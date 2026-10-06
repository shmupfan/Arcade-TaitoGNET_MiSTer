// Ricoh RF5C296 PC card controller, ExCA register file (G-NET subset).
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
// Indexed access (RF5C296/RF5C396L datasheet p26): byte 0x3E0 of the
// controller I/O space is the index, 0x3E1 the data. The G-NET maps the
// controller I/O space at 0x1fb00000 (gnet_fc routes the 16-bit lane at
// 0x3E0 here; everything else in 0x1fb00000-0x1fb0ffff goes to the card's
// task file through the fixed I/O window, see below).
//
// Register file: 64 x 8 for socket A (indices 00h-3Fh; index bits 7:6
// select the socket, the RF5C296 has one), written as the datasheet
// describes, defaults 00h. Reads:
//   00h Identification and Revision = 83h (p27, read only)
//   01h Interface Status (p27): bit 7 GPI inverted (0), bit 6 power active
//       (from 02h bit 4), bit 5 ready / IREQ# level (1: no request; the card
//       interrupt is not modelled), bit 4 WP (0), bits 3:2 card detect (11 when
//       a card is present), bits 1:0 BVD (11)
//   3Ah Chip Identification = 32h (p47, read only)
//   others: the written value. MAME 0.288 returns 00h for every register; the
//   BIOS never reads one (oracle), so the difference is not visible.
// Index read back: the last index written (as MAME).
// Card reset: 03h bit 6 = 0 holds the card in reset (p38). Level, so the card
// starts its power-on sequence when the bit is set; MAME resets the card at
// each write with bit 6 = 0 instead.
//
// Windows: the BIOS programs I/O window 0 for card I/O 0-15 and memory
// window 0 for attribute memory (docs/gnet_glue_design.md 4), which is the
// fixed mapping gnet_fc decodes. win_mismatch flags a programmed window that
// differs from that mapping once both windows are enabled (debug only).

module gnet_rf5c296 (
    input  logic        clk,
    input  logic        rst,

    input  logic        op_req,
    input  logic        op_we,
    input  logic [1:0]  op_bmask,     // byte 0 = index (3E0h), byte 1 = data (3E1h)
    input  logic [15:0] op_wdata,
    output logic        op_ack,
    output logic [15:0] op_rdata,

    input  logic        card_present,
    output logic        card_reset,   // 1 = card held in reset
    output logic        win_mismatch
);
    logic [7:0] regs [64];
    logic [7:0] index;

    function automatic logic [7:0] rd(input logic [7:0] i);
        if (i[7:6] != 2'b00) rd = 8'hff;               // no socket B
        else case (i[5:0])
            6'h00: rd = 8'h83;
            6'h01: rd = {1'b0, regs[6'h02][4], 1'b1, 1'b0, card_present, card_present, 2'b11};
            6'h3a: rd = 8'h32;
            default: rd = regs[i[5:0]];
        endcase
    endfunction

    assign card_reset = ~regs[6'h03][6];

    // fixed G-NET mapping (values from the oracle, all six games)
    wire iow_en  = regs[6'h06][6];
    wire memw_en = regs[6'h06][0];
    wire iow_ok  = regs[6'h08] == 8'h00 && regs[6'h09] == 8'h00 && regs[6'h0a] == 8'h0f && regs[6'h0b] == 8'h00;
    wire memw_ok = regs[6'h14] == 8'h38 && regs[6'h15][5:0] == 6'h03 && regs[6'h15][6];
    assign win_mismatch = (iow_en && !iow_ok) || (memw_en && !memw_ok);

    always_ff @(posedge clk) begin
        op_ack <= 1'b0;
        if (rst) begin
            for (int i = 0; i < 64; i++) regs[i] <= 8'h00;
            index <= 8'h00;
        end else if (op_req) begin
            op_ack <= 1'b1;
            if (op_we) begin
                if (op_bmask[0]) index <= op_wdata[7:0];
                if (op_bmask[1] && (op_bmask[0] ? op_wdata[7:6] : index[7:6]) == 2'b00)
                    regs[op_bmask[0] ? op_wdata[5:0] : index[5:0]] <= op_wdata[15:8];
            end else begin
                op_rdata <= {rd(index), index};
            end
        end
    end
endmodule
