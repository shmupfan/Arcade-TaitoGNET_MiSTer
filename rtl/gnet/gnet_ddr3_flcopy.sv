// Flash area copy from DDR3 to SDRAM after an MRA DDR3 load (issue #12,
// docs/i12_ddr3_load.md).
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
// With <rom index="3" address="0x31000000"> Main_MiSTer copies the flash
// images (U30, U27, U56, U55, U29: 10 MB) straight into DDR3 at byte
// 0x31000000, which is the core's window (0x30000000) plus the flash area
// offset 0x1000000, the same place gnet_ddr3_mirror keeps its copy for the
// Taito Zoom. The main CPU reads the flash from SDRAM 0x1000000, so after
// the download this module copies len bytes from DDR3 0x31000000 + i to
// SDRAM 0x1000000 + i.
//
// DDR3 side (clk2x): 64-beat reads on gnet_ddr3_arb's glue port (through
// gnet_ddr3_gmux, behind the flash mirror) into a 256-qword buffer; a burst
// is only issued while the buffer has room for it.
// SDRAM side (clk1x): each qword becomes two 32-bit writes, the low half at
// the lower address (DDR3 byte 8k in bits 7:0, as Main's memcpy left it;
// sdram.sv writes din[15:0] at the lower address), handed to PSX.sv's
// download write path (ramdownload_*, the cdc_handshake to channel 3), one
// at a time: w_req is a one-clk1x pulse with w_addr and w_data held, w_done
// the channel's done pulse. The writes go through zn2_ch3_arb, so the flash
// mirror sees them and writes the same bytes back into DDR3.
//
// clk1x and clk2x come from one PLL with aligned rising edges (clk2x = 2 x
// clk1x), so each side reads the other's counters directly: a clk1x register
// is stable over both clk2x edges of its period, and a clk2x register is
// seen at the next clk1x edge. Both counters only grow during a copy, so a
// late sample is always on the safe side (less room, fewer qwords ready).
// The buffer is written on clk2x and read on clk1x; a qword is read only
// after rcv shows it written, at least one clk2x period later.
//
// busy is high from the clk1x edge that takes start until the last write is
// done; start is ignored while busy. Nothing is reset except at power-up:
// a copy always ends with every requested beat received.

module gnet_ddr3_flcopy #(
    parameter logic [28:0] BASEQ = 29'h6200000,    // DDR3 qword address of byte 0x31000000
    parameter logic [26:0] SBASE = 27'h1000000,    // SDRAM byte address of the flash area
    parameter int          MAXW  = 32'h280000      // 32-bit words in the flash area (0xA00000 bytes)
) (
    // clk1x side
    input  logic        clk1x,
    input  logic        start,          // one clk1x pulse
    input  logic [26:0] len,            // bytes (Main's DDR3 load length)
    output logic        busy = 1'b0,
    output logic        w_req = 1'b0,
    output logic [26:0] w_addr = '0,
    output logic [31:0] w_data = '0,
    input  logic        w_done,

    // clk2x side: glue port of gnet_ddr3_arb (reads only)
    input  logic        clk2x,
    output logic        g_rd = 1'b0,
    output logic [28:0] g_addr = '0,
    output logic  [7:0] g_burstcnt = 8'd1,
    input  logic        g_busy,
    input  logic        g_dout_ready,
    input  logic [63:0] g_dout,

    // status (clk1x): qwords copied in the last copy
    output logic [20:0] done_q
);
    localparam int DW = 8;                  // buffer 2^DW qwords
    localparam int DEPTH = 1 << DW;
    localparam int BURST = 64;

    // ------------------------------------------------------------ clk1x side
    typedef enum logic [2:0] {IDLE, ACK, CHECK, W0, W0_WAIT, W1, W1_WAIT} t_st;
    t_st         st = IDLE;
    logic        job = 1'b0;                // toggles per copy
    logic [21:0] nw = '0;                   // 32-bit words to write
    logic [20:0] nq = '0;                   // qwords to read
    logic [20:0] cons = '0;                 // qwords written to SDRAM
    logic [63:0] q;
    logic [20:0] rcv;                       // clk2x: qwords received
    logic        job_ack;                   // clk2x: job seen

    (* ramstyle = "M10K" *) logic [63:0] buffer [DEPTH];
    always_ff @(posedge clk1x) q <= buffer[cons[DW-1:0]];

    wire [26:0] len_c = (len > 27'(MAXW * 4)) ? 27'(MAXW * 4) : len;
    wire [21:0] nw_c  = 22'((len_c + 27'd3) >> 2);

    assign done_q = cons;

    always_ff @(posedge clk1x) begin
        w_req <= 1'b0;
        case (st)
            IDLE:
                if (start) begin
                    nw   <= nw_c;
                    nq   <= 21'((nw_c + 22'd1) >> 1);
                    cons <= '0;
                    job  <= ~job;
                    busy <= 1'b1;
                    st   <= ACK;
                end
            ACK:                            // clk2x has cleared its counters for this job
                if (job_ack == job) st <= CHECK;
            CHECK:
                if (cons == nq) begin
                    busy <= 1'b0;
                    st   <= IDLE;
                end else if (rcv != cons) begin
                    st <= W0;               // q <= buffer[cons] at this edge holds the qword
                end
            W0: begin
                w_req  <= 1'b1;
                w_addr <= SBASE + 27'({cons, 3'b000});
                w_data <= q[31:0];
                st     <= W0_WAIT;
            end
            W0_WAIT:
                if (w_done) begin
                    if ({cons, 1'b1} < nw) st <= W1;
                    else begin
                        cons <= cons + 1'd1;
                        st   <= CHECK;
                    end
                end
            W1: begin
                w_req  <= 1'b1;
                w_addr <= SBASE + 27'({cons, 3'b100});
                w_data <= q[63:32];
                st     <= W1_WAIT;
            end
            W1_WAIT:
                if (w_done) begin
                    cons <= cons + 1'd1;
                    st   <= CHECK;
                end
            default: st <= IDLE;
        endcase
    end

    // ------------------------------------------------------------ clk2x side
    logic        job_seen = 1'b0;
    logic [20:0] req = '0;                  // qwords requested
    logic [20:0] rcv_r = '0;
    assign rcv = rcv_r;
    assign job_ack = job_seen;

    wire  [20:0] left   = nq - req;
    wire  [20:0] bc     = (left > 21'(BURST)) ? 21'(BURST) : left;
    // room: requested but not yet written to SDRAM, plus this burst, fits
    wire         room   = (req - cons + bc) <= 21'(DEPTH);
    wire         active = (job_seen == job) && busy;

    always_ff @(posedge clk2x) begin
        if (job != job_seen) begin
            job_seen <= job;
            req      <= '0;
            rcv_r    <= '0;
            g_rd     <= 1'b0;
        end else begin
            if (g_dout_ready) begin
                buffer[rcv_r[DW-1:0]] <= g_dout;
                rcv_r <= rcv_r + 1'd1;
            end
            if (g_rd && g_busy) begin
                // command waiting: held unchanged (Avalon)
            end else if (active && left != 0 && room) begin
                g_rd       <= 1'b1;
                g_addr     <= BASEQ + {8'd0, req};
                g_burstcnt <= bc[7:0];
                req        <= req + bc;
            end else begin
                g_rd <= 1'b0;
            end
        end
    end
endmodule
