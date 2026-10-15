//============================================================================
//  G-NET core: coin input pulse
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// One coin button (pad or keyboard, pressed = 1) to the coin switch the game
// reads: each press gives one pulse of PULSE clocks, however long the button
// is held, then at least PULSE clocks released before the next pulse. A
// press during a pulse or the gap after it is kept (one only) and starts
// the next pulse when the gap ends; a new press needs a release first.
//
// Why: a coin mech closes its switch briefly as the coin drops. Space
// Invaders Anniversary treats a coin switch held for 30 VBLANKs (0.5 s) as
// a jammed mech and stops with COIN ERROR until the watchdog resets it (MAME
// 0.288, routine 0x8001102c); a 0.1 s coin is counted. PSX.sv uses 100 ms
// (3,386,880 clk_1x clocks at 33.8688 MHz): six frames, well inside the jam
// limit and long enough for a game that polls the switch once per frame.
// This is an input-handling choice of the core, not board behaviour (the
// ZN-2 board passes the switch level straight through).
//
// hold: while 1 the timer stops (the core is paused), so a pulse is not
// spent while the game cannot see it.

module gnet_coin_pulse #(
	parameter integer PULSE = 3386880
)
(
	input      clk,
	input      hold,
	input      in,
	output     out
);

localparam integer W     = $clog2(2 * PULSE + 1);
localparam [W-1:0] START = 2 * PULSE - 1;
localparam [W-1:0] HALF  = PULSE;

reg [W-1:0] cnt  = '0;   // 2*PULSE-1 down to PULSE: pulse; PULSE-1 down to 1: gap
reg         in_q = 1'b0;
reg         pend = 1'b0;

wire press = in & ~in_q;

always @(posedge clk) begin
	in_q <= in;
	if (cnt == '0) begin
		if (press | pend) cnt <= START;
		pend <= 1'b0;
	end else begin
		if (press) pend <= 1'b1;
		if (~hold) cnt <= cnt - 1'b1;
	end
end

assign out = (cnt >= HALF);

endmodule
