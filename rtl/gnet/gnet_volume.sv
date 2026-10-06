//============================================================================
//  G-NET core: OSD volume at the final mix
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// OSD Volume (minimum standard): 0 Normal, 1 +6 dB, 2 -6 dB, 3 -12 dB, on
// the signed 16-bit stereo output that goes to AUDIO_L/AUDIO_R. +6 dB
// saturates at the 16-bit limits instead of wrapping. One register stage on
// the core's audio clock; sys_top resamples AUDIO_L/R on its own clock as it
// does for every core. This is the last stage before the framework, so any
// later sound source (the Taito Zoom board) must be mixed into in_l/in_r.

module gnet_volume
(
	input                    clk,
	input              [1:0] vol,
	input  signed     [15:0] in_l,
	input  signed     [15:0] in_r,
	output reg signed [15:0] out_l = 16'sd0,
	output reg signed [15:0] out_r = 16'sd0
);

wire signed [16:0] l2 = {in_l, 1'b0};   // x2
wire signed [16:0] r2 = {in_r, 1'b0};

reg signed [15:0] l, r;

always @(*) begin
	case (vol)
		2'd1: begin
			l = (l2 > 17'sd32767) ? 16'sh7FFF : (l2 < -17'sd32768) ? 16'sh8000 : l2[15:0];
			r = (r2 > 17'sd32767) ? 16'sh7FFF : (r2 < -17'sd32768) ? 16'sh8000 : r2[15:0];
		end
		2'd2: begin
			l = in_l >>> 1;
			r = in_r >>> 1;
		end
		2'd3: begin
			l = in_l >>> 2;
			r = in_r >>> 2;
		end
		default: begin
			l = in_l;
			r = in_r;
		end
	endcase
end

always @(posedge clk) begin
	out_l <= l;
	out_r <= r;
end

endmodule
