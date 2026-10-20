// Pause options and Service Menu (docs/m4_shell.md 4 and 5): PSX.sv's own
// pause/reset block, pause button wire and zn_dsw port expression
// (work/pausewd_psx.svh and work/pausesvc_psx.svh from gen_pausewd.py,
// GNET_SHELL defined) with gnet_pause_dim at a scaled DIM_CLKS. Checks:
//   1 the Pause button (pad bit 11, either player) and the P key toggle the
//     pause, with no OSD gate;
//   2 the RGB halves DIM_CLKS clocks into a pause (Dim On), not before;
//   3 unpausing restores the RGB within 3 video clocks;
//   4 Dim Off: no dimming however long the pause;
//   5 OSD pause (Pause when OSD is open On) also dims; OSD pause Off: no pause;
//   6 a reset cancels the button pause;
//   7 Service Menu On clears DSW bit 3 (S551:4 Test Mode on), Off passes
//     the MRA byte; bits 2:0 untouched.
// Run with sim/shell/run_pausedim.sh
`timescale 1ns/1ps
`ifndef GNET_SHELL
`define GNET_SHELL
`endif
module tb_pausedim;

localparam integer DIM = 1000;   // 10 s scaled to 1000 clk_1x clocks

reg clk_1x = 0;
always #14.7629 clk_1x = ~clk_1x;   // 33.8688 MHz
reg clk_vid = 0;
always #9.3121 clk_vid = ~clk_vid;  // 53.693175 MHz

logic [127:0] status = '0;
logic         OSD_STATUS = 0;
logic         por = 0;
logic  [19:0] zj1 = '0, zj2 = '0;
logic         k_p = 0;

// PSX.sv names used by the included text
reg paused = 0;
reg [9:0] unpause = 0;
reg status1_1;
reg [20:0] aliveCnt = 0;
reg heartbeat_1 = 0;
reg hps_busy = 0;
wire heartbeat = 1'b0;
reg reset = 0;
reg buttonpause_1 = 0;
reg button_paused = 0;
reg TURBO_MEM, TURBO_COMP, TURBO_CACHE, TURBO_CACHE50;
wire zn_wd_reset = 1'b0;
wire zn_wd_mask;
reg [7:0] zn_wd_hold = 0;
wire reset_or = por | (zn_wd_hold != 0);
reg  [7:0] zn_sw0 = 8'h0F;
wire [3:0] zn_dsw_eff;

`include "pausesvc_psx.svh"
`include "pausewd_psx.svh"

wire        dim;
wire [23:0] rgb_out;
logic [23:0] rgb_in = 24'hFF_80_41;
gnet_pause_dim #(.DIM_CLKS(DIM)) pause_dim (
	.clk(clk_1x), .paused(paused), .dim_en(~status[120]), .dim(dim),
	.clk_vid(clk_vid), .rgb_in(rgb_in), .rgb_out(rgb_out)
);

integer errors = 0;
task automatic check(input bit cond, input string what);
	if (!cond) begin
		errors++;
		$display("FAIL %s (t=%0t paused=%0d dim=%0d rgb=%06h)", what, $time, paused, dim, rgb_out);
	end else
		$display("ok   %s", what);
endtask

task automatic clks(input integer n);
	repeat (n) @(posedge clk_1x);
endtask

task automatic press(input integer which);   // 0 P1 pad, 1 P2 pad, 2 P key
	case (which)
		0: zj1[11] = 1;
		1: zj2[11] = 1;
		default: k_p = 1;
	endcase
	clks(20);
	zj1[11] = 0; zj2[11] = 0; k_p = 0;
	clks(20);
endtask

localparam [23:0] HALF = 24'h7F_40_20;
integer i;
logic seen_dim;

initial begin
	clks(10);
	check(!paused && rgb_out == rgb_in, "start: running, full RGB");

	// 1, 2, 3: P1 pad pause, dim at DIM, restore on unpause
	press(0);
	check(paused, "1 P1 Pause button pauses (no OSD gate)");
	clks(DIM - 100);
	check(rgb_out == rgb_in, "2 no dim before DIM clocks of pause");
	clks(150);
	check(rgb_out == HALF, "2 RGB halved after DIM clocks of pause");
	press(1);
	check(!paused, "1 P2 Pause button unpauses");
	repeat (3) @(posedge clk_vid);
	#1 check(rgb_out == rgb_in, "3 RGB restored within 3 video clocks of unpause");

	// P key
	press(2);
	check(paused, "1 P key pauses");
	press(2);
	check(!paused, "1 P key unpauses");

	// 4: Dim Off
	status[120] = 1;
	press(0);
	seen_dim = 0;
	for (i = 0; i < 3 * DIM; i++) begin
		@(posedge clk_1x);
		if (rgb_out != rgb_in) seen_dim = 1;
	end
	check(paused && !seen_dim, "4 Dim Off: no dim over 3x DIM clocks");
	// switching Dim On mid-pause starts the count then
	status[120] = 0;
	clks(DIM + 50);
	check(rgb_out == HALF, "4 Dim switched On during a pause dims DIM clocks later");
	press(0);
	check(!paused, "unpause");
	repeat (3) @(posedge clk_vid);
	#1 check(rgb_out == rgb_in, "3 restored");

	// 5: OSD pause
	OSD_STATUS = 1;
	clks(10);
	check(paused, "5 OSD open pauses (Pause when OSD is open On)");
	clks(DIM + 50);
	check(rgb_out == HALF, "5 OSD pause dims after DIM clocks");
	OSD_STATUS = 0;
	clks(5);
	repeat (3) @(posedge clk_vid);
	#1 check(!paused && rgb_out == rgb_in, "5 OSD closed: running, RGB restored");
	status[64] = 1;
	OSD_STATUS = 1;
	clks(DIM + 50);
	check(!paused && rgb_out == rgb_in, "5 Pause when OSD is open Off: no pause, no dim");
	OSD_STATUS = 0;
	status[64] = 0;

	// 6: reset cancels the button pause
	press(0);
	check(paused, "6 paused");
	por = 1; clks(5); por = 0; clks(5);
	check(!paused && !button_paused, "6 reset cancels the button pause");

	// 7: Service Menu
	zn_sw0 = 8'h0F; status[121] = 0; clks(2);
	check(zn_dsw_eff == 4'hF, "7 Service Menu Off: DSW = MRA (0F)");
	status[121] = 1; clks(2);
	check(zn_dsw_eff == 4'h7, "7 Service Menu On: DSW bit 3 cleared (07)");
	zn_sw0 = 8'h05; clks(2);
	check(zn_dsw_eff == 4'h5, "7 Service Menu On, MRA 05: bits 2:0 kept (05)");
	status[121] = 0; clks(2);
	check(zn_dsw_eff == 4'h5, "7 Service Menu Off, MRA 05: 05");
	zn_sw0 = 8'h07; clks(2);
	check(zn_dsw_eff == 4'h7, "7 MRA Test Mode On (07) stays on with the option Off");

	if (errors == 0) $display("tb_pausedim: PASS");
	else $display("tb_pausedim: FAIL (%0d)", errors);
	$finish;
end

endmodule
