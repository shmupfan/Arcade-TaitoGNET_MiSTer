// Issue #11 (Scandoubler Fx loses the picture): replay of the real video out
// (rtl/gpu_videoout_async.vhd, trace from tb_vtrace.vhd) through PSX.sv's
// GNET_SHELL video chain into rtl/gnet/gnet_arcade_video.sv, for every
// Scandoubler Fx setting and the forced scandoubler, and a measurement of
// what leaves the core on VGA_* (what sys_top hands to the HDMI scaler and
// to the analog output).
//
// Chain modelled (PSX.sv, GNET_SHELL):
//   gnet_sync_keeper: alive, passes the core's signals (o_* = c_*).
//   gnet_crt_pos: CRT H/V position 0, passes hsync and vsync straight
//     through (docs/m4_shell.md 8, bench row "0, 0: pass-through").
//   video_aspect: registered on ce_pix; hb = the core's hblank
//     (GNET_GAME_HBLANK), vb = vblank (vb_pos > 135 clear kept), RGB 0 in
//     blanking, a test pattern in the active area.
//   SD_BLANK defined: rtl/gnet/gnet_sd_blank.sv between video_aspect and
//     arcade_video, as PSX.sv has it after the fix.
//   gnet_arcade_video #(WIDTH 640, DW 24), gamma table off; with ALPHA1
//     defined the framework's sys/arcade_video.v instead (alpha 1 wiring).
//
// Per setting, after 1.2 frames of settling, over the rest of the trace:
//   VGA_HS rises, HS period min..max (clocks), VGA_VS rises, VS interval
//   min..max, HS rises per VS interval, DE lines per VS interval, CE_PIXEL
//   dots per DE line. A valid 31 kHz picture: HS about every 1706/1707
//   clocks (31.47 kHz), a VS once a frame, 2 x 240 DE lines.
// Also, with SD_BLANK, Fx None (no scandoubler) must equal the output
// without the fix on every clock: a second arcade_video fed straight from
// video_aspect runs beside it and every output is compared.
//
// Run with sim/shell/run_sd_trace.sh <mode> [fix]
`timescale 1ns/1ps
module tb_sd_trace;

reg clk = 0;
always #9.3121 clk = ~clk;   // 53.693175 MHz

string  trace;
integer last_w = 320;
integer fd;
integer frame_clocks = 263 * 3413;

// ---------------------------------------------------------------- source
reg        ce = 0, s_hs = 0, s_vs = 0, s_hb = 1, s_vb = 1;
reg        eof = 0;
integer    wait_n = 0;
integer    d, i_hs, i_vs, i_hb, i_vb, rc;
reg        have = 0;

task automatic open_trace;
	begin
		if (fd) $fclose(fd);
		fd = $fopen(trace, "r");
		if (!fd) begin $display("cannot open %s", trace); $finish; end
		eof = 0; have = 0; wait_n = 0;
	end
endtask

always @(posedge clk) begin
	ce <= 0;
	if (!eof) begin
		if (!have) begin
			rc = $fscanf(fd, "%d %d %d %d %d\n", d, i_hs, i_vs, i_hb, i_vb);
			if (rc != 5) eof <= 1;
			else begin have = 1; wait_n = (d == 0) ? 0 : d - 1; end
		end
		if (have) begin
			if (wait_n == 0) begin
				ce   <= 1;
				s_hs <= i_hs[0];
				s_vs <= i_vs[0];
				s_hb <= i_hb[0];
				s_vb <= i_vb[0];
				have = 0;
			end
			else wait_n = wait_n - 1;
		end
	end
end

// ---------------------------------------------------------------- video_aspect
reg        a_hs = 0, a_vs = 0, a_hb = 1, a_vb = 1;
reg [23:0] a_rgb = 0;
reg [11:0] h_pos = 0;
reg  [8:0] v_pos = 0, vb_pos = 0;
always @(posedge clk) if (ce) begin
	reg old_vb;
	old_vb <= s_vb;
	a_hs <= s_hs;
	a_vs <= s_vs;
	a_vb <= s_vb;
	a_rgb <= (s_vb || s_hb) ? 24'd0 : {h_pos[7:0], v_pos[7:0], 8'h80};
	h_pos <= h_pos + 1'd1;
	if (~old_vb && s_vb) vb_pos <= 0;
	if (a_hs && ~s_hs) begin
		h_pos <= 0;
		if (~s_vb) v_pos <= v_pos + 1'd1;
		else vb_pos <= vb_pos + 1'd1;
	end
	if (~a_vs && s_vs) v_pos <= 0;
	if (vb_pos > 135) a_vb <= 0;
	a_hb <= s_hb;   // GNET_GAME_HBLANK
end

// ---------------------------------------------------------------- DUT
reg  [2:0] fx = 0;
reg        forced = 0;
wire       sd_on = (|fx) | forced;

wire       v_hb, v_vb;
`ifdef SD_BLANK
gnet_sd_blank sd_blank
(
	.clk (clk),
	.ce  (ce),
	.en  (sd_on),
	.hs  (a_hs),
	.hb  (a_hb),
	.vb  (a_vb),
	.hb_o(v_hb),
	.vb_o(v_vb)
);
`else
assign v_hb = a_hb;
assign v_vb = a_vb;
`endif

