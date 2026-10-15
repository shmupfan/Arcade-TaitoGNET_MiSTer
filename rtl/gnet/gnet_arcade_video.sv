//============================================================================
//
//  G-NET core: arcade_video with the 480i field offset kept
//  Copyright (C) 2017-2020 Sorgelig (sys/arcade_video.v)
//  Changes for the G-NET core: Copyright (C) 2026 Lee Foot
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
// A copy of the framework's arcade_video module (sys/arcade_video.v, which
// stays as upstream) with one change, issue #3 (480i on direct video):
//
// The framework takes VSync only on an HSync rising edge. In 480i the PSX
// video out (rtl/gpu_videoout_async.vhd, "half line later") starts every
// second field's vsync in the middle of a line, 1707 clocks after the hsync
// rise, so the fields are 262.5 lines apart and a CRT interleaves them. The
// framework's latch moves that edge to the next line start, the fields land
// 262 and 263 lines apart and the CRT shows them on top of each other.
//
// Here VSync is taken on every dot enable when the scandoubler is off (Fx
// None and no forced scandoubler: direct video and the 15 kHz analog
// output), so the half line reaches VGA_VS to within one dot. With the
// scandoubler on (31 kHz, HQ2x, scanlines) the HSync-aligned latch is kept
// as the framework has it, since the scandoubler builds its lines from the
// sync it is given.
//
// 240p is unchanged: there the source's vsync edges come on the same clock
// as its hsync rising edges (docs/m4_shell.md 2, "vsync edge not on hsync
// rise: 0"), so VSync is already equal to vs_fix whenever the framework's
// latch would update it. HBlank, VBlank, the RGB path, the scandoubler and
// the gamma table (video_mixer) are as the framework's.
//
// DW:
//  6 : 2R 2G 2B
//  8 : 3R 3G 2B
//  9 : 3R 3G 3B
// 12 : 4R 4G 4B
// 24 : 8R 8G 8B

module gnet_arcade_video #(parameter WIDTH=320, DW=8, GAMMA=1)
(
	input         clk_video,
	input         ce_pix,

	input[DW-1:0] RGB_in,
	input         HBlank,
	input         VBlank,
	input         HSync,
	input         VSync,

	output        CLK_VIDEO,
	output        CE_PIXEL,
	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,
	output  [1:0] VGA_SL,

	input   [2:0] fx,
	input         forced_scandoubler,
	inout  [21:0] gamma_bus
);

assign CLK_VIDEO = clk_video;

wire hs_fix,vs_fix;
sync_fix sync_v(CLK_VIDEO, HSync, hs_fix);
sync_fix sync_h(CLK_VIDEO, VSync, vs_fix);

reg [DW-1:0] RGB_fix;

wire scandoubler = fx || forced_scandoubler;

reg CE,HS,VS,HBL,VBL;
always @(posedge CLK_VIDEO) begin
	reg old_ce;
	old_ce <= ce_pix;
	CE <= 0;
	if(~old_ce & ce_pix) begin
		CE <= 1;
		HS <= hs_fix;
		// G-NET: the framework's HSync-aligned latch only for the scandoubler
		if(scandoubler) begin
			if(~HS & hs_fix) VS <= vs_fix;
		end
		else VS <= vs_fix;

		RGB_fix <= RGB_in;
		HBL <= HBlank;
		if(HBL & ~HBlank) VBL <= VBlank;
	end
end

wire [7:0] R,G,B;

generate
	if(DW == 6) begin
		assign R = {RGB_fix[5:4],RGB_fix[5:4],RGB_fix[5:4],RGB_fix[5:4]};
		assign G = {RGB_fix[3:2],RGB_fix[3:2],RGB_fix[3:2],RGB_fix[3:2]};
		assign B = {RGB_fix[1:0],RGB_fix[1:0],RGB_fix[1:0],RGB_fix[1:0]};
	end
	else if(DW == 8) begin
		assign R = {RGB_fix[7:5],RGB_fix[7:5],RGB_fix[7:6]};
		assign G = {RGB_fix[4:2],RGB_fix[4:2],RGB_fix[4:3]};
		assign B = {RGB_fix[1:0],RGB_fix[1:0],RGB_fix[1:0],RGB_fix[1:0]};
	end
	else if(DW == 9) begin
		assign R = {RGB_fix[8:6],RGB_fix[8:6],RGB_fix[8:7]};
		assign G = {RGB_fix[5:3],RGB_fix[5:3],RGB_fix[5:4]};
		assign B = {RGB_fix[2:0],RGB_fix[2:0],RGB_fix[2:1]};
	end
	else if(DW == 12) begin
		assign R = {RGB_fix[11:8],RGB_fix[11:8]};
		assign G = {RGB_fix[7:4],RGB_fix[7:4]};
		assign B = {RGB_fix[3:0],RGB_fix[3:0]};
	end
	else if(DW == 18) begin
		assign R = {RGB_fix[17:12],RGB_fix[17:16]};
		assign G = {RGB_fix[11: 6],RGB_fix[11:10]};
		assign B = {RGB_fix[ 5: 0],RGB_fix[ 5: 4]};
	end
	else begin // 24
		assign R = RGB_fix[23:16];
		assign G = RGB_fix[15:8];
		assign B = RGB_fix[7:0];
	end
endgenerate

assign VGA_SL  = sl[1:0];
wire [2:0] sl = fx ? fx - 1'd1 : 3'd0;

video_mixer #(.LINE_LENGTH(WIDTH+4), .HALF_DEPTH(DW!=24), .GAMMA(GAMMA)) video_mixer
(
	.CLK_VIDEO(CLK_VIDEO),
	.ce_pix(CE),
	.CE_PIXEL(CE_PIXEL),

	.scandoubler(scandoubler),
	.hq2x(fx==1),
	.gamma_bus(gamma_bus),

	.R((DW!=24) ? R[7:4] : R),
	.G((DW!=24) ? G[7:4] : G),
	.B((DW!=24) ? B[7:4] : B),

	.HSync (HS),
	.VSync (VS),
	.HBlank(HBL),
	.VBlank(VBL),

	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

endmodule
