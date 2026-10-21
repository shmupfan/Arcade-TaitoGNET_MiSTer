// zsg2_ram: simple dual-port RAM for the ZSG-2 (Taito G-NET core)
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
//         other projects); written in the single-clock simple dual-port form
//         that Quartus 17 infers as M10K.
// Evidence: none needed (storage only).
// Design: docs/zsg2_rtl.md 6.
// Bench: sim/zsg2/.
//
// Simple dual-port RAM (one write port, one registered read port, one
// clock) for the ZSG-2 (docs/zsg2_rtl.md). Plain write enable: Quartus 17
// infers M10K from this template (a byte-enable loop variant was not
// inferred and became flip-flops, docs/zsg2_rtl.md 6). Read during write
// of the same address returns the old data.
module zsg2_ram #(
    parameter AW = 8,
    parameter DW = 16
) (
    input  logic          clk,
    input  logic          we,
    input  logic [AW-1:0] waddr,
    input  logic [DW-1:0] wdata,
    input  logic [AW-1:0] raddr,
    output logic [DW-1:0] q
);
    logic [DW-1:0] mem [0:(1<<AW)-1];

`ifdef VERILATOR
    initial for (int i = 0; i < (1<<AW); i++) mem[i] = '0;
`endif

    always_ff @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        q <= mem[raddr];
    end
endmodule
