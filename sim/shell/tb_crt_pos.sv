// Unit bench for rtl/gnet/gnet_crt_pos.sv (docs/m4_shell.md 4).
// Source raster as the PSX video out in its 320-dot mode (3413 clocks per
// line, hsync 252 clocks, 263 lines, vsync 3 lines starting on an hsync
// rising edge). For each CRT H/V setting, after the setting is taken and one
// frame has passed, two frames are checked:
//   * new hsync: period 3413, width 252, rise at source rise - 2*h*8 + c
//     (c the same for every setting)
//   * new vsync: both edges on a new hsync rise, 3 lines long, rise at the
//     source vsync rise - v lines - 2*h*8 + c
//   * h = v = 0: outputs equal the source
// Run with sim/shell/run_crt_pos.sh
`timescale 1ns/1ps
module tb_crt_pos;

reg clk = 0;
always #9.3121 clk = ~clk;

reg [11:0] sh = 0;
reg  [8:0] sv = 0;
reg hs = 0, vs = 0;
always @(posedge clk) begin
	sh <= (sh == 12'd3412) ? 12'd0 : sh + 12'd1;
	if (sh == 12'd3412) sv <= (sv == 9'd262) ? 9'd0 : sv + 9'd1;
	hs <= (sh == 12'd3412) | (sh < 12'd251);
	if (sh == 12'd3412) vs <= (sv == 9'd262) | (sv < 9'd2);
end

reg  [3:0] crt_h = 0;
reg  [2:0] crt_v = 0;
wire hs_o, vs_o;
gnet_crt_pos dut (.clk(clk), .hs(hs), .vs(vs), .hres(3'b011), .crt_h(crt_h), .crt_v(crt_v), .hs_o(hs_o), .vs_o(vs_o));

integer errors = 0;
integer n = 0;
integer t_src_hs = -1, t_src_vs = -1;
integer t_hs = -1, hs_w = 0, vs_lines = 0;
integer hs_off = 0, vs_off = 0, nh = 0, nv = 0;
reg hq = 0, vq = 0, hoq = 0, voq = 0;
reg check = 0;
integer exp_h, exp_v, c0 = -99999;
reg     seen_vs = 0;

always @(posedge clk) begin
	n = n + 1;
	if (hs & ~hq) t_src_hs = n;
	if (vs & ~vq) t_src_vs = n;
	if (check) begin
		if (hs_o & ~hoq) begin
			if (t_hs >= 0 && n - t_hs != 3413) begin errors++; $display("FAIL hsync period %0d", n - t_hs); end
			t_hs = n;
			nh++;
			// offset to the nearest source rise
			hs_off = n - t_src_hs;
			if (hs_off > 3413 / 2) hs_off -= 3413;
			if (hs_off != exp_h) begin errors++; if (errors < 10) $display("FAIL hsync offset %0d, expected %0d", hs_off, exp_h); end
		end
		if (hs_o) hs_w++;
		if (~hs_o & hoq) begin
			if (hs_w != 252) begin errors++; $display("FAIL hsync width %0d", hs_w); end
			hs_w = 0;
		end
		if (vs_o != voq) begin
			if (!(hs_o & ~hoq)) begin errors++; $display("FAIL vsync edge off the new hsync rise"); end
			if (vs_o) begin
				nv++;
				vs_lines = 0;
				seen_vs = 1;
				vs_off = n - t_src_vs;
				if (vs_off > 3413 * 263 / 2) vs_off -= 3413 * 263;
				if (vs_off != exp_v) begin errors++; $display("FAIL vsync offset %0d, expected %0d", vs_off, exp_v); end
			end else if (seen_vs && vs_lines != 3) begin
				errors++; $display("FAIL vsync %0d lines", vs_lines);
			end
		end
		if (vs_o & hs_o & ~hoq) vs_lines++;
	end else begin
		hs_w = hs_o ? hs_w + 1 : 0;
	end
	hq = hs; vq = vs; hoq = hs_o; voq = vs_o;
end

function automatic integer hs_off_now();
	integer o;
	begin
		o = n - 1 - t_src_hs;
		if (o > 3413 / 2) o -= 3413;
		hs_off_now = o;
	end
endfunction

task automatic run(input integer h, input integer v);
	integer c;
	begin
		crt_h = h[3:0];
		crt_v = v[2:0];
		repeat (3 * 263 * 3413) @(posedge clk);
		c = (c0 == -99999) ? 0 : c0;
		exp_h = -2 * h * 8 + c;
		exp_v = -v * 3413 - 2 * h * 8 + c;
		if (h == 0 && v == 0) begin exp_h = 0; exp_v = 0; end
		t_hs = -1; nh = 0; nv = 0; seen_vs = 0;
		check = 1;
		repeat (2 * 263 * 3413) @(posedge clk);
		check = 0;
		$display("h %0d v %0d: %0d hsyncs, offset %0d; %0d vsyncs, offset %0d clocks; errors %0d", h, v, nh, hs_off, nv, vs_off, errors);
	end
endtask

initial begin
	// bypass
	run(0, 0);
	// latency c of the moved sync: the line counter is 0 one clock after the
	// source edge and the new hsync is a register, so c = 2 clocks for every
	// setting other than 0/0 (which passes the source through)
	c0 = 2;
	run(-1, 0);
	run(1, 0);
	run(7, 0);
	run(-8, 0);
	run(0, 1);
	run(0, 3);
	run(0, -4);
	run(5, -2);
	run(-6, 2);
	run(0, 0);
	if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
	$finish;
end

endmodule
