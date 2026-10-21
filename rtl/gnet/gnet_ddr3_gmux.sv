// Two Avalon masters on gnet_ddr3_arb's glue port (docs/ddr3_arbiter.md 7).
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
//         other projects); from development branch ddr3-card (126e964),
//         unchanged apart from these comments.
// Evidence: none needed (glue between two of this core's masters and its
//           arbiter). Bench: sim/ddr3arb/ (run.sh flcopy, tb_flcopy_top.sv
//           wires it as PSX.sv does).
//
// a: writes only, one beat (gnet_ddr3_mirror), first. b: reads and one-beat
// writes: in this tree gnet_ddr3_flcopy, which only reads (PSX.sv,
// GNET_DDR3_LOAD; docs/i12_ddr3_load.md); the card sector engine it was
// written for (gnet_card_sector, branch ddr3-card) is not in this tree.
// Combinational: the arbiter takes a glue command
// only in the cycle it drops g_busy, so the command offered may change before
// that; each master keeps its own command until it sees its busy low. All
// read beats belong to b.

module gnet_ddr3_gmux (
    input  logic        a_we,
    input  logic [28:0] a_addr,
    input  logic [63:0] a_din,
    input  logic  [7:0] a_be,
    output logic        a_busy,

    input  logic        b_rd,
    input  logic        b_we,
    input  logic [28:0] b_addr,
    input  logic  [7:0] b_burstcnt,
    input  logic [63:0] b_din,
    input  logic  [7:0] b_be,
    output logic        b_busy,
    output logic        b_dout_ready,

    output logic        g_rd,
    output logic        g_we,
    output logic [28:0] g_addr,
    output logic  [7:0] g_burstcnt,
    output logic [63:0] g_din,
    output logic  [7:0] g_be,
    input  logic        g_busy,
    input  logic        g_dout_ready
);
    wire sel_a = a_we;
    assign g_rd       = sel_a ? 1'b0   : b_rd;
    assign g_we       = sel_a ? 1'b1   : b_we;
    assign g_addr     = sel_a ? a_addr : b_addr;
    assign g_burstcnt = sel_a ? 8'd1   : b_burstcnt;
    assign g_din      = sel_a ? a_din  : b_din;
    assign g_be       = sel_a ? a_be   : b_be;
    assign a_busy       = g_busy || !sel_a;
    assign b_busy       = g_busy || sel_a;
    assign b_dout_ready = g_dout_ready;
endmodule
