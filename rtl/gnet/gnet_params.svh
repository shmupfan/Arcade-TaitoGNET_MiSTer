//============================================================================
//  G-NET core: build switch table (macros to localparams)
//  Copyright (C) 2026 Lee Foot
//  SPDX-License-Identifier: GPL-2.0-or-later
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================
//
// Origin: written for this core; moved out of PSX.sv unchanged (refactor step
//         11a, docs/refactor_audit.md 9).
// Evidence: none of its own; each switch cites its document below.
//
// Included by PSX.sv inside module emu, where this table stood: it turns the
// revision's VERILOG_MACRO switches into the localparams that PSX.sv passes to
// psx_mister as generics. Upstream builds define none of the macros, so every
// value falls back to upstream's.

// G-NET: GNET_LEAN fixes the console-only OSD options to constants so their
// logic is removed (docs/f0_budget.md 3.1). Without the macro every option
// stays live.
`ifdef GNET_LEAN
`define GNET_OPT(live, fixed) (fixed)
`else
`define GNET_OPT(live, fixed) (live)
`endif

// G-NET: trim switches (docs/f0_budget.md); upstream builds define none of
// these macros, so every block stays in.
`ifdef GNET_NO_CD
localparam GNET_HAS_CD = 0;
`else
localparam GNET_HAS_CD = 1;
`endif
`ifdef GNET_NO_PADS
localparam GNET_HAS_PADS = 0;
`else
localparam GNET_HAS_PADS = 1;
`endif
`ifdef GNET_NO_SAVESTATES
localparam GNET_HAS_SAVESTATES = 0;
`else
localparam GNET_HAS_SAVESTATES = 1;
`endif
`ifdef GNET_NO_CHEATS
localparam GNET_HAS_CHEATS = 0;
`else
localparam GNET_HAS_CHEATS = 1;
`endif
// MDEC: always built (issue #1); psx_top HAS_MDEC stays an upstream-default
// generic. The GNET_NO_MDEC trim of the early revisions is archived
// (docs/experiment_revisions.md).
localparam GNET_HAS_MDEC = 1;
// G-NET: area switches (docs/area.md). GNET_NO_DCACHE: the CPU's turbo data cache
// (cpu.vhd datacache, 64 M10K) is not built. Only with GNET_LEAN, which ties
// TURBO_CACHE to 0 so the cache's data is never used; without GNET_LEAN the
// macro is ignored and the OSD option keeps its cache.
`ifdef GNET_NO_DCACHE
`ifdef GNET_LEAN
localparam GNET_HAS_DCACHE = 0;
`else
localparam GNET_HAS_DCACHE = 1;
`endif
`else
localparam GNET_HAS_DCACHE = 1;
`endif
// GNET_NO_DBG: no debug overlay (zn_dbg_overlay below, OSD option O[101]) and
// no capture block (psx_top ZN2_DBG 0, rtl/gnet/zn_dbg_regs.vhd).
`ifdef GNET_NO_DBG
localparam GNET_ZN2_DBG = 0;
`else
localparam GNET_ZN2_DBG = 1;
`endif
`ifdef GNET_VRAM_2MB
localparam GNET_VRAM_Y_BITS = 10;   // ZN-2 CXD8654Q, 1024 x 1024 VRAM
`else
localparam GNET_VRAM_Y_BITS = 9;
`endif
`ifdef GNET_GTE_NARROW_MUL
localparam GNET_GTE_NARROW_MUL = `GNET_GTE_NARROW_MUL;   // 1, 2 or 3, see rtl/gte_mac123.vhd and rtl/gte.vhd
`else
localparam GNET_GTE_NARROW_MUL = 0;
`endif
`ifdef GNET_ZOOM
localparam GNET_ZOOM_BOARD = 1;  // Taito Zoom sound board (rtl/zoom, rtl/gnet/zoom_cdc.vhd)
`else
localparam GNET_ZOOM_BOARD = 0;
`endif
`ifdef GNET_DDR3_ARB
localparam GNET_ZOOM_INFL = 8;   // ZSG-2 reads outstanding behind the DDR3 arbiter (docs/ddr3_bandwidth.md 4.4, not in this tree)
`else
localparam GNET_ZOOM_INFL = 4;
`endif
// GPU VRAM read latency options (docs/gpu_read_infl.md); unset = upstream (1)
`ifdef GNET_GPU_READ_INFL
localparam GNET_GPU_READ_INFL = `GNET_GPU_READ_INFL;     // reads in flight / posted writes: 1, 2 or 4
`else
localparam GNET_GPU_READ_INFL = 1;
`endif
`ifdef GNET_TEX_FETCH_QW
localparam GNET_TEX_FETCH_QW = `GNET_TEX_FETCH_QW;       // texture cache fill per miss: 1 or 4 qwords
`else
localparam GNET_TEX_FETCH_QW = 1;
`endif
`ifdef GNET_TEX_FETCH_ROWS
localparam GNET_TEX_FETCH_ROWS = `GNET_TEX_FETCH_ROWS;   // texture rows per fill: 1, 2 or 4 (needs QW 4)
`else
localparam GNET_TEX_FETCH_ROWS = 1;
`endif
`ifdef GNET_TEX_MISS_DELAY
localparam GNET_TEX_MISS_DELAY = `GNET_TEX_MISS_DELAY;   // clk_2x cycles added to each texture cache fill (real GPU VRAM cost)
`else
localparam GNET_TEX_MISS_DELAY = 0;
`endif
// GPU texture timing model (docs/gpu_blend_timing.md); unset = 0 = off
`ifdef GNET_TEX_CACHE_BIG
localparam GNET_TEX_CACHE_BIG = `GNET_TEX_CACHE_BIG;     // 1 = 8 KB texture cache, fewer DDR3 fills
`else
localparam GNET_TEX_CACHE_BIG = 0;
`endif
`ifdef GNET_TEX_SPX_COST4
localparam GNET_TEX_SPX_COST4 = `GNET_TEX_SPX_COST4;     // clk_2x per psx-spx shadow cache miss, 4-bit pages
`else
localparam GNET_TEX_SPX_COST4 = 0;
`endif
`ifdef GNET_TEX_SPX_COST8
localparam GNET_TEX_SPX_COST8 = `GNET_TEX_SPX_COST8;     // 8-bit pages
`else
localparam GNET_TEX_SPX_COST8 = 0;
`endif
`ifdef GNET_TEX_SPX_COST15
localparam GNET_TEX_SPX_COST15 = `GNET_TEX_SPX_COST15;   // 15-bit pages
`else
localparam GNET_TEX_SPX_COST15 = 0;
`endif
`ifdef GNET_POLY_CLIP_X
localparam GNET_POLY_CLIP_X = `GNET_POLY_CLIP_X;         // 1 = polygon spans clipped to the drawing area
`else
localparam GNET_POLY_CLIP_X = 0;
`endif
`ifdef GNET_TEX_FETCH_DIR
localparam GNET_TEX_FETCH_DIR = `GNET_TEX_FETCH_DIR;   // fill rows follow the walk (docs/gpu_speed_sianniv.md): 0 off, 1/2/3
`else
localparam GNET_TEX_FETCH_DIR = 0;
`endif
`ifdef GNET_ZN2
localparam GNET_ZN2_BOARD = 1;   // ZN-2 board and G-NET FC PCB (rtl/gnet/zn2_board.vhd)
localparam GNET_RECT_FLIP = 1;   // CXD8654Q textured rectangle X/Y flip, E1 bits 12/13 (issue #6, gpu_rect.vhd)
`else
localparam GNET_ZN2_BOARD = 0;
localparam GNET_RECT_FLIP = 0;
`endif
// Fast clock edges per CPU clock cycle for the request strobes in sdram.sv
// and psx_top.vhd (docs/r1_cpu_domain_design.md). Selects logic only; the
// clocks come from GNET_CPU50: with it the CPU group runs on clk_cpu
// (50 MHz) and clk_cpu2x (100 MHz), a 2:1 pair, as in the release. Without
// GNET_CPU50 the emu PLL still makes clk_3x : clk_1x = 3:1, so
// GNET_CLK_RATIO2 alone (revision GNET_B1R2) checks synthesis and area
// only and does not run correctly, so that pairing stops elaboration.
`ifdef GNET_CLK_RATIO2
`ifndef GNET_CPU50
gnet_error_clk_ratio2_needs_gnet_cpu50 gnet_error_clk_ratio2();
`endif
localparam GNET_CLK_FAST_RATIO = 2;
`else
localparam GNET_CLK_FAST_RATIO = 3;
`endif
// G-NET: R1 option B: main SDRAM plain reads ready one fast edge earlier at 2:1
// (sdram.sv EARLY_READY; docs/r1_cpu_domain_design.md, throughput section)
`ifdef GNET_EARLY_READY
localparam GNET_EARLY_READY_P = 1;
`else
localparam GNET_EARLY_READY_P = 0;
`endif
// G-NET: R1 read overlap: a ZN-2 expansion read step issues its request when its
// read delay starts (memorymux ZN2_READ_OVERLAP; docs/r1_cpu_domain_design.md)
`ifdef GNET_READ_OVERLAP
localparam GNET_READ_OVERLAP_P = 1;
`else
localparam GNET_READ_OVERLAP_P = 0;
`endif
// G-NET: R1 main RAM load timing at 2:1 (docs/r1_cpu_domain_design.md,
// "Main RAM load timing at 2:1"), both off at 3:1. GNET_RAM_READ_NOWAIT: memorymux
// skips WAITFORRAMREAD for main RAM data reads (psx_top RAM_READ_NOWAIT; the
// CPU's back-to-back compensation is then skipped for RAM-RAM pairs).
// memorymux's back-to-back read window stays at upstream's 7 (psx_top
// RAM_LOAD_WINDOW). The alternative that rescaled it at 2:1 (8 with
// GNET_EARLY_READY, 9 without; macro GNET_RAM_B2B_WINDOW, set by no
// revision) is archived under the tag experiments-archive; the generic stays
// for tools/r1/mem_lat (mode w).
`ifdef GNET_RAM_READ_NOWAIT
localparam GNET_RAM_READ_NOWAIT_P = (GNET_CLK_FAST_RATIO == 2) ? 1 : 0;
`else
localparam GNET_RAM_READ_NOWAIT_P = 0;
`endif
`ifdef GNET_CARD_JOURNAL
localparam GNET_CARD_JOURNAL_P = 1;   // G-NET: zn2_cardmem journal read client (issue #9)
`else
localparam GNET_CARD_JOURNAL_P = 0;
`endif
localparam GNET_RAM_LOAD_WINDOW_P = 7;
// G-NET: R1, CPU group on clk_cpu/clk_cpu2x (needs GNET_CLK_RATIO2 and the LEAN trims)
`ifdef GNET_CPU50
localparam GNET_CPU_CLK_SPLIT = 1;
`else
localparam GNET_CPU_CLK_SPLIT = 0;
`endif
