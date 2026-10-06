// Mirror of SDRAM channel 3 writes to the flash area into DDR3.
//
// Copyright (C) 2026 Lee Foot
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation; either version 2 of the License, or (at your option)
// any later version. This program is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
// Public License for more details.
//
// The flash area stays in SDRAM (0x1000000-0x19FFFFF: U30, U27, U56, U55,
// U29, docs/zn2_layer_design.md 13.4) for the main CPU, and the Taito Zoom
// reads U27 and the waves from a copy in DDR3 at the same offset in the
// core's window (byte 0x31000000 + offset, docs/ddr3_bandwidth.md 5.1 on
// branch ddr3-bandwidth). Every channel 3 write into the area (the MRA flash
// download and the glue's flash programming) is copied here.
//
// Source side (clk_src, sdram.sv's clk_base): w_req is the one-cycle request
// of a channel 3 write (zn2_ch3_arb ch3_req with ch3_rnw = 0), w_addr a byte
// address (bits 1:0 zero), w_din the 32-bit word, little-endian as sdram.sv
// writes it (din[15:0] at the lower address), w_be its byte enables. Writes
// outside the area are ignored. stall asks zn2_ch3_arb not to start a new
// request while the FIFO is nearly full, so no write is ever dropped.
// DDR3 side (clk_2x): one-beat writes on gnet_ddr3_arb's G port (Avalon),
// the 32-bit word in its half of the qword (address bit 2).
// Crossings follow rtl/gnet/cdc/cdc.sdc's names (cdc_tx_* to cdc_rx_s1*,
// bounded at 14 ns there): the Gray pointers, the overflow flag. Each
// pointer bus moves at most once per source period (20 ns at clk_cpu, 14.76
// ns at clk_2x), above the 14 ns bound, so one sample never mixes two
// increments.

module gnet_ddr3_mirror #(
    parameter int AW = 5                    // FIFO depth 2^AW
) (
    input  logic        clk_src,
    input  logic        w_req,
    input  logic [26:0] w_addr,
    input  logic [31:0] w_din,
    input  logic  [3:0] w_be,
    output logic        stall,

    input  logic        clk2x,
    output logic        g_we,
    output logic [28:0] g_addr,
    output logic [63:0] g_din,
    output logic  [7:0] g_be,
    input  logic        g_busy,

    output logic        ovf                 // sticky, clk2x domain (should never set)
);
    localparam logic [26:0] LO = 27'h1000000, HI = 27'h1A00000;
    localparam int D = 1 << AW;

    function automatic logic [AW:0] g2b(input logic [AW:0] g);
        logic [AW:0] b;
        b[AW] = g[AW];
        for (int i = AW - 1; i >= 0; i--) b[i] = b[i + 1] ^ g[i];
        return b;
    endfunction

    (* ramstyle = "M10K" *) logic [60:0] mem [D];   // addr[26:2], din, be
    logic [AW:0] wp = '0, cdc_tx_wptr = '0, rp = '0, cdc_tx_rptr = '0;
    logic [AW:0] cdc_rx_s1_rptr = '0, cdc_rx_s2_rptr = '0, cdc_rx_s1_wptr = '0, cdc_rx_s2_wptr = '0;
    logic        cdc_tx_ovf = 1'b0, cdc_rx_s1_ovf = 1'b0, cdc_rx_s2_ovf = 1'b0;

    // source side
    wire         hit   = w_req && w_addr >= LO && w_addr < HI;
    wire [AW:0]  level = wp - g2b(cdc_rx_s2_rptr);
    assign stall = level >= (AW + 1)'(D - 4);
    always_ff @(posedge clk_src) begin
        cdc_rx_s1_rptr <= cdc_tx_rptr; cdc_rx_s2_rptr <= cdc_rx_s1_rptr;
        if (hit) begin
            if (level == (AW + 1)'(D)) cdc_tx_ovf <= 1'b1;
            else begin
                mem[wp[AW-1:0]] <= {w_addr[26:2], w_din, w_be};
                wp   <= wp + 1'd1;
                cdc_tx_wptr <= (wp + 1'd1) ^ ((wp + 1'd1) >> 1);
            end
        end
    end

    // DDR3 side: head register refilled from the RAM (registered read)
    wire         empty = (g2b(cdc_rx_s2_wptr) == rp);
    logic [60:0] h;
    logic        hv = 1'b0;
    wire         pop = hv && !g_busy;
    assign g_we   = hv;
    assign g_addr = 29'h6000000 + {5'd0, h[60:37]};          // window base + addr[26:3]
    assign g_din  = {2{h[35:4]}};
    assign g_be   = h[36] ? {h[3:0], 4'b0000} : {4'b0000, h[3:0]};
    always_ff @(posedge clk2x) begin
        cdc_rx_s1_wptr <= cdc_tx_wptr; cdc_rx_s2_wptr <= cdc_rx_s1_wptr;
        cdc_rx_s1_ovf <= cdc_tx_ovf; cdc_rx_s2_ovf <= cdc_rx_s1_ovf;
        if (cdc_rx_s2_ovf) ovf <= 1'b1;
        if ((!hv || pop) && !empty) begin
            h    <= mem[rp[AW-1:0]];
            hv   <= 1'b1;
            rp   <= rp + 1'd1;
            cdc_tx_rptr <= (rp + 1'd1) ^ ((rp + 1'd1) >> 1);
        end else if (pop) begin
            hv <= 1'b0;
        end
    end
    initial ovf = 1'b0;
endmodule
