//============================================================================
//  G-NET core: dim the picture during a long pause
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// OSD "Dim video after 10s" (docs/m4_shell.md 4), the convention of the
// official MiSTer arcade cores: after the core has been paused for DIM_CLKS
// clocks of clk (any pause: the Pause button, the P key or the OSD), the
// RGB is halved to reduce burn-in; it is restored on the first clk_vid
// clock after the dim flag crosses once the pause ends or the option is
// switched Off. Written for this core (not derived from Pause_MiSTer).
//
// clk: the clock of `paused` (clk_1x, 33.8688 MHz; 10 s = 338,688,000).
// clk_vid: the video clock. rgb_out is combinational from rgb_in, so the
// picture keeps its alignment with the syncs, which do not pass through
// here.

module gnet_pause_dim #(
	parameter integer DIM_CLKS = 338688000
) (
	input  logic        clk,
	input  logic        paused,
	input  logic        dim_en,     // 1 = dim after DIM_CLKS of pause
	output logic        dim = 1'b0, // on clk

	input  logic        clk_vid,
	input  logic [23:0] rgb_in,
	output logic [23:0] rgb_out
);

localparam integer CW = $clog2(DIM_CLKS + 1);

logic [CW-1:0] cnt = '0;
always_ff @(posedge clk) begin
	if (!paused || !dim_en) begin
		cnt <= '0;
		dim <= 1'b0;
	end else if (cnt == CW'(DIM_CLKS - 1)) begin
		dim <= 1'b1;
	end else begin
		cnt <= cnt + 1'd1;
	end
end

// dim is a level that changes at most twice per pause: two flops into
// clk_vid
logic [1:0] dim_v = 2'b00;
always_ff @(posedge clk_vid) dim_v <= {dim_v[0], dim};

assign rgb_out = dim_v[1] ? {1'b0, rgb_in[23:17], 1'b0, rgb_in[15:9], 1'b0, rgb_in[7:1]} : rgb_in;

endmodule
