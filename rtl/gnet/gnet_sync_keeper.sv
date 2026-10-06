//============================================================================
//  G-NET core: video sync keeper (black picture with running sync)
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// The PSX_MiSTer video timing (rtl/gpu_videoout_async.vhd) stops while the
// core is in reset: every G-NET download (BIOS, flash images, the 40 MB card
// image) holds reset, and so does the reset sequencer that follows. Without
// sync a CRT or a direct_video DAC loses the picture and the HDMI scaler
// changes mode. This block watches the core's hsync; when no hsync rising
// edge has arrived for two lines it substitutes a free-running black raster
// with the core's own 320 x 240 timing (3413 clk_vid clocks per line, 263
// lines, a dot every 8 clocks), and hands back to the core on its first
// hsync edge. The outputs are a combinational multiplexer, so the core's
// video passes with no added latency while it runs.
//
// Raster of the substitute, counted from the hsync leading edge (h = 0):
//   hsync  h 0..251 (252 clocks, as the core's hsync_end count)
//   active h 648..3207: 320 dots of 8 clocks; the core's first active dot
//          in its 320-dot mode (GP1(06h) = 06C58258, all six games) comes
//          648 clocks after its hsync rising edge (sim/shell/tb_dotclock.vhd)
//   vsync  lines 0..2, edges at h = 0, so they coincide with an hsync
//          leading edge (no extra csync pulse)
//   active lines 18..257 (240 lines; the core counts the display range
//          16..256 from the end of its 3-line vsync)
// The dot enable has a fixed period of 8 clocks and its phase restarts at
// h = 0 on every line, as the core's clkCnt restarts at newLineTrigger.

module gnet_sync_keeper
(
	input             clk,         // CLK_VIDEO (53.693175 MHz)

	input             c_ce,
	input             c_hs,
	input             c_vs,
	input             c_hbl,
	input             c_vbl,
	input       [7:0] c_r,
	input       [7:0] c_g,
	input       [7:0] c_b,
	input       [2:0] c_hres,

	output            o_ce,
	output            o_hs,
	output            o_vs,
	output            o_hbl,
	output            o_vbl,
	output      [7:0] o_r,
	output      [7:0] o_g,
	output      [7:0] o_b,
	output      [2:0] o_hres,

	output            o_substitute  // 1 while the substitute raster is shown
);

localparam int H_TOTAL   = 3413;
localparam int V_TOTAL   = 263;
localparam int HS_LEN    = 252;
localparam int H_ACT0    = 648;
localparam int H_ACT1    = 3208;
localparam int V_ACT0    = 18;
localparam int V_ACT1    = 258;
localparam int VS_LINES  = 3;
localparam int DEAD_CLKS = 2 * H_TOTAL;

// core alive: an hsync rising edge within the last two lines
reg        c_hs_q = 1'b0;
reg [13:0] since_hs = 14'(DEAD_CLKS);
reg        alive = 1'b0;

always @(posedge clk) begin
	c_hs_q <= c_hs;
	if (c_hs & ~c_hs_q)
		since_hs <= 14'd0;
	else if (since_hs != 14'(DEAD_CLKS))
		since_hs <= since_hs + 14'd1;
	alive <= (since_hs != 14'(DEAD_CLKS)) | (c_hs & ~c_hs_q);
end

// substitute raster
reg [11:0] h = 12'd0;
reg  [8:0] v = 9'd0;
reg  [2:0] dot = 3'd0;
reg        f_ce = 1'b0;
reg        f_hs = 1'b0;
reg        f_vs = 1'b0;
reg        f_hact = 1'b0;
reg        f_vact = 1'b0;

always @(posedge clk) begin
	if (h == 12'(H_TOTAL - 1)) begin
		h <= 12'd0;
		v <= (v == 9'(V_TOTAL - 1)) ? 9'd0 : v + 9'd1;
	end else begin
		h <= h + 12'd1;
	end

	// registered from the counters of this clock: every output changes
	// one clock after h, all by the same amount
	dot    <= (h == 12'(H_TOTAL - 1)) ? 3'd0 : dot + 3'd1;
	f_ce   <= (dot == 3'd7);
	f_hs   <= (h == 12'(H_TOTAL - 1)) | (h < 12'(HS_LEN - 1));
	if (h == 12'(H_TOTAL - 1))
		f_vs <= (v == 9'(V_TOTAL - 1)) | (v < 9'(VS_LINES - 1));
	f_hact <= (h >= 12'(H_ACT0 - 1)) & (h < 12'(H_ACT1 - 1));
	if (h == 12'(H_TOTAL - 1))
		f_vact <= (v >= 9'(V_ACT0 - 1)) & (v < 9'(V_ACT1 - 1));
end

assign o_substitute = ~alive;
assign o_ce   = alive ? c_ce   : f_ce;
assign o_hs   = alive ? c_hs   : f_hs;
assign o_vs   = alive ? c_vs   : f_vs;
assign o_hbl  = alive ? c_hbl  : ~f_hact;
assign o_vbl  = alive ? c_vbl  : ~f_vact;
assign o_r    = alive ? c_r    : 8'd0;
assign o_g    = alive ? c_g    : 8'd0;
assign o_b    = alive ? c_b    : 8'd0;
assign o_hres = alive ? c_hres : 3'b011;   // 320 dots, as hResMode for clkDiv 8

endmodule
