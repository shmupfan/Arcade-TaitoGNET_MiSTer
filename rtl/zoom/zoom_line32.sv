// zoom_line32: Taito Zoom board 64-bit line port to a 32-bit word port
// (bench only, in no revision) (Taito G-NET core)
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
// Evidence: rtl/sdram.sv read DQM behaviour (cited inline).
// Design: docs/zoom_board_design.md 5.2.
// Bench: sim/zoomboard/ (tb_line32.cpp, build_line32.sh).
//
// Taito Zoom board: 64-bit line port to a 32-bit word port
// (docs/zoom_board_design.md 5.2), written for an SDRAM channel 3 path
// (sdram.sv: 32-bit single accesses, ch3_req sampled once per clk_1x). No
// revision instantiates it: the release reads the flash area from DDR3
// (zoom_memarb.sv), and the SDRAM experiment path GNET_ZOOM_SDRAM uses
// rtl/gnet/zoom_sdram_link.vhd. Only the bench sim/zoomboard (tb_line32)
// builds it.
//
// One line at a time: two word reads, low word (byte 8L) first. The word
// port holds w_req and w_addr until w_ack, which comes with w_rdata; a
// system-level arbiter shares it with the G-NET glue's flash port. The
// flash area holds the images as little-endian 16-bit words (the ROM file
// order, docs/zn2_layer_design.md 13.4), so the line
// is {word at 8L + 4, word at 8L}.
//
// Reads always carry byte enables 1111 (w_be). sdram.sv drives ~be[1:0]
// onto DQMH/DQML with the READ command (channel 3: cas_addr[12:11] take
// ~ch3buf_be[1:0], line 476 at PSX_MiSTer cd17b5a), and with the read
// DQM latency of 2 a partial mask blanks lanes of the burst on real SDRAM;
// simulation models ignore read DQM. Only writes may use lane masks, and
// the Zoom never writes the flash area.
module zoom_line32 (
    input  logic        clk,
    input  logic        rst,
    input  logic        l_req,
    input  logic [20:0] l_line,
    output logic        l_ready,
    output logic        l_rvalid,
    output logic [63:0] l_rdata,
    output logic        w_req,
    output logic [21:0] w_addr,         // byte address bits 23:2
    output logic        w_we,           // always 0: reads only
    output logic [3:0]  w_be,           // always 1111 on reads (see above)
    input  logic        w_ack,
    input  logic [31:0] w_rdata
);
    logic        busy, half;
    logic [20:0] line;
    assign l_ready = !busy;
    assign w_req   = busy;
    assign w_addr  = {line, half};
    assign w_we    = 1'b0;
    assign w_be    = 4'b1111;

    always_ff @(posedge clk) begin
        l_rvalid <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
            half <= 1'b0;
        end else if (!busy) begin
            if (l_req) begin
                busy <= 1'b1;
                half <= 1'b0;
                line <= l_line;
            end
        end else if (w_ack) begin
            if (!half) begin
                l_rdata[31:0] <= w_rdata;
                half <= 1'b1;
            end else begin
                l_rdata[63:32] <= w_rdata;
                l_rvalid <= 1'b1;
                busy <= 1'b0;
            end
        end
    end
endmodule
