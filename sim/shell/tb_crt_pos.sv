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
// Then the same with a 480i source (issue #3), as gpu_videoout_async.vhd in
// GP1(08h) = 08000027h or 08000026h: 525 lines per frame, field A's vsync
// on an hsync rise, field B's 262 lines and 1707 clocks later (rise and fall
// mid-line), so the source vsync intervals are 895,913 and 895,912 clocks.
// Checked, four fields per setting:
//   * new hsync as above
//   * new vsync of field A: both edges on a new hsync rise; field B: both
//     edges 1707 clocks after the last new hsync rise; 3 lines long
//   * rise at the source vsync rise of the same field - v lines - 2*h*8 + c
//   * vsync rise intervals alternate 895,912 / 895,913 (sum 2 x 262.5 lines)
// The 240p runs are repeated at the end, after the 480i ones.
// Run with sim/shell/run_crt_pos.sh
`timescale 1ns/1ps
module tb_crt_pos;

reg clk = 0;
always #9.3121 clk = ~clk;

reg [11:0] sh = 0;
reg  [8:0] sv = 0;
reg hs = 0, vs_p = 0;
always @(posedge clk) begin
	sh <= (sh == 12'd3412) ? 12'd0 : sh + 12'd1;
	if (sh == 12'd3412) sv <= (sv == 9'd262) ? 9'd0 : sv + 9'd1;
	hs <= (sh == 12'd3412) | (sh < 12'd251);
	if (sh == 12'd3412) vs_p <= (sv == 9'd262) | (sv < 9'd2);
end

// 480i source: hsync as above; field A vsync lines 0..2 of the 525-line
// frame from the hsync rise, field B from 1707 clocks after the hsync rise
// of line 262 to the same point of line 265
reg        src_i = 0;
reg  [9:0] fv = 0;
reg        vs_i = 0;
always @(posedge clk) begin
	if (sh == 12'd3412) fv <= (fv == 10'd524) ? 10'd0 : fv + 10'd1;
	if (sh == 12'd3412 && fv == 10'd524) vs_i <= 1'b1;
	if (sh == 12'd3412 && fv == 10'd2)   vs_i <= 1'b0;
	if (sh == 12'd1706 && fv == 10'd262) vs_i <= 1'b1;
	if (sh == 12'd1706 && fv == 10'd265) vs_i <= 1'b0;
end
wire vs = src_i ? vs_i : vs_p;

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
// 480i
localparam integer F2 = 525 * 3413;
integer t_src_a = -1, t_src_b = -1, t_nhs = -1, t_nvs = -1, iv = 0, iv_q = 0, na = 0, nb = 0;
reg     vfield_b = 0;

function automatic integer near(input integer o);
	integer m;
	begin
		m = o % F2;
		if (m > F2 / 2) m -= F2;
		near = m;
	end
endfunction

always @(posedge clk) begin
	n = n + 1;
	if (hs & ~hq) t_src_hs = n;
	if (vs & ~vq) t_src_vs = n;
	if (vs & ~vq) begin
		if (hs & ~hq) t_src_a = n; else t_src_b = n;
	end
	if (hs_o & ~hoq) t_nhs = n;
	if (check && src_i) begin
		if (hs_o & ~hoq) begin
			if (t_hs >= 0 && n - t_hs != 3413) begin errors++; $display("FAIL hsync period %0d", n - t_hs); end
			t_hs = n;
			nh++;
			hs_off = n - t_src_hs;
			if (hs_off > 3413 / 2) hs_off -= 3413;
			if (hs_off != exp_h) begin errors++; if (errors < 10) $display("FAIL hsync offset %0d, expected %0d", hs_off, exp_h); end
		end
		if (vs_o != voq) begin
			// field A edges on a new hsync rise, field B's 1707 clocks after it
			if (hs_o & ~hoq) begin
				if (vs_o) vfield_b = 0;
				else if (vfield_b) begin errors++; $display("FAIL 480i field B vsync fall on the hsync rise"); end
			end else if (n - t_nhs == 1707) begin
				if (vs_o) vfield_b = 1;
				else if (!vfield_b) begin errors++; $display("FAIL 480i field A vsync fall mid-line"); end
			end else begin
				errors++; $display("FAIL 480i vsync edge %0d clocks after the new hsync rise", n - t_nhs);
			end
			if (vs_o) begin
				nv++;
				if (vfield_b) nb++; else na++;
				if (seen_vs && vs_lines != 3) begin errors++; $display("FAIL 480i vsync %0d lines", vs_lines); end
				vs_lines = 0;
				vs_off = near(n - (vfield_b ? t_src_b : t_src_a));
				if (vs_off != exp_v) begin errors++; $display("FAIL 480i field %s vsync offset %0d, expected %0d", vfield_b ? "B" : "A", vs_off, exp_v); end
				if (t_nvs >= 0) begin
					iv = n - t_nvs;
					if (iv != 895912 && iv != 895913) begin errors++; $display("FAIL 480i vsync interval %0d", iv); end
					if (iv_q != 0 && iv == iv_q) begin errors++; $display("FAIL 480i vsync intervals do not alternate (%0d twice)", iv); end
					iv_q = iv;
				end
				t_nvs = n;
				seen_vs = 1;
			end
		end
		if (vs_o & hs_o & ~hoq) vs_lines++;
	end else if (check) begin
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

task automatic run_i(input integer h, input integer v);
	begin
		crt_h = h[3:0];
		crt_v = v[2:0];
		repeat (6 * 263 * 3413) @(posedge clk);
		exp_h = -2 * h * 8 + c0;
		exp_v = -v * 3413 - 2 * h * 8 + c0;
		if (h == 0 && v == 0) begin exp_h = 0; exp_v = 0; end
		t_hs = -1; nh = 0; nv = 0; na = 0; nb = 0; seen_vs = 0; t_nvs = -1; iv_q = 0; vs_lines = 0;
		check = 1;
		repeat (4 * 263 * 3413) @(posedge clk);
		check = 0;
		if (na < 1 || nb < 1) begin errors++; $display("FAIL 480i fields A %0d, B %0d", na, nb); end
		$display("480i h %0d v %0d: %0d hsyncs, offset %0d; %0d vsyncs (A %0d, B %0d), last offset %0d, last interval %0d; errors %0d",
		         h, v, nh, hs_off, nv, na, nb, vs_off, iv, errors);
	end
endtask

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
	// 480i source (issue #3)
	src_i = 1;
	run_i(0, 0);
	run_i(-1, 0);
	run_i(1, 0);
	run_i(7, 0);
	run_i(-8, 0);
	run_i(0, 1);
	run_i(0, 3);
	run_i(0, -4);
	run_i(5, -2);
	run_i(-6, 2);
	run_i(0, 0);
	// back to 240p: the same results as the first runs
	src_i = 0;
	run(0, 0);
	run(-1, 0);
	run(0, 3);
	run(5, -2);
	run(0, 0);
	if (errors == 0) $display("PASS"); else $display("FAILED %0d", errors);
	$finish;
end

endmodule
