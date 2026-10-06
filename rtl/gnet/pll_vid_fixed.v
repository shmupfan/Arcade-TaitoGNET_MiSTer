//============================================================================
//  G-NET core: fixed video clock PLL
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// Replaces PSX_MiSTer's reconfigurable pll2 + pll_cfg in GNET_LEAN builds.
// pll2's static setting is already 53.693175 MHz (NTSC), which is also the
// ZN-2 GPU dot clock crystal (MAME zn.cpp: CXD8654Q at 53.693175 MHz). The
// runtime reconfiguration only serves PAL, fast-forward and a debug clock,
// none of which exist on G-NET. Same altera_pll parameters as pll2_0002.v,
// General subtype so no reconfiguration port is built.

`timescale 1ns/10ps
module pll_vid_fixed
(
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("53.693175 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst     (rst),
		.outclk  ({outclk_0}),
		.locked  (locked),
		.fboutclk( ),
		.fbclk   (1'b0),
		.refclk  (refclk)
	);

endmodule
