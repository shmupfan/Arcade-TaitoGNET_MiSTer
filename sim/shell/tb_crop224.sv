// OSD Crop 224 lines (rtl/gnet/gnet_crop224.sv): replay of the real video
// out (rtl/gpu_videoout_async.vhd, trace from tb_vtrace.vhd) through the
// crop and PSX.sv's video_aspect vblank and RGB rule, with the crop On and
// Off.
//
// Per frame (vblank rise to vblank rise, whole frames only), with the
// crop's output applied as video_aspect does (vb = vblank | blank):
//   DE lines (lines with any dot where hb and vb are both low), the source
//   line index (0 to 239, counted from the trace) of the first and last DE
//   line, dots per DE line; and output vblank (vb | blank) edges that are
//   not inside an hblank (on a drawn dot or on the hblank falling dot):
//   must be 0, as the source's own vblank edges.
// Pass, 240p: On gives 224 lines, source lines 8 to 231, the full width
// on every line; Off gives 240 lines and blank never high. 480i: blank
// never high either way.
//
// Run with sim/shell/run_crop224.sh
`timescale 1ns/1ps
module tb_crop224;

reg clk = 0;
always #9.3121 clk = ~clk;   // 53.693175 MHz

string  trace;
integer width, ilace, en_arg;
integer fd, n, d, ihs, ivs, ihb, ivb;

reg ce = 0, hb = 1, vb = 1, en = 0, interlace = 0;
wire blank;

gnet_crop224 dut
(
	.clk(clk), .ce(ce), .en(en), .interlace(interlace),
	.hb(hb), .vb(vb), .blank(blank)
);

integer frames = 0, errors = 0;
integer src_line = -1, de_lines = 0, first_de = -1, last_de = -1;
integer dots = 0, bad_blank = 0;
reg     line_has_de = 0, old_hb = 1, old_vb = 1, in_frame = 0, old_vbo = 1, ever_blank = 0;

task end_line;
	if (line_has_de) begin
		de_lines = de_lines + 1;
		if (first_de < 0) first_de = src_line;
		last_de = src_line;
		if (dots != width) begin
			$display("ERROR frame %0d source line %0d: %0d dots, expected %0d", frames, src_line, dots, width);
			errors = errors + 1;
		end
	end
	line_has_de = 0;
	dots = 0;
endtask

task end_frame;
	integer want_lines, want_first, want_last;
	want_lines = (en && !ilace) ? 224 : 240;
	want_first = (en && !ilace) ? 8 : 0;
	want_last  = (en && !ilace) ? 231 : 239;
	$display("frame %0d: DE lines %0d, source lines %0d to %0d, vblank edges outside hblank %0d",
	         frames, de_lines, first_de, last_de, bad_blank);
	if (de_lines != want_lines || first_de != want_first || last_de != want_last || bad_blank != 0) begin
		$display("ERROR frame %0d: expected %0d lines, %0d to %0d, 0 edges outside hblank", frames, want_lines, want_first, want_last);
		errors = errors + 1;
	end
	frames = frames + 1;
endtask

initial begin
	if (!$value$plusargs("trace=%s", trace)) trace = "work/vtrace_1.txt";
	if (!$value$plusargs("width=%d", width)) width = 320;
	if (!$value$plusargs("ilace=%d", ilace)) ilace = 0;
	if (!$value$plusargs("en=%d", en_arg)) en_arg = 1;
	en = en_arg[0];
	interlace = ilace[0];
	fd = $fopen(trace, "r");
	if (fd == 0) begin $display("ERROR: cannot open %s", trace); $finish; end
	while (!$feof(fd)) begin
		n = $fscanf(fd, "%d %d %d %d %d\n", d, ihs, ivs, ihb, ivb);
		if (n != 5) break;
		repeat (d > 1 ? d - 1 : 0) @(posedge clk);
		@(negedge clk);
		hb = ihb[0];
		vb = ivb[0];
		ce = 1;
		#1;   // blank is combinational from hb, vb and ce-updated state
		// line and frame bookkeeping on the source signals
		if (old_hb && !hb && !vb) begin
			src_line = src_line + 1;
		end
		if (!old_hb && hb) end_line();
		if (!old_vb && vb) begin
			end_line();
			if (in_frame) end_frame();
			in_frame = 1;
			de_lines = 0; first_de = -1; last_de = -1; bad_blank = 0;
		end
		if (vb) src_line = -1;
		if (!hb && !vb && !blank) begin
			line_has_de = 1;
			dots = dots + 1;
		end
		if (((vb | blank) != old_vbo) && !hb) bad_blank = bad_blank + 1;
		if (blank) ever_blank = 1;
		old_vbo = vb | blank;
		old_hb = hb;
		old_vb = vb;
		@(posedge clk);
		#1 ce = 0;
	end
	$fclose(fd);
	if ((!en || ilace) && ever_blank) begin $display("ERROR: blank high with the crop Off or in 480i"); errors = errors + 1; end
	if (frames == 0) begin $display("ERROR: no whole frame in the trace"); errors = errors + 1; end
	if (errors == 0) $display("PASS (%0d frames, crop %s)", frames, en ? "On" : "Off");
	else $display("FAIL: %0d errors", errors);
	$finish;
end

endmodule
