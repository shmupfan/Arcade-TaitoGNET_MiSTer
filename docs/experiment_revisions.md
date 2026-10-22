# Experiment revisions (archived)

The Quartus revisions below were the experiments and stand-alone fits that
led to the release. They were removed from the main line on 2026-10-20
(refactor plan step 8, my decision 3) and are kept under the annotated
tag `experiments-archive` (commit f5fef8e), together with their
`tools/pc_build.sh` targets. Design docs still cite them by name; this table
says what each one was.

Kept on the main line: GNET_Z1FULLR (the release, alpha 3 and later; target z1fullr),
GNET_Z1FULLO (alpha 1; target z1fullo; kept in the dev tree for now), PSX and
PSX_DualSDRAM (upstream PSX_MiSTer; targets psx and psxsw), and the SDC files
the release reads, GNET_LEAN.sdc and GNET_CPU50_B1.sdc.

To build one again: `git checkout experiments-archive -- <files>` for its
.qsf (and .sdc, .srf, .qpf), and copy its target line from
`git show experiments-archive:tools/pc_build.sh`.

## Core revisions (project PSX)

| Revision | Target | What it tested | Other files |
|---|---|---|---|
| GNET_F0 | f0 | Upstream plus the console trims (no CD, pads, savestates, cheats), docs/f0_budget.md | .srf |
| GNET_F0_NOMDEC | f0m | F0 plus MDEC off | .srf |
| GNET_F0_LEAN | lean | F0 plus MDEC off, console OSD options fixed, framework YC and adaptive scaler off (R18) | .srf |
| GNET_M1_2MB | m1vram | F0_LEAN plus the ZN-2 2 MB VRAM GPU (GNET_VRAM_2MB) | .srf |
| GNET_B1 | b1 | M1_2MB plus the 18x18 GTE multipliers (GNET_GTE_NARROW_MUL=1), normal clocks | |
| GNET_B1S2, GNET_B1S3 | b1s2, b1s3 | B1 at fitter seeds 2 and 3 | |
| GNET_B1R2 | b1r2 | B1 plus GNET_CLK_RATIO2 at the old 3:1 clocks: synthesis and area only, the core does not run | |
| GNET_Z1 | z1 | B1 plus the ZN-2 board and FC glue, no sound, CPU on clk_1x | |
| GNET_CPU50_B1 | cpu50b1 | B1 with the CPU group on its own 50/100 MHz PLL, SDRAM 2:1, GTE_NARROW_MUL 3 (docs/r1_cpu_domain_design.md) | GNET_CPU50_B1.sdc is kept: the release reads it |
| GNET_Z1_CPU50 | z1cpu50, z1dbg | Z1 with the CPU group, zn2_board included, at 50/100 MHz | |
| GNET_Z1_ZOOM | z1zoom | Z1_CPU50 plus the Taito Zoom board with flash in SDRAM (macro GNET_ZOOM_SDRAM, rtl/gnet/zoom_sdram_link.vhd) | |
| GNET_Z1_DDR3 | z1ddr3 | Z1_CPU50 plus the DDR3 arbiter, rotation FIFO, Zoom port and flash mirror (docs/ddr3_arbiter.md) | |
| GNET_Z1SHELL | z1shell | Z1_CPU50 plus the release shell (GNET_SHELL, docs/m4_shell.md) | |
| GNET_Z1FULL | z1full | Z1SHELL plus the DDR3 arbiter and screen_rotate (GNET_DDR3_ARB, GNET_ROT_DDR) | |
| GNET_Z1FULLB | z1fullb | Z1FULL plus R1 option B (GNET_EARLY_READY) | |
| GNET_Z1FULLD | z1fulld | GNET_Z1FULLR plus the MRA DDR3 load path (GNET_DDR3_LOAD, issue #12, docs/i12_ddr3_load.md). From alpha 4 GNET_Z1FULLR sets the macro itself; archived on alpha5 (2026-10-20). Not in the tag: `git show alpha4b:GNET_Z1FULLD.qsf` (commit 8d71028) and the z1fulld line of `git show alpha4b:tools/pc_build.sh`; branch i12-ddr3load keeps both | that copy lacks rtl/gnet/gnet_sd_blank.sv (issue #11), which PSX.sv instantiates in GNET_SHELL builds: add the line before building it |
| GNET_Z1FULLO (own build dir) | z1fullos | The SPU falling-edge MLAB write fix (branch spu-voiceregs) built as Z1FULLO | revision kept, target removed (use SLOT) |
| GNET_F0_CPU50 | cpu50 | F0_LEAN plus 20 ns on CPU-side paths (R1 experiment) | GNET_CPU50.sdc, .srf |
| GNET_F0_CPU50B | cpu50b | LEAN with the CPU side at 50 MHz, GTE at 100 MHz | GNET_CPU50B.sdc, .srf |
| GNET_F0_CPU50C, C4, CS2 | cpu50c, cpu50c4, cpu50cs2 | CPU side 50 MHz, GTE 80 MHz; C4 with GTE_NARROW_MUL 2; CS2 at seed 2 | GNET_CPU50C.sdc, .srf |
| GNET_F0_CPU50D | cpu50d | CPU side 50 MHz, GTE 75 MHz | GNET_CPU50D.sdc, .srf |
| GNET_F0_CPU50E, E2, E3 | cpu50e, cpu50e2, cpu50e3 | As B with GTE_NARROW_MUL 1; E2 and E3 at seeds 2 and 3 | uses GNET_CPU50B.sdc |
| GNET_F0_CPU50E4, E4S2, E4S3 | cpu50e4, cpu50e4s2, cpu50e4s3 | E with GTE_NARROW_MUL 2, seeds 1 to 3 | uses GNET_CPU50B.sdc |
| GNET_F0_CPU50E5, E5S2, E5S3 | cpu50e5, cpu50e5s2, cpu50e5s3 | E with GTE_NARROW_MUL 3 (first version), seeds 1 to 3 | uses GNET_CPU50B.sdc |
| GNET_F0_CPU50E6, E6S2, E6S3 | cpu50e6, cpu50e6s2, cpu50e6s3 | E5 with the early request decode fixed (the GTE_NARROW_MUL 3 the release uses), seeds 1 to 3 | uses GNET_CPU50B.sdc |

The STA scripts for the CPU-rate experiments went with them:
tools/sta/cpu50_check.tcl (after a GNET_F0_CPU50 compile), cpu50b_check.tcl
and cpu50x_check.tcl (after a GNET_F0_CPU50B compile).
tools/sta/cpu50_xclk.tcl stays: it reproduces the R1 cross-clock figures.

## Stand-alone fits (own projects, all ports virtual pins)

| Project / revision | Target | What it measured | Files |
|---|---|---|---|
| GNET_CDC_FIT | cdcfit | rtl/gnet/cdc blocks: RAM inference, ALMs, first pass of rtl/gnet/cdc/cdc.sdc | .qpf, .qsf, .sdc, and its top rtl/gnet/cdc/cdc_syn_top.vhd |
| GNET_GLUE_FIT | gluefit | The G-NET glue (gnet_fc) alone, ALM count (M2) | .qpf, .qsf, .sdc |
| GNET_GLUE_SYN | gluesyn | gnet_fc synthesis only | .qpf, .qsf |
| MN10200_FIT | mn102 | The Zoom sound CPU alone at 33.8688 MHz (docs/mn10200_rtl.md) | .qpf, .qsf, .sdc |
| MN10200_FIT67 | mn102f67 | The same at 67.7376 MHz with PIPE 1 (docs/zoom_board_design.md 6.5) | .qsf, .sdc |
| ZSG2_FIT | zsg2 | The ZSG-2 alone (docs/zsg2_rtl.md) | .qpf, .qsf, .sdc |
| TMS57002_FIT | tms57 | The TMS57002 alone with its delay RAM (docs/tms57002_rtl.md) | .qpf, .qsf, .sdc |
| ZOOM_FIT | zoomfit | zoom_board alone (docs/zoom_board_design.md 11) | .qpf, .qsf, .sdc |
| ZOOM_FIT2X | zoomfit2x | zoom_board alone with split clocks, CLK_H 4 | .qsf, .sdc |

Also removed from pc_build.sh: the measurement targets fx1b and zn2, which
built reference/xelanotpu/ZN1-TaitoFX1B_MiSTer and ZN2-Capcom_MiSTer (not
tracked in this repository).
