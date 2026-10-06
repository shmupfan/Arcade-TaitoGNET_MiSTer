// Unit bench for the G-NET shell blocks (docs/m4_shell.md 6):
//   gnet_sync_keeper: substitute raster while the core is silent (line,
//     hsync, dot period, active area, vsync on hsync, black), hand-over to a
//     running core, take-over two lines after the core stops;
//   gnet_volume: the four OSD settings, saturation at +6 dB.
// Run with sim/shell/run_shell.sh
`timescale 1ns/1ps
module tb_shell;

reg clk = 0;
always #9.3121 clk = ~clk;   // 53.693175 MHz

// ---------------------------------------------------------------- core model
// A raster like the PSX video out's 320-dot mode, at another phase than the
// keeper's: 3413 clocks per line, hsync 252 clocks, dot every 8 clocks with
// the phase restarting each line, non-zero colour.
reg        core_run = 0;
reg [11:0] ch = 12'd1234;
reg  [8:0] cv = 9'd100;
reg  [2:0] cd = 0;
reg        c_ce = 0, c_hs = 0, c_vs = 0, c_hbl = 1, c_vbl = 1;
always @(posedge clk) begin
	if (core_run) begin
		ch <= (ch == 12'd3412) ? 12'd0 : ch + 12'd1;
		if (ch == 12'd3412) cv <= (cv == 9'd262) ? 9'd0 : cv + 9'd1;
		cd <= (ch == 12'd3412) ? 3'd0 : cd + 3'd1;
		c_ce  <= (cd == 3'd7);
		c_hs  <= (ch == 12'd3412) | (ch < 12'd251);
		c_hbl <= ~((ch >= 12'd647) & (ch < 12'd3207));
		if (ch == 12'd3412) begin
			c_vs  <= (cv == 9'd262) | (cv < 9'd2);
			c_vbl <= ~((cv >= 9'd17) & (cv < 9'd257));
		end
	end else begin
		c_ce <= 0;     // the core in reset: no dot enable, sync stops
	end
end

wire       o_ce, o_hs, o_vs, o_hbl, o_vbl, o_sub;
wire [7:0] o_r, o_g, o_b;
wire [2:0] o_hres;

gnet_sync_keeper dut
(
	.clk(clk),
	.c_ce(c_ce), .c_hs(c_hs), .c_vs(c_vs), .c_hbl(c_hbl), .c_vbl(c_vbl),
	.c_r(8'h55), .c_g(8'hAA), .c_b(8'h33), .c_hres(3'b001),
	.o_ce(o_ce), .o_hs(o_hs), .o_vs(o_vs), .o_hbl(o_hbl), .o_vbl(o_vbl),
	.o_r(o_r), .o_g(o_g), .o_b(o_b), .o_hres(o_hres), .o_substitute(o_sub)
);

integer errors = 0;
task automatic fail(input string msg);
	begin
		errors = errors + 1;
		if (errors < 20) $display("FAIL at %0t: %s", $time, msg);
	end
endtask

// ----------------------------------------------------- substitute raster check
integer n = 0, last_hs = -1, last_ce = -1, hs_len = 0, dots = 0, act_lines = 0, lines = 0;
integer frames = 0, first_dot = -1, ph = -1;
reg     hs_q = 0, vs_q = 0, hs_rise;
reg     check_sub = 0;
always @(posedge clk) begin
	n = n + 1;
	hs_rise = o_hs & ~hs_q;
	if (check_sub) begin
		if (!o_sub) fail("substitute expected");
		if (o_r != 0 || o_g != 0 || o_b != 0) fail("substitute not black");
		if (o_hres != 3'b011) fail("substitute hres");
		if (o_ce) begin
			if (!o_hbl && last_ce >= 0 && (n - last_ce) != 8) fail($sformatf("dot period %0d", n - last_ce));
			if (!o_hbl && !o_vbl) begin
				if (dots == 0 && last_hs >= 0) begin
					first_dot = n - last_hs;
					if (ph < 0) ph = first_dot; else if (ph != first_dot) fail("first dot phase");
				end
				dots = dots + 1;
			end
			last_ce = n;
		end
		if (o_hs) hs_len = hs_len + 1;
		if (hs_rise) begin
			if (last_hs >= 0 && (n - last_hs) != 3413) fail($sformatf("line %0d", n - last_hs));
			if (dots != 0) begin
				if (dots != 320) fail($sformatf("dots %0d", dots));
				act_lines = act_lines + 1;
			end
			dots = 0;
			last_hs = n;
			lines = lines + 1;
		end
		if (!o_hs && hs_q && last_hs >= 0 && hs_len != 252) fail($sformatf("hsync %0d", hs_len));
		if (!o_hs) hs_len = 0;
		if (o_vs != vs_q) begin
			if (!hs_rise) fail("vsync edge off hsync rise");
			if (o_vs) begin
				if (frames > 0) begin
					if (lines != 263) fail($sformatf("lines %0d", lines));
					if (act_lines != 240) fail($sformatf("active lines %0d", act_lines));
				end
				frames = frames + 1;
				lines = 0;
				act_lines = 0;
			end
		end
	end
	hs_q = o_hs;
	vs_q = o_vs;
end

// ------------------------------------------------------ pass-through check
reg check_pass = 0;
always @(posedge clk) begin
	#1;
	if (check_pass) begin
		if (o_sub) fail("core expected");
		if (o_ce != c_ce || o_hs != c_hs || o_vs != c_vs || o_hbl != c_hbl || o_vbl != c_vbl
		    || o_r != 8'h55 || o_g != 8'hAA || o_b != 8'h33 || o_hres != 3'b001)
			fail("pass-through differs from core");
	end
end

// ----------------------------------------------------------------- volume
reg  [1:0]  vol = 0;
reg  signed [15:0] in_l = 0, in_r = 0;
wire signed [15:0] out_l, out_r;
gnet_volume vdut (.clk(clk), .vol(vol), .in_l(in_l), .in_r(in_r), .out_l(out_l), .out_r(out_r));

task automatic vcheck(input [1:0] v, input signed [15:0] a, input signed [15:0] b,
                      input signed [15:0] ea, input signed [15:0] eb);
	begin
		vol = v; in_l = a; in_r = b;
		@(posedge clk); @(posedge clk); #1;
		if (out_l != ea || out_r != eb)
			fail($sformatf("volume %0d: %0d,%0d -> %0d,%0d (expected %0d,%0d)", v, a, b, out_l, out_r, ea, eb));
	end
endtask

// ------------------------------------------------------------------ sequence
integer t0;
initial begin
	// volume
	vcheck(0, 16'sd1000, -16'sd1000, 16'sd1000, -16'sd1000);
	vcheck(1, 16'sd1000, -16'sd1000, 16'sd2000, -16'sd2000);
	vcheck(1, 16'sd20000, -16'sd20000, 16'sd32767, -16'sd32768);
	vcheck(1, 16'sd16383, -16'sd16384, 16'sd32766, -16'sd32768);
	vcheck(1, 16'sd16384, -16'sd16385, 16'sd32767, -16'sd32768);
	vcheck(2, 16'sd1001, -16'sd1001, 16'sd500, -16'sd501);
	vcheck(3, 16'sd32767, -16'sd32768, 16'sd8191, -16'sd8192);
	vcheck(0, 16'sd32767, -16'sd32768, 16'sd32767, -16'sd32768);
	$display("volume: done, errors so far %0d", errors);

	// 1. core silent from power-up: substitute raster, 4 frames
	repeat (2 * 3413 + 8) @(posedge clk);
	check_sub = 1;
	repeat (4 * 263 * 3413 + 100) @(posedge clk);
	check_sub = 0;
	$display("substitute: %0d frames checked, first dot %0d clocks after hsync, errors %0d", frames, ph, errors);

	// 2. core starts: hand-over on its first hsync rising edge
	core_run = 1;
	t0 = n;
	wait (o_sub == 0);
	$display("hand-over %0d clocks after the core started (its first hsync rise at ch 3412 -> %0d clocks)", n - t0, 3413 - 1234);
	@(posedge clk);
	check_pass = 1;
	repeat (2 * 263 * 3413) @(posedge clk);
	check_pass = 0;
	$display("pass-through: 2 frames checked, errors %0d", errors);

	// 3. core stops (reset): take-over after two lines without an hsync rise
	@(posedge clk iff (c_hs == 0 && ch == 12'd1000));
	core_run = 0;
	t0 = n;
	wait (o_sub == 1);
	$display("take-over %0d clocks after the core stopped", n - t0);
	last_hs = -1; last_ce = -1; dots = 0; frames = 0; lines = 0; act_lines = 0; ph = -1; hs_len = 0;
	repeat (3413) @(posedge clk);
	check_sub = 1;
	repeat (2 * 263 * 3413) @(posedge clk);
	check_sub = 0;
	$display("substitute again: %0d frames, first dot %0d, errors %0d", frames, ph, errors);

	if (errors == 0) $display("PASS");
	else $display("FAILED: %0d errors", errors);
	$finish;
end

endmodule
