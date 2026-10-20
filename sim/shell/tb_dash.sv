// Bench of gnet_dash and gnet_dash_remap (rtl/gnet/gnet_dash.sv, issue #7),
// a Verilator bench, run_dash.sh. A frame is FR clocks with VBLANK high for the
// first VB of them. A game model samples dir_out once per frame (at VBLANK
// rise, not while paused) and applies Chaos Heat's double tap rule as
// measured in MAME 0.288 (sim/oracle/dash), the strict form that held in
// both VBLANK phases: a press whose start is at most 14 frames after the
// previous press start, after a release of at least 2 frames, the previous
// press lasting at most 12 frames. Each case checks the sampled frames and
// the number of dashes the model sees.
`timescale 1ns/1ns
module tb_dash;

localparam integer FR = 1000, VB = 100;

logic       clk = 0, en = 0, hold = 0, vbl = 0, btn = 0;
logic [3:0] dir_in = 0;
wire  [3:0] dir_out;
wire        busy;

gnet_dash #(.GAP(4), .TAP(4)) dut (.clk(clk), .en(en), .hold(hold), .vbl(vbl), .btn(btn),
	.dir_in(dir_in), .dir_out(dir_out), .busy(busy));

logic        r_en = 0;
logic [19:0] r_in = 0;
wire  [19:0] r_out;
wire         r_dash;
gnet_dash_remap remap (.en(r_en), .in(r_in), .out(r_out), .dash(r_dash));

always #5 clk = ~clk;

// VBLANK, stopped with the game while paused is not modelled: the video
// keeps running and gnet_dash's hold stops the count
integer cyc = 0;
always @(posedge clk) begin
	cyc <= cyc + 1;
	vbl <= ((cyc % FR) < VB);
end

// game model
integer     frame = 0, dashes = 0;
logic [3:0] prev = 0;
integer     run_rel = 99, run_prs = 0, last_start = -99, last_len = 99;
string      seq = "";
logic       vq = 0;
always @(posedge clk) begin
	vq <= vbl;
	if (vbl & ~vq & ~hold) begin
		frame <= frame + 1;
		seq = {seq, $sformatf("%h", dir_out)};
		if ((dir_out != 0) & (prev == 0)) begin
			if ((frame - last_start <= 14) & (run_rel >= 2) & (last_len <= 12)) dashes <= dashes + 1;
			last_start = frame;
			run_prs = 1;
		end else if (dir_out != 0) run_prs = run_prs + 1;
		if (dir_out == 0) begin
			if (prev != 0) begin last_len = run_prs; run_rel = 0; end
			run_rel = run_rel + 1;
		end
		prev <= dir_out;
	end
end

integer fails = 0;
task automatic frames(input integer n);
	repeat (n * FR) @(posedge clk);
endtask
task automatic reset_model();
	@(posedge clk);
	dashes = 0; seq = ""; last_start = -99; last_len = 99; run_rel = 99; run_prs = 0;
endtask
task automatic check(input string name, input string want_seq, input integer want_dashes);
	if ((want_seq != "" && seq != want_seq) || dashes != want_dashes) begin
		$display("%-46s FAIL  seq %s (want %s)  dashes %0d (want %0d)", name, seq, want_seq, dashes, want_dashes);
		fails = fails + 1;
	end else
		$display("%-46s PASS  seq %s  dashes %0d", name, seq, dashes);
endtask
task automatic tap_btn();
	// pressed mid-frame, held 3 frames
	repeat (FR / 2 + 7) @(posedge clk);
	btn = 1; frames(3); btn = 0;
endtask

initial begin
	// 1: Right held, Dash, Right kept held: R, then 4 off, 4 on, 4 off, held
	en = 1; dir_in = 4'b0001; frames(10); reset_model();
	frames(5); fork tap_btn(); join; frames(17);
	check("1 held Right, Dash, Right still held", "11111110000111100001111111", 1);

	// 2: Dash, then Right let go at once: the sequence still completes
	dir_in = 4'b0001; frames(20); reset_model();
	frames(2); repeat (FR / 2) @(posedge clk); btn = 1; repeat (20) @(posedge clk); dir_in = 0; frames(1); btn = 0; frames(18);
	check("2 Dash, Right released straight away", "1111000011110000111100", 1);

	// 3: configuration bit 4 clear: Dash does nothing
	en = 0; dir_in = 4'b0001; frames(20); reset_model();
	frames(5); fork tap_btn(); join; frames(17);
	check("3 bit 4 clear: pass through", "1111111111111111111111111", 0);

	// 4: Dash with no direction: nothing
	en = 1; dir_in = 0; frames(20); reset_model();
	frames(5); fork tap_btn(); join; frames(17); dir_in = 4'b0001; frames(3);
	check("4 Dash with no direction held", "00000000000000000000000000111", 0);

	// 5: Up+Right held (diagonal), Dash: the diagonal is tapped
	dir_in = 4'b1001; frames(20); reset_model();
	frames(5); fork tap_btn(); join; frames(17);
	check("5 diagonal Up+Right", "9999990000999900009999999", 1);

	// 6: paused 10 frames inside the first tap: the count stops
	dir_in = 4'b0001; frames(20); reset_model();
	frames(5); fork tap_btn(); join; frames(2); hold = 1; frames(10); hold = 0; frames(15);
	check("6 pause during the sequence", "11111110000111100001111111", 1);

	// 7: Dash pressed again during the sequence: ignored; again after: a second dash
	dir_in = 4'b0001; frames(20); reset_model();
	frames(5); fork tap_btn(); join; frames(3); btn = 1; frames(2); btn = 0; frames(20);
	fork tap_btn(); join; frames(20);
	check("7 second press ignored while busy, then again", "", 2);

	// 8: bit 4 cleared during the sequence: back to the stick at once
	dir_in = 4'b0001; frames(20); reset_model();
	frames(5); fork tap_btn(); join; en = 0; frames(10); en = 1;
	check("8 bit 4 cleared mid sequence", "111111001111111111", 0);

	// 9: a plain held direction, no Dash: a walk
	dir_in = 4'b0001; frames(20); reset_model(); frames(40);
	check("9 held Right, no Dash", "", 0);

	// remap: MRA list Button 1-3, Dash, Start, Coin, Service, Test, Pause
	r_en = 1; r_in = 20'h0007F; #1;
	if (r_out != 20'h0007F || r_dash) begin $display("10 remap B1-3 and stick       FAIL %h %b", r_out, r_dash); fails++; end
	else $display("10 remap B1-3 and stick                         PASS");
	r_in = 20'h00080; #1;
	if (r_out != 20'h00000 || !r_dash) begin $display("11 remap Dash (bit 7)         FAIL %h %b", r_out, r_dash); fails++; end
	else $display("11 remap Dash bit 7 to dash only                PASS");
	r_in = 20'h01F00; #1;   // Start Coin Service Test Pause at 8-12
	if (r_out != 20'h00F80 || r_dash) begin $display("12 remap Start-Pause           FAIL %h", r_out); fails++; end
	else $display("12 remap Start-Pause bits 8-12 to 7-11           PASS");
	r_in = 20'h30000; #1;   // savestate, fast forward
	if (r_out != 20'h30000) begin $display("13 remap bits 16-17            FAIL %h", r_out); fails++; end
	else $display("13 remap bits 16-17 pass through               PASS");
	r_en = 0; r_in = 20'hFFFFF; #1;
	if (r_out != 20'hFFFFF || r_dash) begin $display("14 remap off                   FAIL %h", r_out); fails++; end
	else $display("14 remap off: identity, no dash                PASS");

	$display("%s: %0d failures", fails ? "FAIL" : "PASS", fails);
	$finish;
end

endmodule
