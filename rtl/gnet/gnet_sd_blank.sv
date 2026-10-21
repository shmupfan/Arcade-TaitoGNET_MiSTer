//============================================================================
//
//  G-NET core: horizontal blanking on every line for the scandoubler
//  Copyright (C) 2026 Lee Foot
//  SPDX-License-Identifier: GPL-2.0-or-later
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================
//
// Origin: written for this core (own implementation, no code copied from
//         other projects).
// Evidence: the framework's sys/scandoubler.v (as in PSX_MiSTer cd17b5a,
//           read, not changed) and the PSX video out
//           rtl/gpu_videoout_async.vhd, traced in simulation
//           (docs/i11_scandoubler.md 3 to 5). Bench: sim/shell/
//           run_sd_trace.sh (tb_sd_trace.sv, trace from run_vtrace.sh).
//
// Issue #11 (Scandoubler Fx loses the picture), docs/i11_scandoubler.md.
//
// The PSX video out (rtl/gpu_videoout_async.vhd) keeps hblank high for the
// whole line on every line it does not draw: the vertical blanking lines,
// vsync included (23 of 263 lines in 240p). The G-NET shell passes the
// core's own hblank to arcade_video (GNET_GAME_HBLANK in PSX.sv). The
// framework's scandoubler (sys/scandoubler.v) restarts its line counter and
// shifts its vsync and vblank pipelines only on an hblank falling edge, and
// places its output hsync from positions measured from that edge; with no
// edge for 23 lines its counter runs past every stored position, so the
// 31 kHz output has no hsync for those lines and never raises vsync.
//
// This block gives arcade_video an hblank that falls and rises on every
// line, only while the scandoubler is on (en = Fx not None or the forced
// scandoubler): on a line where the core's hblank does not fall, hblank
// falls and rises at the same dots (counted from the hsync rise) as on the
// last line that was drawn, and vblank is held high over that stretch, so
// arcade_video latches VBlank = 1 for the line (no DE, no picture change).
// On drawn lines, and always with en low, hb_o = hb and vb_o = vb, so the
// output without the scandoubler (direct video, 15 kHz analog, HDMI with
// Fx None) is unchanged on every clock.
//
// Inputs are PSX.sv's video_aspect signals, which change only on ce; the
// outputs are combinational from them and from state updated on ce, so no
// delay is added (arcade_video samples on the same ce).

module gnet_sd_blank
(
	input        clk,
	input        ce,
	input        en,
	input        hs,
	input        hb,
	input        vb,
	output       hb_o,
	output       vb_o
);

reg        hs_q = 0, hb_q = 1;
reg [11:0] pos_r = 0;
reg [11:0] fall_pos = 0, rise_pos = 0;
reg        have_fall = 0, have_rise = 0;
reg        line_fell = 0;
reg        syn_r = 0;

wire        new_line  = hs & ~hs_q;
wire [11:0] pos       = new_line ? 12'd0 : pos_r + 12'd1;
wire        fell_cur  = new_line ? 1'b0 : line_fell;
wire        syn_start = en & have_fall & have_rise & hb & ~fell_cur & (pos == fall_pos);
wire        syn_end   = new_line | (pos == rise_pos);
wire        syn       = en & (syn_start | (syn_r & ~syn_end));

always @(posedge clk) if (ce) begin
	hs_q  <= hs;
	hb_q  <= hb;
	pos_r <= pos;
	line_fell <= fell_cur;
	if (hb_q & ~hb) begin
		fall_pos  <= pos;
		have_fall <= 1'b1;
		line_fell <= 1'b1;
	end
	if (~hb_q & hb) begin
		rise_pos  <= pos;
		have_rise <= 1'b1;
	end
	syn_r <= syn;
end

assign hb_o = hb & ~syn;
assign vb_o = vb | syn;

endmodule
