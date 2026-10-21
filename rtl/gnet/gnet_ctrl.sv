// G-NET FC PCB control registers and MB3773 watchdog.
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
// Evidence: MAME 0.288 taitogn.cpp (control registers, R15), Fujitsu MB3773
//           datasheet DS04-27401-7E (watchdog, R17); R-items are defined in
//           docs/PLAN.md (research items) and docs/evidence_sources.md.
//           Bench: sim/gnet/ (gnet_fc directed tests), sim/shell/run_pausewd.sh.
//
// Registers (main CPU, MAME 0.288 taitogn.cpp, docs/hardware_inventory.md 4):
//   0x1fb40000 control  8-bit R/W, reset 0x10: bit 5 MB3773 CK, bit 4 Zoom
//                       reset (1 = held), bit 2 flash bank select
//   0x1fb60000 control2 16-bit, write only
//   0x1fa30000 control3 8-bit R/W
//   0x1fb70000 16-bit, reads 0x0002 (R15), writes ignored
// Unmapped bytes read 0 (MAME's behaviour, seen in the oracle).
// Accesses arrive as 16-bit lane operations from gnet_fc.
//
// MB3773 (Fujitsu DS04-27401-7E): a falling edge on CK restarts the
// watchdog; if no edge arrives within the timeout the reset output pulses.
// The timeout on the FC PCB depends on an unknown capacitor (R17), so it is a
// parameter. MAME uses 5 s, a guess. The default here is 8 s: Taito's own Zoom
// init delay loop (Night Raid, Ray Crisis, Shikigami) runs without a kick for
// 2.4 to 2.9 s in MAME, about 3 s or more on a real board (the loop is
// CPU-bound), and 5.081 s for Night Raid in this core's full-system
// simulation at 33.8688 MHz, where a 5 s watchdog reset the game; 8 s leaves
// 2.9 s of margin (docs/gnet_watchdog_mb3773.md, on development branch
// gnet-games, not in this tree). The release uses 8 (PSX.sv localparam
// GNET_WD_TIMEOUT_S, psx_top generic ZN2_WD_TIMEOUT_S; both default to 8).

module gnet_ctrl #(
    parameter int unsigned CLK_HZ       = 33_868_800,
    parameter int unsigned WD_TIMEOUT_S = 8
) (
    input  logic        clk,
    input  logic        rst,          // power-on / system reset

    // 16-bit lane operation
    input  logic        op_req,
    input  logic        op_we,
    input  logic [1:0]  op_reg,       // 0 control, 1 control2, 2 control3, 3 0x1fb70000
    input  logic        op_hi,        // upper 16-bit lane of the 32-bit word
    input  logic [1:0]  op_bmask,     // byte enables within the lane
    input  logic [15:0] op_wdata,
    output logic        op_ack,
    output logic [15:0] op_rdata,

    output logic        zoom_reset,   // control bit 4
    output logic        zoom_release, // pulse: control bit 4 fell (Zoom released)
    output logic        bank_sel,     // control bit 2
    output logic        wd_reset,     // pulse: watchdog expired

    // debug taps (docs/hw_debug_overlay.md): through gnet_fc and zn2_board to
    // zn_dbg_regs, the debug overlay built into the release (OSD, Off by
    // default)
    output logic        wd_kick,      // pulse: CK falling edge restarted the watchdog
    output logic [7:0]  ctrl_q        // control register (reset value 10h)
);
    localparam logic [31:0] WD_CYC = 32'(CLK_HZ) * 32'(WD_TIMEOUT_S);

    logic [7:0]  control;
    logic [15:0] control2;
    logic [7:0]  control3;
    logic [31:0] wd_cnt;

    assign zoom_reset = control[4];
    assign bank_sel   = control[2];
    assign ctrl_q     = control;

    // Only the low byte of the low lane is mapped for control/control3; the
    // whole low lane for control2 and the 0x1fb70000 register.
    wire lo_b0 = op_req && !op_hi && op_bmask[0];

    always_ff @(posedge clk) begin
        op_ack       <= 1'b0;
        zoom_release <= 1'b0;
        wd_reset     <= 1'b0;
        wd_kick      <= 1'b0;
        if (rst) begin
            control  <= 8'h10;
            control2 <= 16'h0000;
            control3 <= 8'h00;
            wd_cnt   <= WD_CYC;
        end else begin
            // watchdog
            if (wd_cnt == 32'd0) begin
                wd_reset <= 1'b1;
                wd_cnt   <= WD_CYC;
            end else begin
                wd_cnt <= wd_cnt - 32'd1;
            end

            if (op_req) begin
                op_ack   <= 1'b1;
                op_rdata <= 16'h0000;
                if (op_we) begin
                    case (op_reg)
                        2'd0: if (lo_b0) begin
                            if (control[5] && !op_wdata[5]) begin               // CK falling edge
                                wd_cnt  <= WD_CYC;
                                wd_kick <= 1'b1;
                            end
                            if (control[4] && !op_wdata[4]) zoom_release <= 1'b1;
                            control <= op_wdata[7:0];
                        end
                        2'd1: if (!op_hi) begin
                            if (op_bmask[0]) control2[7:0]  <= op_wdata[7:0];
                            if (op_bmask[1]) control2[15:8] <= op_wdata[15:8];
                        end
                        2'd2: if (lo_b0) control3 <= op_wdata[7:0];
                        default: ;
                    endcase
                end else begin
                    case (op_reg)
                        2'd0: op_rdata <= op_hi ? 16'h0000 : {8'h00, control};
                        2'd2: op_rdata <= op_hi ? 16'h0000 : {8'h00, control3};
                        2'd3: op_rdata <= op_hi ? 16'h0000 : 16'h0002;
                        default: op_rdata <= 16'h0000;   // control2 is write only
                    endcase
                end
            end
        end
    end
endmodule
