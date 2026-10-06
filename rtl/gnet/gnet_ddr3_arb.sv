// G-NET DDR3 arbiter: four clients on the emu DDRAM port (docs/ddr3_arbiter.md).
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
// Sits between the clients and the emu DDRAM_* port (Avalon-MM, one command
// per cycle, BUSY = waitrequest, read data in command order), on the port
// clock (clk_2x). Clients, highest priority first (docs/ddr3_bandwidth.md
// 5.2 on branch ddr3-bandwidth):
//   R  rotation: screen_rotate's DDRAM_* outputs (sys/arcade_video.v), on
//      their own clock; a dual-clock FIFO of 2^RAW entries takes every write
//      (screen_rotate ignores BUSY). Writes only.
//   Z  Zoom line port (zoom_memarb's m_* side, branch zoom-board): 64-bit
//      line reads, req held until ready, rvalid in order. m_line is the
//      byte offset / 8 in the flash area (U27 at 0x200000, waves at
//      0x400000, zoom_board.sv:39-40), so line L is qword ZQBASE + L.
//   G  G-NET glue (card sector engine, flash chips in DDR3): Avalon master.
//   C  core (psx_mister's DDRAM side: GPU, SPU and savestates behind the
//      core's own pause arbiter): Avalon master, every remaining slot.
// A client command is taken into a one-entry command register when the
// register is free or is being accepted downstream; an Avalon client sees
// BUSY until that cycle. A write burst (burstcount > 1) locks the port to
// its client until the last beat. Each read command pushes {owner, length}
// into an owner FIFO; DOUT_READY goes to the owner of the head entry only.

