//============================================================================
//  G-NET core: CPU group clock PLL (R1, docs/r1_cpu_domain_design.md)
//  Copyright (C) 2026 Lee Foot
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// Used only with the GNET_CPU50 macro (PSX.sv). Two outputs from one VCO:
//   outclk_0  50.000000 MHz  clk_cpu   (cpu, memorymux, memctrl, dma, irq,
//                                       timer, sio, exp2, SDRAM clk_base)
//   outclk_1 100.000000 MHz  clk_cpu2x (GTE, scratchpad and icache ports,
//                                       DMA FIFO, SDRAM controller)
// Both are integer multiples of the 50 MHz reference, so the PLL runs in
// integer mode (fractional_vco_multiplier "false"); Quartus picks M/N/C (for
// example VCO 400 MHz, C 8 and 4), the fit report's PLL summary confirms.
// Phase 0 on both outputs of one VCO in direct mode: the counters start
// together, so the two clocks are phase-aligned and STA times clk_cpu to
// clk_cpu2x paths as synchronous (the relation clk_1x and clk_2x have in
// rtl/pll/pll_0002.v). Same altera_pll form as rtl/gnet/pll_vid_fixed.v
// (General type and subtype, no reconfiguration port).

`timescale 1ns/10ps
module pll_cpu
(
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire outclk_1,
	output wire locked
);

	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(2),
		.output_clock_frequency0("50.000000 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.output_clock_frequency1("100.000000 MHz"),
		.phase_shift1("0 ps"),
		.duty_cycle1(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst     (rst),
		.outclk  ({outclk_1, outclk_0}),
		.locked  (locked),
		.fboutclk( ),
		.fbclk   (1'b0),
		.refclk  (refclk)
	);

endmodule
