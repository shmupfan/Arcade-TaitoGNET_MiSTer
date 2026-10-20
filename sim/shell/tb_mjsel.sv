// Mahjong sets: Select + L = Service, Select + R = Test on the pad
// (docs/m4_shell.md 3). Runs PSX.sv's own mahjong pad block, zj1 wire and
// coin 1 pulse instance (work/mjsel_psx.svh from gen_pausewd.py; 100 ms
// coin = 3,386,880 clk_1x clocks). Cases, Usagi (gnet_inmode 2) and
// Mahjong Oh (1):
//   Select tap: one 100 ms coin after the release;
//   Select + L: Service held while both are held, no coin, L not a shift;
//   Select + R: Test held, no coin, R not a shift;
//   R alone: shift as before (s1 gives tile I), no Test, no coin;
//   keyboard 9 and F2 still Service and Test;
// and joystick mode 0: Select is a coin on press, L and R do nothing here.
// Run with sim/shell/run_mjsel.sh
`timescale 1ns/1ps
module tb_mjsel;

reg clk_1x = 0;
always #14.7629 clk_1x = ~clk_1x;   // 33.8688 MHz

logic [19:0] joy_g = '0;
logic  [1:0] gnet_inmode = 2'd2;
reg k_up = 0, k_dn = 0, k_lt = 0, k_rt = 0, k_b1 = 0, k_b2 = 0, k_b3 = 0;
reg k_st1 = 0, k_co1 = 0, k_svc = 0, k_test = 0;
reg paused = 0;
wire zc1;

`include "mjsel_psx.svh"

localparam integer PULSE = 3386880;
localparam integer MS = 33869;   // clocks per ms

integer errors = 0;
task automatic check(input bit cond, input string what);
	if (!cond) begin
		errors++;
		$display("FAIL %s (t=%0t)", what, $time);
	end else
		$display("ok   %s", what);
endtask

logic zc1_q = 0;
// coin edges and length, Service/Test seen, over n clocks
integer coins, coin_len, svc_n, test_n;
task automatic run(input integer n);
	repeat (n) begin
		@(posedge clk_1x);
		#1;
		if (zc1) coin_len++;
		if (zc1 & ~zc1_q) coins++;
		zc1_q = zc1;
		if (zj1[9]) svc_n++;
		if (zj1[10]) test_n++;
	end
endtask
task automatic clr();
	coins = 0; coin_len = 0; svc_n = 0; test_n = 0;
endtask

localparam SEL = 8, L = 13, R = 14, S1 = 1;   // S1 = pad Left (mahjong s1)

task automatic mj_cases(input string set);
	// Select tap: coin after release
	clr();
	joy_g[SEL] = 1; run(50 * MS);
	check(coins == 0, {set, ": Select held, no coin before the release"});
	joy_g[SEL] = 0; run(250 * MS);
	check(coins == 1 && coin_len == PULSE, $sformatf("%s: Select tap = one 100 ms coin (coins %0d, %0d clocks)", set, coins, coin_len));
	check(svc_n == 0 && test_n == 0, {set, ": Select tap, no Service or Test"});

	// Select + L
	clr();
	joy_g[SEL] = 1; run(20 * MS);
	joy_g[L] = 1; run(100 * MS);
	check(svc_n == 100 * MS && test_n == 0, $sformatf("%s: Select + L = Service held (%0d clocks)", set, svc_n));
	joy_g[S1] = 1; run(5 * MS);
	check(!mp_l[0] && !mp_r[0], {set, ": Select + L, s1 is not Kan (L not a shift)"});
	joy_g[S1] = 0; run(5 * MS);
	joy_g[L] = 0; run(20 * MS);
	joy_g[SEL] = 0; run(250 * MS);
	check(coins == 0, {set, ": Select + L, no coin"});

	// Select + R, R released after Select
	clr();
	joy_g[SEL] = 1; run(20 * MS);
	joy_g[R] = 1; run(100 * MS);
	check(test_n == 100 * MS && svc_n == 0, $sformatf("%s: Select + R = Test held (%0d clocks)", set, test_n));
	joy_g[S1] = 1; run(5 * MS);
	check(!mp_r[0] && !mp_l[0], {set, ": Select + R, s1 is not tile I (R not a shift)"});
	joy_g[S1] = 0; run(5 * MS);
	joy_g[SEL] = 0; run(20 * MS);
	joy_g[R] = 0; run(250 * MS);
	check(coins == 0, {set, ": Select + R, no coin"});

	// R alone: shift
	clr();
	joy_g[R] = 1; run(10 * MS);
	joy_g[S1] = 1; run(10 * MS);
	check(mp_r[0] && mp_mj[8], {set, ": R alone + s1 = tile I (shift as before)"});
	joy_g[S1] = 0; run(5 * MS);
	joy_g[R] = 0; run(150 * MS);
	check(coins == 0 && test_n == 0 && svc_n == 0, {set, ": R alone, no coin, Service or Test"});

	// keyboard 9 and F2
	clr();
	k_svc = 1; run(MS); k_svc = 0;
	k_test = 1; run(MS); k_test = 0; run(10);
	check(svc_n == MS && test_n == MS, {set, ": keyboard 9 / F2 = Service / Test"});
endtask

initial begin
	run(100);
	gnet_inmode = 2'd2; mj_cases("Usagi");
	gnet_inmode = 2'd1; mj_cases("Mahjong Oh");

	gnet_inmode = 2'd0;
	clr();
	joy_g[SEL] = 1; run(20 * MS);
	check(coins == 1, "joystick sets: Select coins on press, as before");
	joy_g[R] = 1; joy_g[L] = 1; run(20 * MS);
	check(svc_n == 0 && test_n == 0, "joystick sets: Select + L / R, no Service or Test");
	joy_g = '0; run(250 * MS);
	check(coins == 1, "joystick sets: one coin");

	if (errors == 0) $display("tb_mjsel: PASS");
	else $display("tb_mjsel: FAIL (%0d)", errors);
	$finish;
end

endmodule
