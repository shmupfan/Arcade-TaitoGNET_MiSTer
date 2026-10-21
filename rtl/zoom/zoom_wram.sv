// zoom_wram: Taito Zoom board MN10200 work RAM (Taito G-NET core)
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
// Evidence: Sharp LH52B256 32 KB SRAM on the FC PCB (PLAN.md R7,
//           docs/evidence_sources.md); MAME 0.288 taito_zm.cpp:121.
// Design: docs/zoom_board_design.md 4.2.
// Bench: sim/zoomboard/.
//
// Taito Zoom board: MN10200 work RAM (docs/zoom_board_design.md 4.2).
//
// The FC PCB carries one LH52B256 (32 KB, PLAN.md R7); MAME maps 128 KB at
// 0x400000-0x41FFFF (taito_zm.cpp:121). 2^AW words of 16 bits, mirrored
// across the window; AW = 14 is the PCB's 32 KB. The firmware stays below
// 0x408000 (docs/mn10200_design.md 3.4); the bus decoder flags any access
// above the RAM size.
//
// Read on clk2x (see zoom_pcache.sv). At CLK_H 4 (the release) the MN10200
// side also runs on clk2x, so read data arrive one wait clock after the
// address (cur marks it). At CLK_H 2 the core runs on clk_1x: data for the
// address the core put on the bus at a clk_1x edge are valid before the next
// clk_1x edge, and a write held for one clk_1x cycle is written twice with
// the same data, which is harmless.
module zoom_wram #(
    parameter int AW = 14
) (
    input  logic          clk2x,
    input  logic [AW-1:0] a,            // word address
    input  logic          we,
    input  logic [1:0]    be,
    input  logic [15:0]   wd,
    output logic [15:0]   q,
    output logic          cur           // q belongs to address a
);
    logic [1:0][7:0] mem [0:(1<<AW)-1];
    logic [AW-1:0]   qa;

`ifdef VERILATOR
    initial for (int i = 0; i < (1<<AW); i++) mem[i] = '0;
`endif

    always_ff @(posedge clk2x) begin
        if (we) begin
            if (be[0]) mem[a][0] <= wd[7:0];
            if (be[1]) mem[a][1] <= wd[15:8];
        end
        q  <= mem[a];
        qa <= a;
    end
    assign cur = (qa == a);
endmodule
