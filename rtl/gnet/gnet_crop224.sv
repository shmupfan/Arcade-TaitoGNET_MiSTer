//============================================================================
//
//  G-NET core: optional 224-line crop of the 240-line picture
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
// Evidence: MAME 0.288 frames (sim/oracle in gnet-mister): Shikigami no
//           Shiro fills lines 0 to 7 and 232 to 239 of its 240 with one
//           flat colour in 343 of 355 sampled frames (both sets), Chaos
//           Heat with black in 67 of 76; no other traced game does it
//           (docs/crop224.md). The PSX video out (rtl/gpu_videoout_async.vhd,
//           sim/shell/run_vtrace.sh mode 1) changes vblank only while
//           hblank is high and draws 240 lines of 320 dots.
//           Bench: sim/shell/run_crop224.sh.
//
// OSD "Crop 224 lines" (status[122], On by default), shown only for sets
// whose MRA sets configuration bit 5 (PSX.sv: en = bit 5 and the item On;
// every other set never crops). With en high, the
// first and last 8 drawn lines of each 240p frame become vertical blanking:
// PSX.sv's video_aspect holds vblank high and the RGB black there, so every
// output after it (arcade_video and the scandoubler, the rotation feed, the
// HDMI scaler through VGA_DE) sees a 224-line picture and the HDMI aspect
// (4:3, 3:4 rotated) applies to those 224 lines. Sync timing is unchanged,
// so on a CRT the 16 lines show black.
//
// A drawn line starts at an hblank falling edge with vblank low; the line
// index counts those edges from 0 after each vblank. During hblank the
// index is already the next line's, so blank changes on the first hblank
// dot after a drawn line and is steady for the whole hblank before the next
// line starts (the source moves vblank inside hblank too: 30 of 106 dots
// in at 320 dots, run_vtrace.sh mode 1; the framework's scandoubler samples
// vblank at the hblank falling edge). The output is combinational from the
// inputs and state updated on ce (the inputs change only on ce), so no
// delay is added. Interlaced modes (480i) are never cropped.

module gnet_crop224
(
	input  clk,
	input  ce,
	input  en,
	input  interlace,
	input  hb,
	input  vb,
	output blank
);

reg [8:0] line_no = 9'd0;
reg       first   = 1'b1;
reg       old_hb  = 1'b1;

wire       hb_fall   = old_hb & ~hb & ~vb;
wire [8:0] line_next = first ? 9'd0 : line_no + 9'd1;
wire [8:0] line_cur  = (hb | old_hb) ? line_next : line_no;

assign blank = en & ~interlace & ~vb & ((line_cur < 9'd8) | (line_cur >= 9'd232));

always @(posedge clk) if (ce) begin
	old_hb <= hb;
	if (vb) first <= 1'b1;
	if (hb_fall) begin
		line_no <= line_next;
		first   <= 1'b0;
	end
end

endmodule