module gnet_ddr3_arb #(
    parameter int          RAW    = 9,              // rotation FIFO depth 2^RAW
    parameter int          OFW    = 4,              // owner FIFO depth 2^OFW
    parameter logic [28:0] ZQBASE = 29'h6200000     // Zoom flash area base, byte 0x31000000
) (
    input  logic        clk,
    input  logic        rst,

    // downstream: emu DDRAM_* (DDRAM_CLK = clk)
    input  logic        ddr_busy,
    output logic  [7:0] ddr_burstcnt,
    output logic [28:0] ddr_addr,
    input  logic [63:0] ddr_dout,
    input  logic        ddr_dout_ready,
    output logic        ddr_rd,
    output logic [63:0] ddr_din,
    output logic  [7:0] ddr_be,
    output logic        ddr_we,

    // R: rotation writes, rot_clk domain (screen_rotate DDRAM_CLK = CLK_VIDEO)
    input  logic        rot_clk,
    input  logic        rot_we,
    input  logic [28:0] rot_addr,
    input  logic [63:0] rot_din,
    input  logic  [7:0] rot_be,

    // Z: Zoom line port
    input  logic        z_req,
    input  logic [20:0] z_line,
    output logic        z_ready,
    output logic        z_rvalid,

    // G: glue, Avalon
    input  logic        g_rd,
    input  logic        g_we,
    input  logic [28:0] g_addr,
    input  logic  [7:0] g_burstcnt,
    input  logic [63:0] g_din,
    input  logic  [7:0] g_be,
    output logic        g_busy,
    output logic        g_dout_ready,

    // C: core, Avalon
    input  logic        c_rd,
    input  logic        c_we,
    input  logic [28:0] c_addr,
    input  logic  [7:0] c_burstcnt,
    input  logic [63:0] c_din,
    input  logic  [7:0] c_be,
    output logic        c_busy,
    output logic        c_dout_ready,

    // read data for every client (valid with its own rvalid / dout_ready)
    output logic [63:0] rdata,

    // status (clk domain): rotation FIFO overflow (sticky until reset), its
    // highest fill level, owner FIFO overflow (a protocol error)
    output logic        rot_ovf,
    output logic [RAW:0] rot_hiwater,
    output logic        own_ovf
);
    localparam logic [1:0] O_R = 2'd0, O_Z = 2'd1, O_G = 2'd2, O_C = 2'd3;

    // ------------------------------------------------------------ rotation FIFO
    // dual clock, Gray-coded pointers, 69 bits: address, 32-bit pixel, enables
    // (screen_rotate duplicates the pixel in both halves, arcade_video.v:212).
    // Crossing registers named as rtl/gnet/cdc/cdc.sdc expects (cdc_tx_* to
    // cdc_rx_s1*); in the G-NET revisions CLK_VIDEO is also false-pathed to
    // the emu PLL clocks (GNET_LEAN.sdc).
    localparam int RD = 1 << RAW;
    (* ramstyle = "M10K" *) logic [68:0] rf_mem [RD];
    logic [RAW:0] rf_wp, cdc_tx_wptr, rf_rp, cdc_tx_rptr;
    logic [RAW:0] cdc_rx_s1_rptr, cdc_rx_s2_rptr;     // read pointer into rot_clk
    logic [RAW:0] cdc_rx_s1_wptr, cdc_rx_s2_wptr;     // write pointer into clk
    logic         cdc_tx_rovf;

    function automatic logic [RAW:0] bin2gray(input logic [RAW:0] b);
        return b ^ (b >> 1);
    endfunction
    function automatic logic [RAW:0] gray2bin(input logic [RAW:0] g);
        logic [RAW:0] b;
        b[RAW] = g[RAW];
        for (int i = RAW - 1; i >= 0; i--) b[i] = b[i + 1] ^ g[i];
        return b;
    endfunction

    // reset into the rot_clk domain
    logic cdc_rx_s1_rst, cdc_rx_s2_rst;
    always_ff @(posedge rot_clk) begin cdc_rx_s1_rst <= rst; cdc_rx_s2_rst <= cdc_rx_s1_rst; end

    wire [RAW:0] rf_rp_w = gray2bin(cdc_rx_s2_rptr);
    wire         rf_full = (rf_wp - rf_rp_w) == (RAW + 1)'(RD);
    always_ff @(posedge rot_clk) begin
        cdc_rx_s1_rptr <= cdc_tx_rptr; cdc_rx_s2_rptr <= cdc_rx_s1_rptr;
        if (cdc_rx_s2_rst) begin
            rf_wp <= '0; cdc_tx_wptr <= '0; cdc_tx_rovf <= 1'b0;
        end else if (rot_we) begin
            if (rf_full) begin
                cdc_tx_rovf <= 1'b1;
            end else begin
                rf_mem[rf_wp[RAW-1:0]] <= {rot_addr, rot_din[31:0], rot_be};
                rf_wp   <= rf_wp + 1'd1;
                cdc_tx_wptr <= bin2gray(rf_wp + 1'd1);
            end
        end
    end

    logic        cdc_rx_s1_rovf, cdc_rx_s2_rovf;
    wire [RAW:0] rf_wp_r = gray2bin(cdc_rx_s2_wptr);
    wire         rf_empty = (rf_wp_r == rf_rp);
    wire [RAW:0] rf_level = rf_wp_r - rf_rp;
    logic [68:0] rf_q;                       // head entry (show-ahead register)
    logic        rf_qv;                      // rf_q holds a valid entry
    logic        rf_pop;                     // the head is taken this cycle

    always_ff @(posedge clk) begin
        cdc_rx_s1_wptr <= cdc_tx_wptr; cdc_rx_s2_wptr <= cdc_rx_s1_wptr;
        cdc_rx_s1_rovf <= cdc_tx_rovf; cdc_rx_s2_rovf <= cdc_rx_s1_rovf;
        if (rst) begin
            rf_rp <= '0; cdc_tx_rptr <= '0; rf_qv <= 1'b0;
            rot_ovf <= 1'b0; rot_hiwater <= '0;
        end else begin
            if (cdc_rx_s2_rovf) rot_ovf <= 1'b1;
            if (rf_level > rot_hiwater) rot_hiwater <= rf_level;
            // refill the head register from the RAM (one cycle read)
            if ((!rf_qv || rf_pop) && !rf_empty) begin
                rf_q    <= rf_mem[rf_rp[RAW-1:0]];
                rf_qv   <= 1'b1;
                rf_rp   <= rf_rp + 1'd1;
                cdc_tx_rptr <= bin2gray(rf_rp + 1'd1);
            end else if (rf_pop) begin
                rf_qv <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------ command register
    logic        k_valid, k_rd;
    logic  [1:0] k_own;
    logic  [7:0] wb_rem;        // write-burst beats still to come from wb_own
    logic  [1:0] wb_own;
    logic [OFW:0] of_wp, of_rp;
    wire         of_full = (of_wp - of_rp) == (OFW + 1)'(1 << OFW);

    wire accept = k_valid && !ddr_busy;
    wire load   = !rst && (!k_valid || accept);    // nothing is taken in reset

    // requests; a read needs a free owner FIFO slot (counting the command in
    // the register, which is pushed only when accepted)
    wire rd_room = !of_full && !((of_wp - of_rp) == (OFW + 1)'((1 << OFW) - 1) && k_valid && k_rd);
    wire lock    = wb_rem != 8'd0;
    wire req_r = !lock && rf_qv;
    wire req_z = !lock && z_req && rd_room;
    wire req_g = (lock ? (wb_own == O_G && g_we) : ((g_rd && rd_room) || g_we));
    wire req_c = (lock ? (wb_own == O_C && c_we) : ((c_rd && rd_room) || c_we));

    wire sel_r = load && req_r;
    wire sel_z = load && !req_r && req_z;
    wire sel_g = load && !req_r && !req_z && req_g;
    wire sel_c = load && !req_r && !req_z && !req_g && req_c;

    assign rf_pop  = sel_r;
    assign z_ready = sel_z;
    assign g_busy  = !sel_g;
    assign c_busy  = !sel_c;

    assign ddr_rd = k_valid && k_rd;
    assign ddr_we = k_valid && !k_rd;

    always_ff @(posedge clk) begin
        if (rst) begin
            k_valid <= 1'b0; wb_rem <= 8'd0;
        end else if (load) begin
            k_valid <= sel_r | sel_z | sel_g | sel_c;
            if (sel_r) begin
                k_rd <= 1'b0; k_own <= O_R;
                ddr_addr <= rf_q[68:40];
                ddr_din  <= {2{rf_q[39:8]}};
                ddr_be   <= rf_q[7:0];
                ddr_burstcnt <= 8'd1;
            end else if (sel_z) begin
                k_rd <= 1'b1; k_own <= O_Z;
                ddr_addr <= ZQBASE + {8'd0, z_line};
                ddr_burstcnt <= 8'd1;
                ddr_be <= 8'hFF;
            end else if (sel_g) begin
                k_rd <= g_rd && !lock; k_own <= O_G;
                ddr_addr <= g_addr; ddr_din <= g_din; ddr_be <= g_be;
                ddr_burstcnt <= g_burstcnt;
            end else if (sel_c) begin
                k_rd <= c_rd && !lock; k_own <= O_C;
                ddr_addr <= c_addr; ddr_din <= c_din; ddr_be <= c_be;
                ddr_burstcnt <= c_burstcnt;
            end
            // write bursts: the first beat sets the lock, every beat counts down
            if ((sel_g && !(g_rd && !lock)) || (sel_c && !(c_rd && !lock))) begin
                if (lock) wb_rem <= wb_rem - 8'd1;
                else if ((sel_g ? g_burstcnt : c_burstcnt) > 8'd1) begin
                    wb_rem <= (sel_g ? g_burstcnt : c_burstcnt) - 8'd1;
                    wb_own <= sel_g ? O_G : O_C;
                end
            end
        end
    end

    // ------------------------------------------------------------ owner FIFO
    logic [1:0] of_own [1 << OFW];
    logic [7:0] of_len [1 << OFW];
    logic [7:0] bc;
    wire  [1:0] h_own = of_own[of_rp[OFW-1:0]];
    wire  [7:0] h_len = of_len[of_rp[OFW-1:0]];
    wire        of_empty = (of_wp == of_rp);

    always_ff @(posedge clk) begin
        if (rst) begin
            of_wp <= '0; of_rp <= '0; bc <= 8'd0; own_ovf <= 1'b0;
        end else begin
            if (accept && k_rd) begin
                of_own[of_wp[OFW-1:0]] <= k_own;
                of_len[of_wp[OFW-1:0]] <= ddr_burstcnt;
                of_wp <= of_wp + 1'd1;
            end
            if (ddr_dout_ready) begin
                if (of_empty) own_ovf <= 1'b1;
                if (bc == h_len - 8'd1) begin bc <= 8'd0; of_rp <= of_rp + 1'd1; end
                else bc <= bc + 8'd1;
            end
        end
    end

    assign rdata        = ddr_dout;
    assign z_rvalid     = ddr_dout_ready && !of_empty && h_own == O_Z;
    assign g_dout_ready = ddr_dout_ready && !of_empty && h_own == O_G;
    assign c_dout_ready = ddr_dout_ready && !of_empty && h_own == O_C;
endmodule