wire [21:0] gb, gb_r;
assign gb[20:0] = 21'd0;
assign gb_r[20:0] = 21'd0;

wire       o_ce, o_hs, o_vs, o_de;
wire [7:0] o_r, o_g, o_b;
wire [1:0] o_sl;
`ifdef ALPHA1
// alpha 1 (gnet-full e0a36a3): the framework's sys/arcade_video.v
arcade_video #(.WIDTH(640), .DW(24)) dut
`else
gnet_arcade_video #(.WIDTH(640), .DW(24)) dut
`endif
(
	.clk_video(clk), .ce_pix(ce), .RGB_in(a_rgb),
	.HBlank(v_hb), .VBlank(v_vb), .HSync(a_hs), .VSync(a_vs),
	.CLK_VIDEO(), .CE_PIXEL(o_ce),
	.VGA_R(o_r), .VGA_G(o_g), .VGA_B(o_b), .VGA_HS(o_hs), .VGA_VS(o_vs), .VGA_DE(o_de), .VGA_SL(o_sl),
	.fx(fx), .forced_scandoubler(forced), .gamma_bus(gb)
);

// reference: the alpha 3 wiring (no gnet_sd_blank)
wire       r_ce, r_hs, r_vs, r_de;
wire [7:0] r_r, r_g, r_b;
wire [1:0] r_sl;
gnet_arcade_video #(.WIDTH(640), .DW(24)) ref_av
(
	.clk_video(clk), .ce_pix(ce), .RGB_in(a_rgb),
	.HBlank(a_hb), .VBlank(a_vb), .HSync(a_hs), .VSync(a_vs),
	.CLK_VIDEO(), .CE_PIXEL(r_ce),
	.VGA_R(r_r), .VGA_G(r_g), .VGA_B(r_b), .VGA_HS(r_hs), .VGA_VS(r_vs), .VGA_DE(r_de), .VGA_SL(r_sl),
	.fx(fx), .forced_scandoubler(forced), .gamma_bus(gb_r)
);

// ---------------------------------------------------------------- measure
integer n = 0, start_n = 0;
reg     meas = 0;
reg     hs_q = 0, vs_q = 0, de_q = 0;
integer hs_n, hs_last, hs_min, hs_max;
integer vs_n, vs_last, vs_min, vs_max;
integer hs_in_frame, hpf_min, hpf_max;
integer de_lines, dl_min, dl_max;
integer dots, dots_min, dots_max, dots_odd, dots_first;
integer diff_n, cmp_n;
reg     cmp_ref = 0;

task automatic clear;
	begin
		hs_n = 0; hs_last = -1; hs_min = 1 << 30; hs_max = 0;
		vs_n = 0; vs_last = -1; vs_min = 1 << 30; vs_max = 0;
		hs_in_frame = 0; hpf_min = 1 << 30; hpf_max = 0;
		de_lines = 0; dl_min = 1 << 30; dl_max = 0;
		dots = 0; dots_min = 1 << 30; dots_max = 0; dots_odd = 0; dots_first = 1;
		diff_n = 0; cmp_n = 0;
	end
endtask

always @(posedge clk) begin
	n = n + 1;
	if (meas) begin
		if (o_hs & ~hs_q) begin
			if (hs_last >= 0) begin
				if (n - hs_last < hs_min) hs_min = n - hs_last;
				if (n - hs_last > hs_max) hs_max = n - hs_last;
			end
			hs_last = n;
			hs_n = hs_n + 1;
			hs_in_frame = hs_in_frame + 1;
		end
		if (o_vs & ~vs_q) begin
			if (vs_last >= 0) begin
				if (n - vs_last < vs_min) vs_min = n - vs_last;
				if (n - vs_last > vs_max) vs_max = n - vs_last;
				if (hs_in_frame < hpf_min) hpf_min = hs_in_frame;
				if (hs_in_frame > hpf_max) hpf_max = hs_in_frame;
				if (de_lines < dl_min) dl_min = de_lines;
				if (de_lines > dl_max) dl_max = de_lines;
			end
			vs_last = n;
			vs_n = vs_n + 1;
			hs_in_frame = 0;
			de_lines = 0;
		end
		if (o_ce) begin
			if (o_de) dots = dots + 1;
			if (de_q & ~o_de) begin
				if (dots_first) dots_first = 0;   // partial line at the start of the measurement
				else begin
					if (dots < dots_min) dots_min = dots;
					if (dots > dots_max) dots_max = dots;
					if (dots != (fx == 3'd1 ? 2 : 1) * last_w) dots_odd = dots_odd + 1;
				end
				dots = 0;
				de_lines = de_lines + 1;
			end
			de_q = o_de;
		end
		if (cmp_ref) begin
			cmp_n = cmp_n + 1;
			if ({o_ce, o_hs, o_vs, o_de, o_r, o_g, o_b, o_sl} != {r_ce, r_hs, r_vs, r_de, r_r, r_g, r_b, r_sl})
				diff_n = diff_n + 1;
		end
	end
	hs_q = o_hs;
	vs_q = o_vs;
end

integer errors = 0;

task automatic run(input [2:0] f, input fs);
	begin
		fx = f;
		forced = fs;
		open_trace();
		clear();
		repeat (frame_clocks + frame_clocks / 5) @(posedge clk);
		meas = 1;
		cmp_ref = 1;
		while (!eof) @(posedge clk);
		meas = 0;
		cmp_ref = 0;
		$display("RESULT fx %0d forced %0d: HS rises %0d period %0d..%0d | VS rises %0d interval %0d..%0d | HS per frame %0d..%0d | DE lines per frame %0d..%0d | dots per DE line %0d..%0d (%0d lines not %0d) | differs from alpha 3 wiring on %0d of %0d clocks",
		         f, fs, hs_n, hs_min, hs_max, vs_n, vs_min, vs_max, hpf_min, hpf_max, dl_min, dl_max, dots_min, dots_max, dots_odd, (fx == 3'd1 ? 2 : 1) * last_w, diff_n, cmp_n);
`ifdef SD_BLANK
		if (!sd_on && diff_n != 0) begin errors = errors + 1; $display("FAIL: Fx None output changed by the fix"); end
		if (sd_on) begin
			if (vs_n < 2) begin errors = errors + 1; $display("FAIL: no VGA_VS with the scandoubler"); end
			if (hs_max > 1800) begin errors = errors + 1; $display("FAIL: HS gap %0d clocks with the scandoubler", hs_max); end
			if (dots_odd != 0) begin errors = errors + 1; $display("FAIL: %0d DE lines with a wrong dot count", dots_odd); end
		end
`endif
	end
endtask

initial begin
	if (!$value$plusargs("trace=%s", trace)) trace = "work/vtrace_1.txt";
	if (!$value$plusargs("width=%d", last_w)) last_w = 320;
	fd = 0;
	run(3'd0, 1'b0);
	run(3'd0, 1'b1);
	run(3'd1, 1'b0);
	run(3'd2, 1'b0);
	run(3'd3, 1'b0);
	run(3'd4, 1'b0);
`ifdef SD_BLANK
	if (errors == 0) $display("PASS");
	else $display("FAILED: %0d errors", errors);
`endif
	$finish;
end

endmodule
