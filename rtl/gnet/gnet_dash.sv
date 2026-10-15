//============================================================================
//  G-NET core: Dash button (Chaos Heat, issue #7)
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// Chaos Heat (chaoshea, chaosheaj) dashes on a double tap of a direction.
// With the game configuration byte's bit 4 set (MRA rom index 7), a Dash
// button does the double tap for the player: pressed while a direction is
// held, the direction is released for GAP frames, pressed for TAP frames,
// released for GAP frames and pressed for TAP frames, then the stick passes
// through again (still held, the player keeps running after the dash).
// Frames are the core's VBLANKs; the sequence starts at the next VBLANK
// (the direction held at the press is kept until then).
//
// Measured in MAME 0.288 (sim/oracle/dash, chaoshea in play, player X and Z
// words 0x1426ec/0x1426f0 every frame, both VBLANK phases): a dash when the
// second press starts at most 14 frames after the first press starts (15 in
// one phase) and the release between them is at least 2 frames (1 in one
// phase); a first press of 2 to 12 frames works, 16 or more never (a held
// direction is a walk). From a held direction the game needs the release
// before the first tap. GAP 4 and TAP 4 put the second press 8 frames after
// the first: 6 frames inside the limit, the gaps 2 frames above the minimum.
// All 8 directions dash with this sequence (both phases), and a walk does
// not reach the dash speed (150 units a frame against 82).
//
// hold: while 1 (the core is paused) the frame count stops.

module gnet_dash #(
	parameter integer GAP = 4,
	parameter integer TAP = 4
)
(
	input            clk,
	input            en,        // configuration bit 4
	input            hold,      // paused
	input            vbl,       // core VBLANK, any clock domain
	input            btn,       // Dash, pressed = 1
	input      [3:0] dir_in,    // U D L R, pressed = 1
	output     [3:0] dir_out,
	output           busy
);

localparam integer MX = (GAP > TAP) ? GAP : TAP;
localparam integer W  = $clog2(MX + 1);
localparam [2:0] S_IDLE = 3'd0, S_ARM = 3'd1, S_REL1 = 3'd2, S_TAP1 = 3'd3, S_REL2 = 3'd4, S_TAP2 = 3'd5;

reg  [2:0]   vbl_s = 3'd0;
reg          btn_q = 1'b0;
reg  [2:0]   st    = S_IDLE;
reg  [W-1:0] cnt   = '0;
reg  [3:0]   dir   = 4'd0;

wire tick  = vbl_s[1] & ~vbl_s[2] & ~hold;
wire press = btn & ~btn_q;
wire last  = (cnt == '0);

always @(posedge clk) begin
	vbl_s <= {vbl_s[1:0], vbl};
	btn_q <= btn;
	case (st)
		S_IDLE: if (en & press & (dir_in != 4'd0)) begin dir <= dir_in; st <= S_ARM; end
		S_ARM:  if (tick) begin st <= S_REL1; cnt <= W'(GAP - 1); end
		S_REL1: if (tick) begin if (last) begin st <= S_TAP1; cnt <= W'(TAP - 1); end else cnt <= cnt - 1'b1; end
		S_TAP1: if (tick) begin if (last) begin st <= S_REL2; cnt <= W'(GAP - 1); end else cnt <= cnt - 1'b1; end
		S_REL2: if (tick) begin if (last) begin st <= S_TAP2; cnt <= W'(TAP - 1); end else cnt <= cnt - 1'b1; end
		S_TAP2: if (tick) begin if (last) st <= S_IDLE; else cnt <= cnt - 1'b1; end
		default: st <= S_IDLE;
	endcase
	if (~en) st <= S_IDLE;
end

assign dir_out = ((st == S_REL1) | (st == S_REL2)) ? 4'd0 :
                 ((st == S_ARM) | (st == S_TAP1) | (st == S_TAP2)) ? dir : dir_in;
assign busy    = (st != S_IDLE);

endmodule

// The pad's J1 bits with Dash in the MRA button list (en = configuration bit
// 4): the MRA names Button 1, Button 2, Button 3, Dash, Start, Coin,
// Service, Test, Pause, so Dash is bit 7 and Start to Pause are bits 8-12.
// Moved back to the core's J1 list (7 Start ... 11 Pause); bit 12 reads 0
// and bits 13-19 (16 and 17 are the PSX base's savestate and fast forward)
// pass through. With en 0 the pad passes through and dash reads 0.
module gnet_dash_remap
(
	input         en,
	input  [19:0] in,
	output [19:0] out,
	output        dash
);
assign out  = en ? {in[19:13], 1'b0, in[12:8], in[6:0]} : in;
assign dash = en & in[7];
endmodule
