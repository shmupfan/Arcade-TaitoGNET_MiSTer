`timescale 1ns/1ps
module tb;
reg        clk_1x = 0;
reg [15:0] joystick_analog_l0 = 0;
reg  [7:0] paddle_0 = 0;
reg [19:0] zj1 = 0;
reg        gnet_rc = 1;
`include "rc_block.svh"
always #5 clk_1x = ~clk_1x;
integer x, y, errs = 0, n = 0;
task chk(input [7:0] e0, input [7:0] e1, input [255:0] what);
  begin
    #1; n = n + 1;
    if (zn_an0 !== e0 || zn_an1 !== e1) begin
      errs = errs + 1;
      $display("FAIL %0s: X=%0d Y=%0d zj1=%h pad=%0d paddle=%0d -> %h %h, want %h %h", what,
        $signed(joystick_analog_l0[7:0]), $signed(joystick_analog_l0[15:8]), zj1[3:0], rc_paddle, paddle_0, zn_an0, zn_an1, e0, e1);
    end
  end
endtask
function [7:0] trig(input integer yy);
  integer t; begin t = 128 - yy; if (t > 255) t = 255; trig = t[7:0]; end
endfunction
initial begin
  repeat (4) @(posedge clk_1x);
  // rest = MAME's rest (80h, 80h)
  chk(8'h80, 8'h80, "rest");
  // full sweep of both axes, no D-pad
  for (x = -128; x <= 127; x = x + 1) for (y = -128; y <= 127; y = y + 1) begin
    joystick_analog_l0 = {y[7:0], x[7:0]}; @(posedge clk_1x);
    chk((x + 128) & 8'hFF, trig(y), "sweep");
  end
  // stick extremes the pad reports (-127..+127)
  joystick_analog_l0 = {8'd0, 8'h81}; @(posedge clk_1x); chk(8'h01, 8'h80, "X -127");
  joystick_analog_l0 = {8'd0, 8'h7F}; @(posedge clk_1x); chk(8'hFF, 8'h80, "X +127");
  joystick_analog_l0 = {8'h81, 8'd0}; @(posedge clk_1x); chk(8'h80, 8'hFF, "Y -127 (up)");
  joystick_analog_l0 = {8'h7F, 8'd0}; @(posedge clk_1x); chk(8'h80, 8'h01, "Y +127 (down)");
  // D-pad with the stick at rest or inside the dead band: full deflection
  joystick_analog_l0 = 0;
  zj1 = 20'h2; @(posedge clk_1x); chk(8'h00, 8'h80, "dpad L");
  zj1 = 20'h1; @(posedge clk_1x); chk(8'hFF, 8'h80, "dpad R");
  zj1 = 20'h8; @(posedge clk_1x); chk(8'h80, 8'hFF, "dpad U");
  zj1 = 20'h4; @(posedge clk_1x); chk(8'h80, 8'h00, "dpad D");
  joystick_analog_l0 = {8'hF6, 8'h0A}; zj1 = 20'h9; @(posedge clk_1x); chk(8'hFF, 8'hFF, "dpad R+U, stick in dead band");
  // D-pad bits set by a deflected stick: the analog value wins
  joystick_analog_l0 = {8'hC0, 8'h40}; zj1 = 20'h9; @(posedge clk_1x); chk(8'hC0, 8'hC0, "stick R+U with D-pad bits");
  joystick_analog_l0 = {8'h40, 8'hC0}; zj1 = 20'h6; @(posedge clk_1x); chk(8'h40, 8'h40, "stick L+D with D-pad bits");
  zj1 = 0;
  // other sets: FFh on both
  gnet_rc = 0; joystick_analog_l0 = {8'h40, 8'hC0}; @(posedge clk_1x); chk(8'hFF, 8'hFF, "not gobyrc");
  gnet_rc = 1; joystick_analog_l0 = 0;
  // paddle resting at FFh or FEh is not movement (old 8-bit sum wrapped)
  paddle_0 = 8'hFF; repeat (3) @(posedge clk_1x);
  joystick_analog_l0 = {8'd0, 8'h50}; repeat (2) @(posedge clk_1x);   // stick clears the paddle flag
  joystick_analog_l0 = 0; repeat (5) @(posedge clk_1x);
  chk(8'h80, 8'h80, "paddle at rest FFh");
  paddle_0 = 8'hFE; repeat (5) @(posedge clk_1x);
  chk(8'h80, 8'h80, "paddle at rest FEh (1 step)");
  // paddle moves: it drives the wheel, the D-pad no longer overrides it
  paddle_0 = 8'h20; repeat (2) @(posedge clk_1x); chk(8'h20, 8'h80, "paddle moved");
  zj1 = 20'h1; @(posedge clk_1x); chk(8'h20, 8'h80, "paddle with dpad R"); zj1 = 0;
  // stick moves: back to the stick
  joystick_analog_l0 = {8'd0, 8'h50}; repeat (2) @(posedge clk_1x); chk(8'hD0, 8'h80, "stick takes over");
  $display("bench: %0d checks, %0d failures", n, errs);
  $finish;
end
endmodule
