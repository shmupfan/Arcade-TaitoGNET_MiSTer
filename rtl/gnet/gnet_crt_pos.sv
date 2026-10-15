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
// vsync. As in my other cores: crt_h moves the picture right by 2 dots a
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
//   * 480i (issue #3): every second field's source vsync starts and ends in
//     the middle of a line (rtl/gpu_videoout_async.vhd, "half line later",
//     1707 clocks after the hsync rise), which is what makes a CRT
//     interleave the fields. When a source vsync rise does not come with an
//     hsync rise, the new vsync edges of that field keep the same number of
//     clocks after their new hsync rise, and the fields' line counts (which
//     alternate) are taken from two fields back. The 240p logic is the
//     branch with ilace = 0, unchanged; it is only left while one of the
//     last two source vsyncs rose mid-line.
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

// source vsync phase (480i): clocks from the source hsync rise to the vsync
// rise, 0 when both rise on the same clock (all 240p modes); 1 the last
// source vsync, 2 the one before
reg [11:0] ph1 = 12'd0, ph2 = 12'd0;
reg        mid1 = 1'b0, mid2 = 1'b0;

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
		// phase of this vsync in its line, clocks after the hsync rise
		ph2  <= ph1;
		mid2 <= mid1;
		mid1 <= ~hs_rise;
		ph1  <= hs_rise ? 12'd0 : hc + 12'd1;
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

// 480i: a mid-line source vsync and its fields of alternating length.
// Line i of the new vsync of a field, counted as li from the first new
// hsync after that field's source vsync rose: the new hsync that belongs to
// the source vsync's line comes before the rise when the hsync is moved
// earlier (dh > 0) or the vsync rose mid-line (|dh| <= 160 clocks, half a
// line is 1707), so one less (b); crt_v lines earlier. d1 places the new
// vsync of the last source vsync, d2 the one of the next source vsync,
// predicted from the field two back (frame2 lines, phase ph2, mid2), which
// is the same kind of field as the next one. Each edge then waits its
// field's phase after the new hsync rise.
reg  [8:0] frame2 = 9'd263;     // frame length before the last one
wire       ilace = mid1 | mid2;
wire signed [10:0] li_x = {2'b00, li_next};
wire signed [10:0] sv_x = {{7{sv[3]}}, sv};
wire signed [10:0] fr_x = {2'b00, frame2};
wire signed [10:0] vl_x = {2'b00, vs_lines};
wire signed [10:0] d1 = li_x + sv_x + ((dh > 0 || mid1) ? 11'sd1 : 11'sd0);
wire signed [10:0] d2 = li_x + sv_x - fr_x + ((dh > 0 || mid2) ? 11'sd1 : 11'sd0);
wire       on1 = (d1 >= 11'sd0) && (d1 < vl_x);
wire       on2 = (d2 >= 11'sd0) && (d2 < vl_x);
wire       want_i = on1 | on2;
reg        nvs_l = 1'b0;        // new vsync as decided at the last new hsync
reg        nvs_pv = 1'b0;       // level waiting for the phase delay
reg [11:0] nvs_ph = 12'd0;      // phase of the new vsync pulse running
reg [11:0] dcnt = 12'd0;        // phase delay count
wire [11:0] tph = on2 ? ph2 : ph1;
wire [11:0] dly = want_i ? tph : nvs_ph;

always @(posedge clk) begin
	if (dcnt != 12'd0) begin
		dcnt <= dcnt - 12'd1;
		if (dcnt == 12'd1) nvs <= nvs_pv;
	end
	if (vs_rise) pend <= 1'b1;
	if (nhs_start) begin
		if (pend) begin
			frame  <= li + 9'd1;
			frame2 <= frame;
			pend   <= 1'b0;
		end
		li  <= li_next;
		if (!ilace) begin
			// 240p (as before)
			nvs   <= (d < vs_lines);
			nvs_l <= (d < vs_lines);
			dcnt  <= 12'd0;
		end else if (want_i != nvs_l) begin
			nvs_l <= want_i;
			if (want_i) nvs_ph <= tph;
			if (dly == 12'd0) begin
				nvs <= want_i;
			end else begin
				nvs_pv <= want_i;
				dcnt   <= dly;
			end
		end
	end
end

assign hs_o = bypass ? hs : nhs;
assign vs_o = bypass ? vs : nvs;

endmodule
