//============================================================================
//  G-NET core: OSD CRT H/V position (moves the sync pulses only)
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// Minimum standard: CRT H/V position moves the sync pulses, never the
// picture, the totals or the game's timing, and the new setting is taken at
// vsync. As in Lee's other cores: crt_h moves the picture right by 2 dots a
// step (-16..+14), crt_v moves it down by 1 line a step (-4..+3).
//
// The video source's own raster is not touched. This block regenerates
// hsync and vsync from it on CLK_VIDEO:
//   * a new hsync starts K clocks after each source hsync rising edge, with
//     the source's pulse width; K = line - 2 * crt_h * dot (picture right =
//     sync earlier, taken modulo the measured line length), dot = clocks per
//     dot of the current mode (hres: 10/8/7/5/4 for 256/320/368/512/640)
//   * a new vsync starts and ends on new hsync rising edges (so csync gets
//     no extra pulse), crt_v lines earlier than the source's (modulo the
//     measured frame length in lines), with the source's length in lines
// With both settings 0 the source's hsync and vsync pass straight through.

module gnet_crt_pos
(
	input             clk,
	input             hs,
	input             vs,
	input       [2:0] hres,     // PSX hResMode
	input       [3:0] crt_h,    // two's complement, 2 dots a step
	input       [2:0] crt_v,    // two's complement, 1 line a step
	output            hs_o,
	output            vs_o
);

// clocks per dot of the current mode
reg [3:0] dot;
always @(*) begin
	case (hres)
		3'b100:  dot = 4'd10;
		3'b011:  dot = 4'd8;
		3'b010:  dot = 4'd7;
		3'b001:  dot = 4'd5;
		default: dot = 4'd4;
	endcase
end

reg        hs_q = 1'b0, vs_q = 1'b0;
wire       hs_rise = hs & ~hs_q;
wire       vs_rise = vs & ~vs_q;

reg [11:0] hc = 12'd0;          // clocks since the source hsync rose
reg [11:0] line_len = 12'd3413; // measured source line
reg [11:0] hs_len = 12'd252;    // measured source hsync width
reg  [8:0] vs_lines = 9'd3;     // source vsync length in lines
reg  [8:0] vs_cnt = 9'd0;

// settings, taken at the source vsync
reg signed [4:0] sh = 5'sd0;    // crt_h
reg signed [3:0] sv = 4'sd0;    // crt_v
reg        bypass = 1'b1;

// shift in clocks: 2 * crt_h * dot, |value| <= 16 * 10
wire signed [9:0] dh = sh * $signed({1'b0, dot}) * 10'sd2;
reg  [11:0] k = 12'd0;

always @(posedge clk) begin
	hs_q <= hs;
	vs_q <= vs;

	if (hs_rise) begin
		line_len <= hc + 12'd1;
		hc <= 12'd0;
	end else if (hc != 12'hFFF) begin
		hc <= hc + 12'd1;
	end
	if (hs_q & ~hs) hs_len <= hc + 12'd1;

	// source vsync length in lines (its edges come with hsync rises)
	if (hs_rise) begin
		if (vs) vs_cnt <= vs_cnt + 9'd1;
		else if (vs_cnt != 0) begin
			vs_lines <= vs_cnt;
			vs_cnt   <= 9'd0;
		end
	end

	if (vs_rise) begin
		sh     <= $signed({crt_h[3], crt_h});
		sv     <= $signed({crt_v[2], crt_v});
		bypass <= (crt_h == 4'd0) && (crt_v == 3'd0);
	end

	// K: delay of the new hsync after the source's
	if (dh > 0)      k <= line_len - 12'(dh);
	else if (dh < 0) k <= 12'(-dh);
	else             k <= 12'd0;
end

// new hsync
reg        nhs = 1'b0;
reg [11:0] nhs_cnt = 12'd0;
wire       nhs_start = (hc == k);   // k = 0: one clock after the source edge
always @(posedge clk) begin
	if (nhs_start) begin
		nhs     <= 1'b1;
		nhs_cnt <= hs_len - 12'd1;
	end else if (nhs_cnt != 0) begin
		nhs_cnt <= nhs_cnt - 12'd1;
	end else begin
		nhs <= 1'b0;
	end
end

// new vsync: line index i of each new hsync since the source vsync rose
reg        pend = 1'b0;
reg  [8:0] li = 9'd0;
reg  [8:0] frame = 9'd263;
reg        nvs = 1'b0;
// line of the new vsync, counted from the first new hsync after the source
// vsync rose; with the hsync moved earlier (dh > 0) the new hsync that
// belongs to the source vsync's line comes before that rise, so one less
wire [8:0] vs_base = (sv > 0) ? frame - 9'($unsigned(sv)) : 9'($unsigned(-sv));
wire [8:0] vs_at = (dh <= 0) ? vs_base : (vs_base == 9'd0) ? frame - 9'd1 : vs_base - 9'd1;
wire [8:0] li_next = pend ? 9'd0 : li + 9'd1;
wire [8:0] d = (li_next >= vs_at) ? li_next - vs_at : li_next + frame - vs_at;
always @(posedge clk) begin
	if (vs_rise) pend <= 1'b1;
	if (nhs_start) begin
		if (pend) begin
			frame <= li + 9'd1;
			pend  <= 1'b0;
		end
		li  <= li_next;
		nvs <= (d < vs_lines);
	end
end

assign hs_o = bypass ? hs : nhs;
assign vs_o = bypass ? vs : nvs;

endmodule
