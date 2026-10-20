// Unit bench for rtl/gnet/gnet_arcade_video.sv (issue #3, 480i on direct
// video) against the framework's sys/arcade_video.v, both on the same input.
//
// Source: the PSX video out after PSX.sv's video_aspect stage, 640-dot mode
// (dot enable every 4 clocks, phase restarting each line, 3413 clocks per
// line, hsync 252 clocks), with hsync, vsync, blanking and RGB registered on
// the dot enable as video_aspect does.
//   240p (GP1(08h) = 08000003h): 263 lines, vsync 3 lines from an hsync rise.
//   480i (08000027h, gpu_videoout_async.vhd): 525 lines per frame, field A's
//        vsync from an hsync rise, field B's 262 lines and 1707 clocks later
//        (mid-line), so the source vsync intervals are 895,913 and 895,912.
//
// Checks:
//   1. 240p with Fx None, HQ2x, CRT 25/50/75% and forced scandoubler: every
//      output (CE_PIXEL, VGA_R/G/B/HS/VS/DE/SL) equal to the framework's on
//      every clock (the 240p picture is unchanged).
//   2. 480i, Fx None (direct video, 15 kHz): VGA_VS rise intervals alternate,
//      each within one dot (4 clocks) of 262.5 lines (895,912.5) and two in a
//      row sum to 525 lines (1,791,825); every other output equal to the
//      framework's. The framework's own VGA_VS intervals are printed: whole
//      lines (894,206 = 262 and 897,619 = 263), the issue #3 fault.
//   3. 480i with the scandoubler (CRT 25%, forced scandoubler): every output
//      equal to the framework's (HSync-aligned VSync kept for 31 kHz).
// Run with sim/shell/run_arcade_video.sh
`timescale 1ns/1ps
module tb_arcade_video;

reg clk = 0;
always #9.3121 clk = ~clk;   // 53.693175 MHz

// ---------------------------------------------------------------- source
reg        ilace = 0;
reg [11:0] h = 0;
reg  [9:0] v = 0;
reg  [1:0] dc = 0;
reg        ce = 0, hs_s = 0, vs_s = 0, hb_s = 1, vb_s = 1;
always @(posedge clk) begin
	h  <= (h == 12'd3412) ? 12'd0 : h + 12'd1;
	if (h == 12'd3412) v <= (v >= (ilace ? 10'd524 : 10'd262)) ? 10'd0 : v + 10'd1;
	dc <= (h == 12'd3412) ? 2'd0 : dc + 2'd1;
	ce <= (dc == 2'd3);
	hs_s <= (h == 12'd3412) | (h < 12'd251);
	hb_s <= ~((h >= 12'd659) & (h < 12'd3219));
	if (ilace) begin
		if (h == 12'd3412 && v == 10'd524) vs_s <= 1'b1;
		if (h == 12'd3412 && v == 10'd2)   vs_s <= 1'b0;
		if (h == 12'd1706 && v == 10'd262) vs_s <= 1'b1;
		if (h == 12'd1706 && v == 10'd265) vs_s <= 1'b0;
		if (h == 12'd3412) vb_s <= ~(((v >= 10'd15) & (v < 10'd255)) | ((v >= 10'd277) & (v < 10'd517)));
	end else if (h == 12'd3412) begin
		vs_s <= (v == 10'd262) | (v < 10'd2);
		vb_s <= ~((v >= 10'd15) & (v < 10'd255));
	end
end

// video_aspect: registered on the dot enable
reg        a_hs = 0, a_vs = 0, a_hb = 1, a_vb = 1;
reg [23:0] a_rgb = 0;
always @(posedge clk) if (ce) begin
	a_hs  <= hs_s;
	a_vs  <= vs_s;
	a_hb  <= hb_s;
	a_vb  <= vb_s;
	a_rgb <= (hb_s | vb_s) ? 24'd0 : {h[9:2], v[7:0], h[9:2] ^ v[7:0]};
end

// ---------------------------------------------------------------- DUTs
reg  [2:0] fx = 0;
reg        forced = 0;

wire [21:0] gb_f, gb_g;
assign gb_f[20:0] = 21'd0;
assign gb_g[20:0] = 21'd0;

wire       f_ce, f_hs, f_vs, f_de;
wire [7:0] f_r, f_g, f_b;
wire [1:0] f_sl;
arcade_video #(.WIDTH(640), .DW(24)) fw
(
	.clk_video(clk), .ce_pix(ce), .RGB_in(a_rgb),
	.HBlank(a_hb), .VBlank(a_vb), .HSync(a_hs), .VSync(a_vs),
	.CLK_VIDEO(), .CE_PIXEL(f_ce),
	.VGA_R(f_r), .VGA_G(f_g), .VGA_B(f_b), .VGA_HS(f_hs), .VGA_VS(f_vs), .VGA_DE(f_de), .VGA_SL(f_sl),
	.fx(fx), .forced_scandoubler(forced), .gamma_bus(gb_f)
);

wire       g_ce, g_hs, g_vs, g_de;
wire [7:0] g_r, g_g, g_b;
wire [1:0] g_sl;
gnet_arcade_video #(.WIDTH(640), .DW(24)) dut
(
	.clk_video(clk), .ce_pix(ce), .RGB_in(a_rgb),
	.HBlank(a_hb), .VBlank(a_vb), .HSync(a_hs), .VSync(a_vs),
	.CLK_VIDEO(), .CE_PIXEL(g_ce),
	.VGA_R(g_r), .VGA_G(g_g), .VGA_B(g_b), .VGA_HS(g_hs), .VGA_VS(g_vs), .VGA_DE(g_de), .VGA_SL(g_sl),
	.fx(fx), .forced_scandoubler(forced), .gamma_bus(gb_g)
);

// ---------------------------------------------------------------- checks
integer errors = 0;
task automatic fail(input string msg);
	begin
		errors = errors + 1;
		if (errors < 20) $display("FAIL at %0t: %s", $time, msg);
	end
endtask

localparam integer HALF2 = 525 * 3413;   // two fields
integer n = 0, clocks = 0;
reg     cmp_all = 0, cmp_novs = 0, meas = 0;
reg     gvs_q = 0, fvs_q = 0;
integer g_last = -1, g_iv = 0, g_iv_q = 0, g_n = 0, g_min = 0, g_max = 0;
integer f_last = -1, f_iv = 0, f_n = 0, f_min = 0, f_max = 0;

always @(posedge clk) begin
	n = n + 1;
	if (cmp_all || cmp_novs) begin
		clocks = clocks + 1;
		if (g_ce != f_ce || g_r != f_r || g_g != f_g || g_b != f_b || g_hs != f_hs || g_de != f_de || g_sl != f_sl)
			fail("output differs from the framework's arcade_video");
		if (cmp_all && g_vs != f_vs)
			fail("VGA_VS differs from the framework's arcade_video");
	end
	if (meas) begin
		if (g_vs & ~gvs_q) begin
			if (g_last >= 0) begin
				g_iv = n - g_last;
				g_n = g_n + 1;
				if (g_iv < g_min || g_min == 0) g_min = g_iv;
				if (g_iv > g_max) g_max = g_iv;
				if (g_iv < 895912 - 4 || g_iv > 895913 + 4) fail($sformatf("480i VGA_VS interval %0d", g_iv));
				if (g_iv_q != 0) begin
					if (g_iv == g_iv_q) fail($sformatf("480i VGA_VS intervals do not alternate (%0d twice)", g_iv));
					if (g_iv + g_iv_q != HALF2) fail($sformatf("480i VGA_VS two fields %0d, expected %0d", g_iv + g_iv_q, HALF2));
				end
				g_iv_q = g_iv;
			end
			g_last = n;
		end
		if (f_vs & ~fvs_q) begin
			if (f_last >= 0) begin
				f_iv = n - f_last;
				f_n = f_n + 1;
				if (f_iv < f_min || f_min == 0) f_min = f_iv;
				if (f_iv > f_max) f_max = f_iv;
			end
			f_last = n;
		end
	end
	gvs_q = g_vs;
	fvs_q = f_vs;
end

localparam integer FRAME = 263 * 3413;

task automatic same(input [2:0] f, input fs, input integer frames);
	begin
		fx = f;
		forced = fs;
		repeat (2 * FRAME) @(posedge clk);
		clocks = 0;
		cmp_all = 1;
		repeat (frames * FRAME) @(posedge clk);
		cmp_all = 0;
		$display("%s fx %0d forced %0d: %0d clocks equal to the framework's, errors %0d",
		         ilace ? "480i" : "240p", f, fs, clocks, errors);
	end
endtask

initial begin
	// 1. 240p
	ilace = 0;
	same(3'd0, 1'b0, 2);
	same(3'd1, 1'b0, 2);
	same(3'd2, 1'b0, 2);
	same(3'd3, 1'b0, 2);
	same(3'd4, 1'b0, 2);
	same(3'd0, 1'b1, 2);
	same(3'd0, 1'b0, 2);

	// 2. 480i, Fx None
	ilace = 1;
	fx = 0;
	forced = 0;
	repeat (3 * FRAME) @(posedge clk);
	clocks = 0;
	g_last = -1; g_iv_q = 0; g_n = 0; g_min = 0; g_max = 0;
	f_last = -1; f_n = 0; f_min = 0; f_max = 0;
	cmp_novs = 1;
	meas = 1;
	repeat (6 * FRAME) @(posedge clk);
	meas = 0;
	cmp_novs = 0;
	if (g_n < 3) fail($sformatf("480i: only %0d VGA_VS intervals", g_n));
	$display("480i fx 0: gnet_arcade_video VGA_VS intervals %0d..%0d (%0d), framework %0d..%0d (%0d); other outputs equal over %0d clocks, errors %0d",
	         g_min, g_max, g_n, f_min, f_max, f_n, clocks, errors);

	// 3. 480i through the scandoubler
	same(3'd2, 1'b0, 4);
	same(3'd0, 1'b1, 4);

	// back to 240p
	ilace = 0;
	same(3'd0, 1'b0, 2);

	if (errors == 0) $display("PASS");
	else $display("FAILED: %0d errors", errors);
	$finish;
end

endmodule
