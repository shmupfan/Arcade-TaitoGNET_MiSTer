// Zoom line port (clk_1x) to the DDR3 arbiter's Z port (clk_2x).
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
// zoom_board's m_* port (zoom_memarb, clk_1x) on one side, gnet_ddr3_arb's
// z_* port (clk_2x) on the other. clk_1x and clk_2x come from one PLL and
// are phase aligned: every clk_1x edge is a clk_2x edge. Everything here is
// on clk_2x; s_end marks the clk_2x cycles that end on a clk_1x edge
// (worked out as psx_top.vhd's clk2xIndex does).
//   Requests: taken at a clk_1x edge into a one-entry register while it is
//     free (m_ready from registered state only, so the Zoom's request path
//     stays out of the arbiter's and the GPU's logic); the register is
//     offered to the arbiter's Z port. m_line is taken at that edge only (it
//     may change while a request waits).
//   Responses: arbiter beats (any clk_2x cycle) go into a return queue;
//     at each clk_1x edge one leaves as a one-clk_1x m_rvalid pulse.
//   Zoom reset (zrst, clk_1x domain, the PS1-group reset): the queue is
//     emptied and the beats still owed by the arbiter for requests made
//     before the reset are counted and dropped, so nothing requested before
//     a reset is answered after it. No request is taken during zrst.
// At most 2^QW requests are open (zoom_memarb OW = 3: 8); the queue has the
// same depth, so it cannot overflow.

module gnet_ddr3_zport #(
    parameter int QW = 3
) (
    input  logic        clk2x,
    input  logic        clk1x,
    input  logic        zrst,           // Zoom-side reset (clk_1x domain)

    // zoom_board m_* (clk_1x)
    input  logic        m_req,
    input  logic [20:0] m_line,
    output logic        m_ready,
    output logic        m_rvalid,
    output logic [63:0] m_rdata,

    // gnet_ddr3_arb z_* (clk_2x)
    output logic        z_req,
    output logic [20:0] z_line,
    input  logic        z_ready,
    input  logic        z_rvalid,
    input  logic [63:0] z_rdata
);
    // clk_1x phase on clk_2x
    logic t1 = 1'b0, t1_2x = 1'b0, idx = 1'b0;
    always_ff @(posedge clk1x) t1 <= ~t1;
    always_ff @(posedge clk2x) begin
        t1_2x <= t1;
        idx   <= (t1_2x == t1);           // 1 in the first half of a clk_1x period
    end
    wire s_end = ~idx;                    // this clk_2x cycle ends on a clk_1x edge

    // one-entry skid register: the Zoom side's request is taken at a clk_1x
    // edge whenever the register is free, and the arbiter sees only the
    // register. m_ready depends on registered state alone, so no path runs
    // from zoom_memarb's request through the arbiter's priority select into
    // the core's BUSY and the GPU's request logic (GNET_Z1FULL STA, clk_2x
    // -0.020 ns, builds/z1full_clk2x). One clk_2x more latency per line.
    logic        hv = 1'b0;
    logic [20:0] hline;
    assign m_ready = s_end && !hv && !zrst;
    assign z_req   = hv && !zrst;
    assign z_line  = hline;
    always_ff @(posedge clk2x) begin
        if (zrst) hv <= 1'b0;
        else if (m_req && m_ready) begin hv <= 1'b1; hline <= m_line; end
        else if (z_req && z_ready) hv <= 1'b0;
    end

    // return queue; owed = answers the arbiter still has to deliver, drop =
    // how many of the next answers belong to requests from before a reset
    // (answers come in request order, so they are the first ones)
    localparam int QD = 1 << QW;
    logic [63:0] q [QD];
    logic [QW:0] wp = '0, rp = '0, owed = '0, drop = '0;
    wire         q_empty = (wp == rp);
    wire         acc     = z_req && z_ready;
    wire [QW:0]  owed_n  = owed + {{QW{1'b0}}, acc} - {{QW{1'b0}}, z_rvalid};
    wire         keep    = z_rvalid && drop == '0 && !zrst;
    logic        rv_q;

    always_ff @(posedge clk2x) begin
        owed <= owed_n;
        if (zrst) drop <= owed_n;
        else if (z_rvalid && drop != '0) drop <= drop - 1'd1;
        if (keep) begin
            q[wp[QW-1:0]] <= z_rdata;
            wp <= wp + 1'd1;
        end
        if (s_end) begin
            rv_q     <= !q_empty && !zrst;
            m_rdata  <= q[rp[QW-1:0]];
            if (!q_empty && !zrst) rp <= rp + 1'd1;
        end
        if (zrst) begin
            wp <= '0; rp <= '0;
        end
    end
    initial rv_q = 1'b0;
    // a pulse registered before a reset is not shown once the reset is there
    assign m_rvalid = rv_q && !zrst;
endmodule
