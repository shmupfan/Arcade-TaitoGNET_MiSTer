// Flash area copy from DDR3 to SDRAM after an MRA DDR3 load (issue #12,
// docs/i12_ddr3_load.md).
//
// Copyright (C) 2026 Lee Foot
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This program is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation; either version 2 of the License, or (at your option)
// any later version. This program is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
// Public License for more details.
//
// Origin: written for this core (own implementation, no code copied from
//         other projects).
// Evidence: Main_MiSTer's DDR3 load (support/arcade/mra_loader.cpp
//           rom_finish, user_io.cpp user_io_set_download, at Main_MiSTer
//           63186a3) and sys/hps_io.sv FIO_FILE_TX, as read in
//           docs/i12_ddr3_load.md 3; flash area layout
//           docs/zn2_layer_design.md 13.4. Bench: sim/ddr3arb/ (run.sh
//           flcopy, tb_flcopy.cpp, flcopy_mutants.py), full system
//           sim/fullsys/zn2fulldl.sh (docs/i12_ddr3_load.md 6 and 7).
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
// Integrity passes (issue #12 hardware result, docs/i12_ddr3_load.md 13):
// after the copy the module reads every word back from SDRAM through the
// same channel 3 path (w_req with w_rnw = 1, the word in r_data at w_done;
// all byte enables, so the SDRAM read DQM landmine does not apply) and then
// reads the DDR3 area once more (the flash mirror has rewritten it from the
// SDRAM writes; this is what the Taito Zoom reads). It keeps three 32-bit
// sums of the 32-bit words: sum_copy (as read from DDR3 and written to
// SDRAM, Main's data), sum_sdram (read back), sum_ddr3 (re-read). flags:
// bit 0 the last copy and both passes finished, bit 1 sum_sdram differs
// from sum_copy, bit 2 sum_ddr3 differs from sum_copy, bit 3 busy. The
// debug overlay's DR row shows them (PSX.sv).
//
// busy is high from the clk1x edge that takes start until the last pass is
// done; start is ignored while busy. Nothing is reset except at power-up:
// a pass always ends with every requested beat received.
//
// Bounded (hardware result 2026-10-20: with the integrity passes Main never
// left the load, so a wait never ended on the MiSTer): if the clk1x side
// makes no progress (no state change, no w_done) for 2^TMO_BITS clk1x
// cycles (2^25: 0.99 s), it gives up: busy drops (the core leaves reset,
// Main goes on), flags bit 3 is set and tmo_info records where it stuck:
// [23:20] state (1 ACK, 2 CHECK waiting for a DDR3 beat, 4 W0_WAIT / 6
// W1_WAIT waiting for a channel 3 write, 9 RB_WAIT waiting for a channel 3
// read), [19] DDR3 re-read pass, [18] buffer empty (no beat ready), [17]
// read command waiting on the glue port, [16] 0, [15:0] low bits of the
// qword (copy, re-read) or word (read-back) index.
// DDR3 reads (hardening after the same result): BURST beats per read and
// at most MAXOUT reads outstanding (16 and 1), so the copier never has
// back-to-back bursts in flight on the glue port; the copy is bound by the
// channel 3 writes (about 800 ns per qword), so this costs nothing there.
//
// Second hardware result (2026-10-21, d13, Ray Crisis full DDR3 load): DR
// row 053E C8A7, so the copy sum was not the file's (3ECBA9) and the DDR3
// re-read disagreed with the copy, while the SDRAM read-back agreed. Two
// reads of the same data through the buffer disagreed. Two changes:
// - The clk1x side sees rcv through two registers (rcv_s), so a qword is
//   read from the buffer at least one clk1x period plus one clk2x period
//   after its write. Before, the read could come one clk2x period after the
//   write, inside the M10K's mixed-clock read-during-write window (the
//   output is undefined there; timing analysis does not cover it, and the
//   simulation model always returns the new data).
// - Up to TRIES copies: when either check fails, the copy starts again
//   (PSX.sv keeps the flash mirror off while busy, so the DDR3 area still
//   holds Main's data for the next try). retried is set when a copy was
//   repeated; flags describe the last one.

