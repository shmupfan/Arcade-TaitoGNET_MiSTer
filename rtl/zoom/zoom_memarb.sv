// zoom_memarb: Taito Zoom board wave and program memory arbiter (Taito G-NET
// core)
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
// Evidence: none needed beyond the design (an in-order two-client line port).
// Design: docs/zoom_board_design.md 5.
// Bench: sim/zoomboard/.
//
// Taito Zoom board: wave and program memory arbiter (docs/zoom_board_design.md 5).
//
// Two clients share one 64-bit line port into the flash area: the MN10200
// program cache (client P) and the ZSG-2 prefetcher (client Z). Protocol on
// every side: req and line held until ready; responses (rvalid with 64-bit
// data) come back in request order, any latency, several outstanding. The
// arbiter grants P first: a cache miss stalls the CPU at once, while a ZSG-2
// prefetch has a sample period of slack (docs/zsg2_rtl.md 5). A small FIFO
// remembers the owner of each outstanding request to route the responses.
//
// Downstream (psx_top zoom_m_*, PSX.sv): in the release (GNET_DDR3_ARB) the
// G-NET DDR3 arbiter's Zoom port reads the flash mirror in DDR3
// (rtl/gnet/gnet_ddr3_arb.sv, gnet_ddr3_zport.sv). The archived experiment
// revision GNET_Z1_ZOOM (macro GNET_ZOOM_SDRAM, tag experiments-archive) read
// SDRAM channel 3 through rtl/gnet/zoom_sdram_link.vhd.
//
// The line port has no byte enables: every request reads a whole 64-bit
// line. Anything that carries it to SDRAM must issue full-width reads (byte
// enables 1111, see zoom_line32.sv); partial read masks blank data on real
// SDRAM.
module zoom_memarb #(
    parameter int OW = 3                // up to 2^OW requests outstanding downstream
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        p_req,
    input  logic [20:0] p_line,
    output logic        p_ready,
    output logic        p_rvalid,
    input  logic        z_req,
    input  logic [20:0] z_line,
    output logic        z_ready,
    output logic        z_rvalid,
    output logic        m_req,
    output logic [20:0] m_line,
    input  logic        m_ready,
    input  logic        m_rvalid,
    output logic        dbg_ovf         // sticky: a response arrived with no request outstanding
);
    logic [(1<<OW)-1:0] own;            // owner bit per slot: 1 = P
    logic [OW:0]        wp, rp;
    localparam logic [OW:0] K_FULL = 1 << OW;
    wire  [OW:0]        occ  = wp - rp;
    wire                full = occ == K_FULL;

    wire sel_p = p_req;
    assign m_req   = (p_req || z_req) && !full;
    assign m_line  = sel_p ? p_line : z_line;
    assign p_ready = m_ready && !full && sel_p;
    assign z_ready = m_ready && !full && !sel_p && z_req;

    wire head_p = own[rp[OW-1:0]];
    assign p_rvalid = m_rvalid && head_p;
    assign z_rvalid = m_rvalid && !head_p;

    always_ff @(posedge clk) begin
        if (rst) begin
            wp <= '0; rp <= '0; dbg_ovf <= 1'b0;
        end else begin
            if (m_req && m_ready) begin
                own[wp[OW-1:0]] <= sel_p;
                wp <= wp + 1'd1;
            end
            if (m_rvalid) begin
                if (wp == rp) dbg_ovf <= 1'b1;
                rp <= rp + 1'd1;
            end
        end
    end
endmodule