module gnet_ddr3_flcopy #(
    parameter logic [28:0] BASEQ = 29'h6200000,    // DDR3 qword address of byte 0x31000000
    parameter logic [26:0] SBASE = 27'h1000000,    // SDRAM byte address of the flash area
    parameter int          MAXW  = 32'h280000,     // 32-bit words in the flash area (0xA00000 bytes)
    parameter int          BURST = 16,             // beats per DDR3 read
    parameter int          MAXOUT = 1,             // DDR3 reads in flight
    parameter int          TMO_BITS = 25,          // no-progress timeout, 2^TMO_BITS clk1x
    parameter int          TRIES = 3               // copies before giving up on the checks (1 to 4)
) (
    // clk1x side
    input  logic        clk1x,
    input  logic        start,          // one clk1x pulse
    input  logic [26:0] len,            // bytes (Main's DDR3 load length)
    output logic        busy = 1'b0,
    output logic        w_req = 1'b0,
    output logic        w_rnw = 1'b0,   // 1: read w_addr (integrity pass), the word comes in r_data with w_done
    output logic [26:0] w_addr = '0,
    output logic [31:0] w_data = '0,
    input  logic        w_done,
    input  logic [31:0] r_data,

    // clk2x side: glue port of gnet_ddr3_arb (reads only)
    input  logic        clk2x,
    output logic        g_rd = 1'b0,
    output logic [28:0] g_addr = '0,
    output logic  [7:0] g_burstcnt = 8'd1,
    input  logic        g_busy,
    input  logic        g_dout_ready,
    input  logic [63:0] g_dout,

    // status (clk1x)
    output logic [31:0] sum_copy = '0,
    output logic [31:0] sum_sdram = '0,
    output logic [31:0] sum_ddr3 = '0,
    output logic  [3:0] flags,
    output logic        retried = 1'b0,
    output logic [23:0] tmo_info = '0
);
    localparam int DW = 8;                  // buffer 2^DW qwords
    localparam int DEPTH = 1 << DW;

    // ------------------------------------------------------------ clk1x side
    typedef enum logic [3:0] {IDLE, ACK, CHECK, W0, W0_WAIT, W1, W1_WAIT, SUM, RB_REQ, RB_WAIT} t_st;
    t_st         st = IDLE;
    logic        job = 1'b0;                // toggles per DDR3 pass
    logic        pass_ddr = 1'b0;           // 0: the copy pass, 1: the DDR3 re-read pass
    logic [21:0] nw = '0;                   // 32-bit words
    logic [20:0] nq = '0;                   // qwords to read
    logic [20:0] cons = '0;                 // qwords taken from the buffer
    logic [21:0] k = '0;                    // read-back word index
    logic        ok = 1'b0, bad_sdram = 1'b0, bad_ddr3 = 1'b0, tmo = 1'b0;
    logic [TMO_BITS:0] idle_cnt = '0;      // clk1x cycles without progress
    t_st         st_1 = IDLE;
    logic        g_wait;                    // clk2x: a read command waits on the glue port
    logic [63:0] q;
    logic [20:0] rcv;                       // clk2x: qwords received
    logic        job_ack;                   // clk2x: job seen
    logic [20:0] rcv_s1 = '0, rcv_s = '0;   // rcv two clk1x edges late (buffer read margin)
    logic  [1:0] tries = '0;                // copies started in this job, minus one

    (* ramstyle = "M10K" *) logic [63:0] buffer [DEPTH];
    always_ff @(posedge clk1x) q <= buffer[cons[DW-1:0]];

    wire [26:0] len_c = (len > 27'(MAXW * 4)) ? 27'(MAXW * 4) : len;
    wire [21:0] nw_c  = 22'((len_c + 27'd3) >> 2);
    wire        hi_ok = {cons, 1'b1} < nw;  // the qword's high word is inside the length

    assign flags = {tmo, bad_ddr3, bad_sdram, ok};

    always_ff @(posedge clk1x) begin
        w_req  <= 1'b0;
        st_1   <= st;
        rcv_s1 <= rcv;
        rcv_s  <= rcv_s1;
        if (!busy || st != st_1 || w_done) idle_cnt <= '0;
        else idle_cnt <= idle_cnt + 1'd1;
        if (busy && idle_cnt[TMO_BITS]) begin
            tmo      <= 1'b1;
            tmo_info <= {st, pass_ddr, rcv_s == cons, g_wait, 1'b0,
                         (st == RB_REQ || st == RB_WAIT) ? k[15:0] : 16'(cons)};
            busy     <= 1'b0;
            idle_cnt <= '0;
            st       <= IDLE;
        end else
        case (st)
            IDLE:
                if (start) begin
                    nw        <= nw_c;
                    nq        <= 21'((nw_c + 22'd1) >> 1);
                    cons      <= '0;
                    job       <= ~job;
                    rcv_s1    <= '0;        // forget the last pass's count (clk2x clears rcv before the next clk1x edge)
                    rcv_s     <= '0;
                    pass_ddr  <= 1'b0;
                    sum_copy  <= '0;
                    sum_sdram <= '0;
                    sum_ddr3  <= '0;
                    ok        <= 1'b0;
                    tmo       <= 1'b0;
                    tmo_info  <= '0;
                    bad_sdram <= 1'b0;
                    bad_ddr3  <= 1'b0;
                    retried   <= 1'b0;
                    tries     <= '0;
                    busy      <= 1'b1;
                    st        <= ACK;
                end
            ACK:                            // clk2x has cleared its counters for this pass
                if (job_ack == job) st <= CHECK;
            CHECK:
                if (cons == nq) begin
                    if (!pass_ddr) begin
                        k  <= '0;
                        st <= RB_REQ;
                    end else if ((sum_sdram != sum_copy || sum_ddr3 != sum_copy) &&
                                 32'(tries) < TRIES - 1) begin
                        // a check failed: copy again from the start
                        tries     <= tries + 1'd1;
                        retried   <= 1'b1;
                        cons      <= '0;
                        job       <= ~job;
                        rcv_s1    <= '0;
                        rcv_s     <= '0;
                        pass_ddr  <= 1'b0;
                        sum_copy  <= '0;
                        sum_sdram <= '0;
                        sum_ddr3  <= '0;
                        st        <= ACK;
                    end else begin
                        ok        <= 1'b1;
                        bad_sdram <= sum_sdram != sum_copy;
                        bad_ddr3  <= sum_ddr3 != sum_copy;
                        busy      <= 1'b0;
                        st        <= IDLE;
                    end
                end else if (rcv_s != cons) begin
                    st <= pass_ddr ? SUM : W0;  // q <= buffer[cons] at this edge holds the qword
                end
            W0: begin
                w_req    <= 1'b1;
                w_rnw    <= 1'b0;
                w_addr   <= SBASE + 27'({cons, 3'b000});
                w_data   <= q[31:0];
                sum_copy <= sum_copy + q[31:0];
                st       <= W0_WAIT;
            end
            W0_WAIT:
                if (w_done) begin
                    if (hi_ok) st <= W1;
                    else begin
                        cons <= cons + 1'd1;
                        st   <= CHECK;
                    end
                end
            W1: begin
                w_req    <= 1'b1;
                w_rnw    <= 1'b0;
                w_addr   <= SBASE + 27'({cons, 3'b100});
                w_data   <= q[63:32];
                sum_copy <= sum_copy + q[63:32];
                st       <= W1_WAIT;
            end
            W1_WAIT:
                if (w_done) begin
                    cons <= cons + 1'd1;
                    st   <= CHECK;
                end
            SUM: begin                      // DDR3 re-read pass
                sum_ddr3 <= sum_ddr3 + q[31:0] + (hi_ok ? q[63:32] : 32'd0);
                cons     <= cons + 1'd1;
                st       <= CHECK;
            end
            RB_REQ:                         // SDRAM read-back pass
                if (k == nw) begin
                    pass_ddr <= 1'b1;
                    cons     <= '0;
                    job      <= ~job;
                    rcv_s1   <= '0;
                    rcv_s    <= '0;
                    st       <= ACK;
                end else begin
                    w_req  <= 1'b1;
                    w_rnw  <= 1'b1;
                    w_addr <= SBASE + 27'({k, 2'b00});
                    st     <= RB_WAIT;
                end
            RB_WAIT:
                if (w_done) begin
                    sum_sdram <= sum_sdram + r_data;
                    k         <= k + 1'd1;
                    st        <= RB_REQ;
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
    // reads in flight: requested beats not yet received
    wire         few    = (req - rcv_r) <= 21'((MAXOUT - 1) * BURST);
    assign g_wait = g_rd;
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
            end else if (active && left != 0 && room && few) begin
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
