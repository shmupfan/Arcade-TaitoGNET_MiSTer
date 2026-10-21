# Provenance

Where every part of this core comes from, what I changed in code I did not
write, and why. The licence position is in docs/licensing.md: the files I
wrote are GPL-2.0-or-later, the combined core and its bitstream are
GPL-3.0-or-later because some MiSTer framework files are.

## Upstream base: PSX_MiSTer

- Project: PSX_MiSTer by Robert Peip, MiSTer port and framework by Sorgelig
  and contributors, https://github.com/MiSTer-devel/PSX_MiSTer
- Base commit: cd17b5a (main, 2026-08-21, "CD: improve Pause timing
  accuracy with SPT model"), merged into this repository as the base on
  2026-10-04. Every difference between cd17b5a and this tree in the files
  below is mine.
- Licence: as PSX_MiSTer (LICENSE holds its GPLv2 text; file headers and
  docs/licensing.md give the per-file statements). I did not add licence
  claims to upstream files that have no header.
- sys/ (the MiSTer framework): unchanged from cd17b5a.
- Upstream files I did not modify are not listed; they are as in cd17b5a.

Commit hashes below are from my development repository, which is not
published: this repository carries the code in release commits instead of
that history. A hash identifies the change and its date; the appendix
lists every subject. The upstream base cd17b5a is in this repository's
history, so the diffs against it can be checked here.

## Upstream files I modified

Each of these files has a notice at the top (below the upstream header
where there is one) and a `G-NET:` comment on each change, except
mechanical substitutions that the notice names. `tools/upstream_marks.py
--all` lists any change without a marker (it applies the substitutions each
notice covers: PSX.sv's `GNET_OPT` wrappings, psx_top's clock split renames,
the GPU files' VRAM_Y_BITS widths); it finds no hunks that change blank
space only. Unless
stated, every new generic or parameter defaults to upstream's behaviour, so
a build that does not set it gets upstream's logic. Line counts are the
code and comment changes at the alpha 3 release (24235eb), before the
notices and markers were added.

| File | Lines added / removed | What changed | Why |
|---|---|---|---|
| PSX.sv | +1565 / -49 | Becomes the G-NET top level: GNET_* build switches (macro table in the SYSTEM section), arcade OSD and shell, loader, inputs, ZN-2 and Zoom wiring, CPU clocks, DDR3 arbiter and rotation, debug overlay; console OSD options fixed with `GNET_OPT` in GNET_LEAN builds | The core is a Taito G-NET core built on PSX_MiSTer; all switches off is meant to give upstream (revision PSX matched unmodified PSX_MiSTer's synthesis totals on 2026-10-04, docs/f0_budget.md 3.1, before most of these edits; not re-checked since) |
| rtl/psx_top.vhd | +1539 / -122 | 24 generics (trims, VRAM size, GTE, GPU read options, clock split, ZN-2 and Zoom boards, RAM timing); ZN-2 layer and Zoom board instances; CPU_CLK_SPLIT wiring through rtl/gnet/cpu_split; debug overlay capture registers; upstream signals renamed for the clock split (`clk_cpu`, `_c`, `_p`) | ZN-2 hardware, the 50 MHz CPU (R1), the board's sound and expansion bus |
| rtl/psx_mister.vhd | +158 / -4 | Passes the new generics and ports through | as psx_top |
| rtl/cpu.vhd | +17 / -3 | Debug overlay taps (PC, data address); B2B_RAM_COMP generic | debug overlay; main RAM load timing at 2:1 (issue #5) |
| rtl/memorymux.vhd | +213 / -16 | ZN2_MAP expansion bus decode; CPU clock split changes; ZN2_READ_OVERLAP; write address latched for posted writes; RAM_READ_NOWAIT and RAM_LOAD_WINDOW | ZN-2 expansion bus; R1 timing; issue #5 |
| rtl/dma.vhd | +8 / -2 | DMA_SPU_readStall / DMA_SPU_readReq (SPU channel reads wait for the clock crossing) | CPU on its own clock (CPU_CLK_SPLIT) |
| rtl/timer.vhd | +10 / -5 | sys_tick input (default '1' = upstream): 33.8688 MHz-equivalent ticks for the system clock sources | CPU on its own clock |
| rtl/savestates.vhd | +35 / -3 | CPU_FILL_EXT generic: the reset zero fill of scratchpad and RAM done by a CPU-side filler | CPU on its own clock (savestates.vhd is also the reset sequencer) |
| rtl/sdram.sv (GPL-3.0-or-later, its own header) | +90 / -11 | CLK_FAST_RATIO (3 = upstream, 2 = CPU domain); at 2:1 a cache line fill signals ready after its last word, and the CPU request strobes select the row address in the last mux level; EARLY_READY (default 0) | R1 at 2:1; issue #5 |
| rtl/gte.vhd, gte_mac0.vhd, gte_mac123.vhd, gte_UNRDivide.vhd, pGTE.vhd | +811 / -7 | GTE_NARROW_MUL (0 = upstream; 3, used by the release, runs the GTE at 100 MHz with the same results and step counts; 1 and 2 are earlier experiments) | GTE on the 100 MHz CPU clock (R1) |
| rtl/gpu.vhd | +135 / -49 | VRAM_Y_BITS (9 = upstream, 10 = 2 MB); GP1(10h) index 7 answers 2 with 2 MB VRAM; GPU_READ_INFL, TEX_FETCH_QW, TEX_FETCH_ROWS, TEX_MISS_DELAY passed to the pipeline; RECT_FLIP passed to gpu_rect | ZN-2 CXD8654Q GPU (2 MB VRAM); DDR3 read latency and calibration to the board (docs/gpu_read_infl.md) |
| rtl/gpu_pixelpipeline.vhd | +126 / -29 | VRAM_Y_BITS; texture cache fill per miss (TEX_FETCH_QW), extra rows (TEX_FETCH_ROWS), reads in flight, TEX_MISS_DELAY | as gpu.vhd |
| rtl/gpu_rect.vhd | +57 / -20 | VRAM_Y_BITS; RECT_FLIP: textured rectangle X/Y flip (E1 bits 12/13) | CXD8654Q behaviour (issue #6) |
| rtl/gpu_cpu2vram, gpu_fillVram, gpu_line, gpu_poly, gpu_videoout, gpu_vram2cpu, gpu_vram2vram (.vhd), pGPU.vhd | about +13 / -9 each | VRAM_Y_BITS width expressions; pGPU's vramRange widened | 2 MB VRAM |
| rtl/mdec.vhd | +39 / -9 | IDCT_REG_STAGE (0 = upstream; psx_top sets it to CPU_CLK_SPLIT): a register stage on the IDCT table reads (one clk2x more latency, same products in the same order) | MDEC timing on the 100 MHz CPU clock (issue #1 put the MDEC in the CPU group) |
| rtl/spu.vhd | +57 / -16 | MLAB_WR_NEGEDGE (0 = upstream; psx_top sets it to ZN2_BOARD): voice register, volume, record and envelope MLABs written on the falling edge of clk1x from rising-edge copies | Hold time on the MLAB write ports in the GNET_Z1FULLO fit (2026-10-07) |
| sim/system/src/tb/tb.vhd | +3 / -0 | CPU group clock ports tied to the PS1 clocks | upstream's system bench elaborates with the new ports |
| README.md, .gitignore | | Rewritten for this core; build outputs ignored | |

### Changes since alpha 3

Line counts are code and comment changes from 24235eb to 8d71028 (the
alpha 4 build with the area savings), before this standard was applied to
them. Each change carries a `G-NET:`
marker and is named in its file's notice.

| File | Lines added / removed | What changed | Why |
|---|---|---|---|
| PSX.sv | +179 / -3 | GNET_DDR3_LOAD: an index 3 download with a length in ioctl_addr is a DDR3 load; gnet_ddr3_flcopy copies the flash area to SDRAM over the download write path, holding ioctl_wait; gnet_ddr3_gmux puts it on the DDR3 arbiter's glue port behind the flash mirror. gnet_sd_blank between video_aspect and arcade_video. GNET_NO_DBG and GNET_NO_DCACHE (debug overlay, its capture block, the turbo data cache out; the Debug overlay OSD item hidden) | Issue #12 (faster loading, docs/i12_ddr3_load.md); issue #11 (scandoubler lost vsync, docs/i11_scandoubler.md); area for timing closure (docs/area.md) |
| rtl/psx_top.vhd | +16 / -3 | Generics HAS_DCACHE (passed to cpu) and ZN2_DBG (0 leaves out the zn_dbg_regs capture block, word reads 0), both default 1 | area (docs/area.md) |
| rtl/psx_mister.vhd | +4 / -0 | Passes HAS_DCACHE and ZN2_DBG through | as psx_top |
| rtl/cpu.vhd | +18 / -1 | Generic HAS_DCACHE (default 1 = upstream): 0 does not build the datacache instance, hit and data read 0 | area: with TURBO_CACHE tied to 0 (GNET_LEAN) the cache's data is never used, 64 M10K |
| rtl/gpu_poly.vhd | +8 / -0 | The polygon watchdog (timeout) restarts on every pixel step | Issue #10: a long textured quad on DDR3 VRAM took more than 1,048,575 clk2x and was cut off (docs/i10_triangle.md) |

The gpu_poly.vhd change applies to every build, revision PSX included,
like mdec.vhd and spu.vhd did at alpha 3: it is not behind a generic. It
only lets a primitive that keeps stepping pixels run past the limit; a
stall with no pixel step still fires the watchdog. Putting it behind a
generic whose default is upstream is a planned step. New own files in alpha 4:
rtl/gnet/gnet_sd_blank.sv, gnet_ddr3_flcopy.sv, gnet_ddr3_gmux.sv (from
dev commit 126e964) and GNET_HDMI_FITOC.sdc (fix F1,
docs/hdmi_timing.md); rtl/gnet/zn2_io.vhd and zn2_board.vhd gained
ZOOM_STUB (the unreachable Zoom mailbox stub is not built with ZOOM = 1).

At the alpha 3 release two changes broke the rule that new behaviour sits
behind a generic whose default is upstream: mdec.vhd's register stage and
spu.vhd's falling-edge writes applied to every build. Since the refactor
of 2026-10-20 they sit behind IDCT_REG_STAGE and
MLAB_WR_NEGEDGE, both 0 = upstream, which psx_top sets from CPU_CLK_SPLIT
and ZN2_BOARD, so every G-NET build keeps them and revision PSX is upstream
again. The same refactor reverted the whitespace-only edits to upstream
lines in memorymux.vhd, cpu.vhd and PSX.sv. One known slip outside the
release configuration:
gpu.vhd tests `fifoOut_Dout(85)` where it should test `F_SRC` (the bit moves
to 86 with 2 MB VRAM); the release cannot reach it because GNET_LEAN ties
the 480p interlace hack off. Its fix is also a planned step.

### Later changes in this release (after 8d71028)

Line counts are the sums of the commits listed in the appendix under
"After 8d71028".

| File | Lines added / removed | What changed | Why |
|---|---|---|---|
| rtl/gpu.vhd | +24 / -6 | reqVRAMwrap (the second burst of a VRAM read that wraps at X = 1024) is computed one clk2x after the request, from registered X and rounded size, instead of from the live request lines. Nothing reads it in that first cycle. Not behind a generic: it applies to every build, like the gpu_poly.vhd change | Timing closure: every clk_2x setup failure of the 8d71028 fits ended at reqVRAMwrap, through the DDR3 arbiter's combinational BUSY (docs/area_timing.md 9). The sim/gpuinfl bench with 7 wrapping VRAM to VRAM copies gives the same VRAM dump before and after |
| PSX.sv | +70 / -17 | GNET_DDR3_LOAD: the flash copier's integrity checks wired up (its read-back reads take the download path to channel 3); the flash mirror ignores channel 3 writes while the copier runs (flc_busy through a cdc_sync into clk_cpu); in builds with the debug overlay, its DR row shows the copier's flags and the sum of the words it read | Issue #12: the first copier stopped with ERROR C094 on hardware (docs/i12_ddr3_load.md 13) |

Own files changed or added: rtl/gnet/gnet_ddr3_flcopy.sv checks each copy
(sums of the words read from DDR3, of an SDRAM read-back and of a second
DDR3 read), copies again up to 3 times if a check fails, bounds its waits,
and reads its buffer at least one clk1x plus one clk2x period after the
write (the read-during-write window of the dual-clock M10K,
docs/i12_ddr3_load.md 13.7). GNET_SPURAM_HOLD.sdc (new, read by
GNET_Z1FULLR.qsf) removes the hold check on the savestate engine's SPU RAM
read capture, which no build without savestates can reach
(docs/area_timing.md 2).

### Card save, high score save and output level

Line counts are code and comment changes from 1c93c21 to 167276d (the
release RTL), including the merge b6dd7c2 that joined the two saves. Both
features sit behind their own macros (GNET_CARD_JOURNAL, GNET_HISCORE) and
generic (CARD_JOURNAL, default 0), so a build that does not set them gets
the previous logic; GNET_Z1FULLR sets both.

| File | Lines added / removed | What changed | Why |
|---|---|---|---|
| PSX.sv | +232 / -1 | GNET_CARD_JOURNAL: gnet_card_journal instance; index 6 is the EEPROM in its first 2 KB and the card hunk journal after it (upload mux, ioctl_wait term, upload request on OSD open). GNET_HISCORE: gnet_hiscore instance (MRA index 8 configuration, dump in the index 6 file's padding at 0xA00), its game RAM port on the download side of channel 3, its pause term and the pause crossing for cdc.sdc; build checks that stop a GNET_HISCORE build without GNET_CPU50, GNET_LEAN, GNET_SHELL and GNET_ZN2, and a GNET_CARD_JOURNAL build without GNET_ZN2 | Issue #9 (game settings on the PC card were lost, docs/i9_nvram.md); high score save (docs/hiscore.md) |
| rtl/psx_top.vhd | +37 / -2 | Generic CARD_JOURNAL (default 0): zn2_board's card write events (zn_cj_tog, zn_cj_hunk) out, and a line read client on zn2_cardmem (zn_cj_rd_*) for the journal; tied off when the ZN-2 layer is not built | Issue #9 |
| rtl/psx_mister.vhd | +17 / -2 | Passes CARD_JOURNAL and the zn_cj_* ports through | as psx_top |

Own files changed or added: rtl/gnet/gnet_card_journal.sv and
rtl/gnet/gnet_hiscore.sv (new); rtl/gnet/zn2_board.vhd reports each card
sector write and rtl/gnet/zn2_cardmem.vhd gained the journal's read port
(CARD_JOURNAL generic); rtl/zoom/zoom_mix.sv has OUT_SHIFT (default 15),
which doubles the whole mix (+6.02 dB) because with the MAME gains alone
the core played about 7 to 17 dB under the mister-core reference level in
full-system simulation (its header gives the measurement); 16 is the MAME
scale. rtl/gnet/hiscore.v is derived from Hiscores_MiSTer (GPL-3.0-or-later,
"Files derived from other projects" below); it is the first file from
another project outside the MiSTer framework that is GPL-3.0-or-later, so
the combined core and its RBF stay GPL-3.0-or-later as stated at the top.
Benches: sim/i9 and sim/hiscore.

## Checking these claims

- `python3 tools/upstream_marks.py --all`: every change in an upstream file
  is marked or covered by its notice.
- `python3 tools/comment_only_check.py --base <commit> --qsf
  GNET_Z1FULLR.qsf`: proves that a later edit changed comments only.
- `git diff cd17b5a -- <file>` in this repository shows each change in
  full against the upstream base.

## Files derived from other projects

| File | Derived from | Changes | Licence |
|---|---|---|---|
| rtl/gnet/gnet_arcade_video.sv | sys/arcade_video.v (Sorgelig, MiSTer framework, as in PSX_MiSTer cd17b5a) | VSync passed on every dot when not scandoubling, so the 480i half-line field offset reaches direct video and 15 kHz analog (issue #3); details in its header | GPL-2.0-or-later, as the original |
| rtl/gnet/hiscore.v | hiscore.v of Hiscores_MiSTer (Alan Steremberg, Jim Gregory), https://github.com/JimmyStones/Hiscores_MiSTer master 31789f3 (2021-10-09), version 0014 | line endings CRLF to LF; a clock enable on the state machine block and the change mask size as a parameter (HS_MASKBITS, default 256 as upstream), both marked G-NET:; used by rtl/gnet/gnet_hiscore.sv (GNET_HISCORE, docs/hiscore.md) | GPL-3.0-or-later, as the original |

## Files I wrote

Everything under rtl/gnet and rtl/zoom except the files above: own
implementations for this core, no code copied from other projects. Each
file's header gives its origin, licence (GPL-2.0-or-later) and, where it
models board behaviour, the evidence it follows (MAME 0.288 source files
with line numbers, datasheets and manuals with pages, board evidence). The
G-NET build revisions (GNET_*.qsf and their .sdc), tools/, docs/ and sim/
are mine as well, except PSX_MiSTer's own benches (sim/cd, gpu, gte, mdec,
pad, spu and system, as in cd17b5a apart from sim/system/src/tb/tb.vhd
above; the new files in sim/mdec are mine). The two ROM images
rtl/zoom/mn10200_form.hex and mn10200_ctl.hex are generated by
tools/mn102/mn102_rom.py.

XelaNotPu's ZN-1 and ZN-2 cores were used as a reference only (build size
measurements in docs/f0_budget.md 2); no code was copied. ppriest's TMS57002
was not used (docs/licensing.md).

## Reference material (not part of the build, not in this repository)

- MAME 0.288 source files, unmodified, which I read alongside the RTL:
  BSD-3-Clause per their headers except pccard.cpp and pccard.h
  (GPL-2.0-or-later). They are not copied here;
  [docs/mame_sources.md](docs/mame_sources.md) links each one at the exact
  version, with its md5.
- MAME commit 61c7940 zsg2.cpp and zsg2.h, the ZSG-2 fix the Zoom model
  follows where it differs from 0.288; also linked in docs/mame_sources.md.

## Appendix: commits per modified upstream file

Generated in my development repository with `git log --no-merges
--format='%h %ad %s' --date=short cd17b5a..24235eb -- <file>` (24235eb is
the alpha 3 release RTL). The alpha 4 commits (24235eb..8d71028) are
listed after them, under "Alpha 4", and the later ones under "After
8d71028".

### PSX.sv

- 771b9fe 2026-10-15 TEX_MISS_DELAY: clk2x wait added to each texture cache fill (default 0 = previous logic), GNET_TEX_MISS_DELAY macro through PSX.sv, psx_mister, psx_top and gpu; GNET_Z1FULLR calibrated to D = 8 (Ray Crisis demo replay: board 1.078 lies 0.41 of the way from prefetch 1.045 to upstream 1.126; docs/gpu_read_infl.md 10)
- c4f13c6 2026-10-06 GNET_TEX_FETCH_QW, GNET_TEX_FETCH_ROWS, GNET_GPU_READ_INFL macros through PSX.sv, psx_mister and psx_top to the GPU (defaults upstream)
- 988d431 2026-10-15 Go By RC: buttons 1 and 2 give full accelerate (trigger FFh) and full brake (00h)
- fff5a90 2026-10-14 Go By RC: trigger rests at 80h as MAME, analog stick beats D-pad bits (issue #4)
- 9220498 2026-10-14 Mahjong sets: Select + L = Service, Select + R = Test on the pad
- 08bee47 2026-10-14 Shell OSD: Video, Audio, Pause and Advanced pages
- 60652e5 2026-10-14 Shell: arcade-core pause options and an OSD Service Menu toggle
- 1c8a8bd 2026-10-14 GPU: textured rectangle X/Y flip for G-NET (issue #6)
- bf5293f 2026-10-14 Dash button for Chaos Heat (issue #7)
- 864cc5e 2026-10-14 R1 main RAM load timing at 2:1 (issue #5): memorymux RAM_READ_NOWAIT and RAM_LOAD_WINDOW, cpu B2B_RAM_COMP, PSX.sv macros GNET_RAM_READ_NOWAIT and GNET_RAM_B2B_WINDOW (all default off)
- 5d3dea5 2026-10-14 480i keeps its half-line field offset on direct video and 15 kHz analog (issue #3)
- 732641e 2026-10-14 Coins: one 100 ms pulse per press, and the coin lockouts as MAME (issue #1)
- 223366f 2026-10-14 Mahjong panel on pad 1 for Usagi and Mahjong Oh (issue #2)
- 70a6690 2026-10-14 GNET shell: Pause Button OSD option (O[120]), Off by default
- d965cae 2026-10-06 Special controls: mahjong panel (mahjngoh, usagi) and RC wheel and trigger (gobyrc, rcdego), selected by the game configuration byte bits 3:2
- 0fd0608 2026-10-06 No Zoom board per game: game-config byte (ioctl index 7) bit 1 holds the Zoom MN10200 in reset regardless of control bit 4, as MAME init_nozoom (otenamih, otenamhf, zokuoten, zokuotena, zooo, sianniv, 2011 conversions); psx_mister/psx_top port zn_nozoom, default 0 (existing MRAs unchanged)
- ee3c8c7 2026-10-06 Comments: first person in PSX.sv and gnet_crt_pos.sv; tms57002.sv cites MAME's source path at tag mame0288 instead of the local reference copy
- ca79590 2026-10-06 Revert SFX Level default 0.7 (dbede4b): back to MAME's 0.3 default
- dbede4b 2026-10-06 SFX Level default 0.7, estimated from a real Psyvariar Revision board (0.3 MAME kept as an option)
- aff128c 2026-10-06 SFX Level OSD option: PS1 SPU gain in zoom_mix (0.3 MAME default, 0.45, 0.6, 0.9, 1.2, 1.5)
- 8701d1f 2026-10-06 Read overlap prototype: memorymux ZN2_READ_OVERLAP (default 0) issues a ZN-2 read step's request as its delay starts
- 96f5475 2026-10-06 Option B prototype: sdram.sv EARLY_READY (default 0) cuts a 2:1 RAM read by one CPU cycle
- 4621404 2026-10-06 Rotation: screen_rotate fed the pre-scandoubler video (rot_gamma); sim/rotfx bench
- 3c993c0 2026-10-05 Silent pause for the Zoom mix; DDR3-path Zoom bench (sim/zoomddr3) and tb_zoomlink mbx.log
- 5f72e72 2026-10-05 PSX.sv: shell rotation wires declared before the FB_* mux
- 72dccbc 2026-10-05 Loader back-pressure: zn2_cdc p_ld_busy -> psx_top zn_ld_busy -> PSX.sv ioctl_wait
- c07cee9 2026-10-05 Zoom integration: SDRAM path exclusive with GNET_DDR3_ARB, integration bench with a MAME replay, Zoom test MRAs
- b41a76d 2026-10-05 Shell: EEPROM NVRAM save, CRT H/V position, scandoubler Fx (arcade_video), core README
- 277f5de 2026-10-05 GNET_DDR3_ARB: arbiter and mirror status on named PSX.sv wires for the debug overlay (gnet_ddr3_rot_ovf, gnet_ddr3_rot_hiwater, gnet_ddr3_own_ovf, gnet_ddr3_mirror_ovf)
- 370499a 2026-10-05 M4 shell: revision GNET_Z1SHELL (GNET_SHELL), target z1shell (not fitted)
- c6aab13 2026-10-05 GNET_DDR3_ARB: DDR3 arbiter in front of DDRAM in PSX.sv (core behind it), screen_rotate into the rotation FIFO (gnet_rot_en/gnet_rot_ccw), Zoom m_* port through gnet_ddr3_zport (clk_1x, reset drop), channel 3 flash-area mirror into DDR3 (gnet_ddr3_mirror, zn2_ch3_arb stall), CDC names for cdc.sdc, revision GNET_Z1_DDR3 and pc_build target z1ddr3, Zoom adapter and mirror benches, tools/lint_psx.py
- 34a221b 2026-10-05 Taito Zoom board in the G-NET core: zn2_board host port, zoom_cdc crossings, zoom_m_* line port, SPU mix, revision GNET_Z1_ZOOM
- 41d4fb3 2026-10-05 Hardware debug overlay for G-NET builds (OSD status bit 101, default Off)
- 43c9570 2026-10-05 ZN-2 layer in the CPU group: zn2_board on clk_cpu (CLK_HZ 50 MHz) with CPU_CLK_SPLIT = 1
- b32532c 2026-10-05 R1 GNET_CPU50: pll_cpu reference over the global clock network (fit 1: no free fPLL reachable from FPGA_CLK2_50's dedicated path)
- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50
- 338def1 2026-10-05 G-NET silent test integration: psx_top ZN2_BOARD, zn2_board, DDR3 card client, PSX.sv GNET_ZN2, GNET_Z1
- 67a3f97 2026-10-05 R1: CLK_FAST_RATIO generic for the clk3x request strobes
- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts
- e0bed57 2026-10-05 R1: GTE_NARROW_MUL=2 (parallel adders, select after) and revision CPU50E4
- 3d186b7 2026-10-05 R1: experiment C result; GTE_NARROW_MUL option (18x18 multiply or shift) and CPU50E revision
- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)
- 3a8d3d3 2026-10-04 LEAN: fixed 53.693175 MHz video PLL replaces reconfigurable pll2 + pll_cfg (no PAL/fast-forward on G-NET)
- 26a9af8 2026-10-04 F0: GNET_F0_LEAN revision (console OSD options fixed via GNET_OPT, YC and adaptive framework paths off)
- 475d621 2026-10-04 F0: trim switches (CD, pads/memcards, savestate requests, cheats, MDEC), trial-fit revisions, build and fit-report tools, licensing note

### rtl/psx_top.vhd

- 771b9fe 2026-10-15 TEX_MISS_DELAY: clk2x wait added to each texture cache fill (default 0 = previous logic), GNET_TEX_MISS_DELAY macro through PSX.sv, psx_mister, psx_top and gpu; GNET_Z1FULLR calibrated to D = 8 (Ray Crisis demo replay: board 1.078 lies 0.41 of the way from prefetch 1.045 to upstream 1.126; docs/gpu_read_infl.md 10)
- c4f13c6 2026-10-06 GNET_TEX_FETCH_QW, GNET_TEX_FETCH_ROWS, GNET_GPU_READ_INFL macros through PSX.sv, psx_mister and psx_top to the GPU (defaults upstream)
- aa7e055 2026-10-14 MDEC in the CPU group and kept in GNET_Z1FULLO: sianniv Start hang (issue #1)
- 1c8a8bd 2026-10-14 GPU: textured rectangle X/Y flip for G-NET (issue #6)
- 864cc5e 2026-10-14 R1 main RAM load timing at 2:1 (issue #5): memorymux RAM_READ_NOWAIT and RAM_LOAD_WINDOW, cpu B2B_RAM_COMP, PSX.sv macros GNET_RAM_READ_NOWAIT and GNET_RAM_B2B_WINDOW (all default off)
- d965cae 2026-10-06 Special controls: mahjong panel (mahjngoh, usagi) and RC wheel and trigger (gobyrc, rcdego), selected by the game configuration byte bits 3:2
- 0fd0608 2026-10-06 No Zoom board per game: game-config byte (ioctl index 7) bit 1 holds the Zoom MN10200 in reset regardless of control bit 4, as MAME init_nozoom (otenamih, otenamhf, zokuoten, zokuotena, zooo, sianniv, 2011 conversions); psx_mister/psx_top port zn_nozoom, default 0 (existing MRAs unchanged)
- 8701d1f 2026-10-06 Read overlap prototype: memorymux ZN2_READ_OVERLAP (default 0) issues a ZN-2 read step's request as its delay starts
- 72dccbc 2026-10-05 Loader back-pressure: zn2_cdc p_ld_busy -> psx_top zn_ld_busy -> PSX.sv ioctl_wait
- b41a76d 2026-10-05 Shell: EEPROM NVRAM save, CRT H/V position, scandoubler Fx (arcade_video), core README
- 34a221b 2026-10-05 Taito Zoom board in the G-NET core: zn2_board host port, zoom_cdc crossings, zoom_m_* line port, SPU mix, revision GNET_Z1_ZOOM
- 41d4fb3 2026-10-05 Hardware debug overlay for G-NET builds (OSD status bit 101, default Off)
- 43c9570 2026-10-05 ZN-2 layer in the CPU group: zn2_board on clk_cpu (CLK_HZ 50 MHz) with CPU_CLK_SPLIT = 1
- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50
- 935647c 2026-10-05 zn2_layer_design: RAM window after MAME aab5dcadb, flash S5 timing, Shikigami in-play select
- 338def1 2026-10-05 G-NET silent test integration: psx_top ZN2_BOARD, zn2_board, DDR3 card client, PSX.sv GNET_ZN2, GNET_Z1
- 67a3f97 2026-10-05 R1: CLK_FAST_RATIO generic for the clk3x request strobes
- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts
- 3d186b7 2026-10-05 R1: experiment C result; GTE_NARROW_MUL option (18x18 multiply or shift) and CPU50E revision
- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)
- bcdec20 2026-10-04 HAS_SAVESTATES=0: mask savestate strobes for types 0-11 and all reads, so per-module saved-state registers reduce to their reset constants
- 475d621 2026-10-04 F0: trim switches (CD, pads/memcards, savestate requests, cheats, MDEC), trial-fit revisions, build and fit-report tools, licensing note

### rtl/psx_mister.vhd

- 771b9fe 2026-10-15 TEX_MISS_DELAY: clk2x wait added to each texture cache fill (default 0 = previous logic), GNET_TEX_MISS_DELAY macro through PSX.sv, psx_mister, psx_top and gpu; GNET_Z1FULLR calibrated to D = 8 (Ray Crisis demo replay: board 1.078 lies 0.41 of the way from prefetch 1.045 to upstream 1.126; docs/gpu_read_infl.md 10)
- c4f13c6 2026-10-06 GNET_TEX_FETCH_QW, GNET_TEX_FETCH_ROWS, GNET_GPU_READ_INFL macros through PSX.sv, psx_mister and psx_top to the GPU (defaults upstream)
- 1c8a8bd 2026-10-14 GPU: textured rectangle X/Y flip for G-NET (issue #6)
- 864cc5e 2026-10-14 R1 main RAM load timing at 2:1 (issue #5): memorymux RAM_READ_NOWAIT and RAM_LOAD_WINDOW, cpu B2B_RAM_COMP, PSX.sv macros GNET_RAM_READ_NOWAIT and GNET_RAM_B2B_WINDOW (all default off)
- d965cae 2026-10-06 Special controls: mahjong panel (mahjngoh, usagi) and RC wheel and trigger (gobyrc, rcdego), selected by the game configuration byte bits 3:2
- 0fd0608 2026-10-06 No Zoom board per game: game-config byte (ioctl index 7) bit 1 holds the Zoom MN10200 in reset regardless of control bit 4, as MAME init_nozoom (otenamih, otenamhf, zokuoten, zokuotena, zooo, sianniv, 2011 conversions); psx_mister/psx_top port zn_nozoom, default 0 (existing MRAs unchanged)
- 8701d1f 2026-10-06 Read overlap prototype: memorymux ZN2_READ_OVERLAP (default 0) issues a ZN-2 read step's request as its delay starts
- 72dccbc 2026-10-05 Loader back-pressure: zn2_cdc p_ld_busy -> psx_top zn_ld_busy -> PSX.sv ioctl_wait
- b41a76d 2026-10-05 Shell: EEPROM NVRAM save, CRT H/V position, scandoubler Fx (arcade_video), core README
- 34a221b 2026-10-05 Taito Zoom board in the G-NET core: zn2_board host port, zoom_cdc crossings, zoom_m_* line port, SPU mix, revision GNET_Z1_ZOOM
- 41d4fb3 2026-10-05 Hardware debug overlay for G-NET builds (OSD status bit 101, default Off)
- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50
- 338def1 2026-10-05 G-NET silent test integration: psx_top ZN2_BOARD, zn2_board, DDR3 card client, PSX.sv GNET_ZN2, GNET_Z1
- 67a3f97 2026-10-05 R1: CLK_FAST_RATIO generic for the clk3x request strobes
- 3d186b7 2026-10-05 R1: experiment C result; GTE_NARROW_MUL option (18x18 multiply or shift) and CPU50E revision
- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)
- 475d621 2026-10-04 F0: trim switches (CD, pads/memcards, savestate requests, cheats, MDEC), trial-fit revisions, build and fit-report tools, licensing note

### rtl/cpu.vhd

- 864cc5e 2026-10-14 R1 main RAM load timing at 2:1 (issue #5): memorymux RAM_READ_NOWAIT and RAM_LOAD_WINDOW, cpu B2B_RAM_COMP, PSX.sv macros GNET_RAM_READ_NOWAIT and GNET_RAM_B2B_WINDOW (all default off)
- 41d4fb3 2026-10-05 Hardware debug overlay for G-NET builds (OSD status bit 101, default Off)

### rtl/memorymux.vhd

- 864cc5e 2026-10-14 R1 main RAM load timing at 2:1 (issue #5): memorymux RAM_READ_NOWAIT and RAM_LOAD_WINDOW, cpu B2B_RAM_COMP, PSX.sv macros GNET_RAM_READ_NOWAIT and GNET_RAM_B2B_WINDOW (all default off)
- 62c7cce 2026-10-06 memorymux ZN-2: write steps use the word address latched in EXT_IDLE (posted-write address fix)
- 8701d1f 2026-10-06 Read overlap prototype: memorymux ZN2_READ_OVERLAP (default 0) issues a ZN-2 read step's request as its delay starts
- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50
- fbba55b 2026-10-05 memorymux: ZN2_MAP generic (default 0 = upstream) for the ZN-2 expansion bus

### rtl/dma.vhd

- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50

### rtl/timer.vhd

- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50

### rtl/savestates.vhd

- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50

### rtl/sdram.sv

- 6fe551b 2026-10-15 sdram EARLY_READY: ch1_dout32 as a clk_cpu2x register loaded on clk_cpu-aligned edges, multicycle 2 into clk_cpu
- 87d11e7 2026-10-06 sdram.sv 2:1: CPU request strobes select the row address in the last mux level (z1fullb clk_cpu2x setup fix)
- 96f5475 2026-10-06 Option B prototype: sdram.sv EARLY_READY (default 0) cuts a 2:1 RAM read by one CPU cycle
- 6cb9b78 2026-10-05 sdram.sv: at CLK_FAST_RATIO = 2 a cache line fill signals ready after its last word is written
- 67a3f97 2026-10-05 R1: CLK_FAST_RATIO generic for the clk3x request strobes

### rtl/gte.vhd

- 83807dd 2026-10-05 R1: GTE_NARROW_MUL=3 early decode without inferred divider (E6)
- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts
- 3d186b7 2026-10-05 R1: experiment C result; GTE_NARROW_MUL option (18x18 multiply or shift) and CPU50E revision

### rtl/gte_mac0.vhd

- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts

### rtl/gte_mac123.vhd

- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts
- e0bed57 2026-10-05 R1: GTE_NARROW_MUL=2 (parallel adders, select after) and revision CPU50E4
- 3d186b7 2026-10-05 R1: experiment C result; GTE_NARROW_MUL option (18x18 multiply or shift) and CPU50E revision

### rtl/gte_UNRDivide.vhd

- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts

### rtl/pGTE.vhd

- 92ae3a6 2026-10-05 R1: GTE_NARROW_MUL=3, GTE at 100 MHz with unchanged results and step counts

### rtl/gpu.vhd

- 771b9fe 2026-10-15 TEX_MISS_DELAY: clk2x wait added to each texture cache fill (default 0 = previous logic), GNET_TEX_MISS_DELAY macro through PSX.sv, psx_mister, psx_top and gpu; GNET_Z1FULLR calibrated to D = 8 (Ray Crisis demo replay: board 1.078 lies 0.41 of the way from prefetch 1.045 to upstream 1.126; docs/gpu_read_infl.md 10)
- 864ae50 2026-10-06 GPU read latency on DDR3: per-class attribution (texture misses are the cost), texture cache group fill (TEX_FETCH_QW), multi-row fills with reads in flight (TEX_FETCH_ROWS, GPU_READ_INFL), posted writes, all generics defaulting to upstream; pipelined VRAM model in the replay bench (docs/gpu_read_infl.md)
- 1c8a8bd 2026-10-14 GPU: textured rectangle X/Y flip for G-NET (issue #6)
- e775367 2026-10-05 GPU: GP1(10h) index 7 answers 2 in ZN-2 mode (VRAM_Y_BITS = 10), as the CXD8654Q in MAME
- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_pixelpipeline.vhd

- 771b9fe 2026-10-15 TEX_MISS_DELAY: clk2x wait added to each texture cache fill (default 0 = previous logic), GNET_TEX_MISS_DELAY macro through PSX.sv, psx_mister, psx_top and gpu; GNET_Z1FULLR calibrated to D = 8 (Ray Crisis demo replay: board 1.078 lies 0.41 of the way from prefetch 1.045 to upstream 1.126; docs/gpu_read_infl.md 10)
- 864ae50 2026-10-06 GPU read latency on DDR3: per-class attribution (texture misses are the cost), texture cache group fill (TEX_FETCH_QW), multi-row fills with reads in flight (TEX_FETCH_ROWS, GPU_READ_INFL), posted writes, all generics defaulting to upstream; pipelined VRAM model in the replay bench (docs/gpu_read_infl.md)
- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_rect.vhd

- 1c8a8bd 2026-10-14 GPU: textured rectangle X/Y flip for G-NET (issue #6)
- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_cpu2vram.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_fillVram.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_line.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_poly.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_videoout.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_vram2cpu.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/gpu_vram2vram.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/pGPU.vhd

- c71a991 2026-10-04 M1 (WIP, verifying): ZN-2 2 MB VRAM GPU behind generic VRAM_Y_BITS (9 = PS1 default, 10 = CXD8654Q)

### rtl/mdec.vhd

- 2d6bf48 2026-10-14 MDEC: register the IDCT table reads before the multiply (clk_cpu2x timing)

### rtl/spu.vhd

- e1fac28 2026-10-07 spu: the same falling-edge write for the VOICEVOLUMES, VOICERECORDS and envelope-counter MLABs (VOICEVOLUMES' write address came within 0.064 ns of clk_1x hold in the seed-2 fit); lockstep 2 seeds x 3M clk1x against upstream: no output difference. Note: a one-clock-late write into these three RAMs is not visible at the outputs either (they are not read in the clock after a write), so for them the equivalence rests on the timing: each word is first sampled at the same rising edge as before
- dd1ea06 2026-10-07 spu: voice register MLABs written on the falling edge of clk1x from a rising-edge copy of RamVoice_write/dataA/addrA (half a clk1x period of hold margin; the 2026-10-07 GNET_Z1FULLO seed-1 fit missed clk_1x hold by 0.060 ns on RamVoice_addrA into the MLAB write address); the word is still first sampled at the same rising edge. NVC lockstep against the upstream SPU (random register writes and immediate read-backs, sound RAM, CD input, resets), 2 seeds x 3M clk1x: no output difference (a one-clock-late write is caught at clock 129)

### sim/system/src/tb/tb.vhd

- f0cd555 2026-10-05 R1 steps 4 and 5: CPU group on its own 50/100 MHz clocks behind CPU_CLK_SPLIT / GNET_CPU50

### Alpha 4

From `git log --no-merges --format='%h %ad %s' --date=short
24235eb..8d71028 -- <file>`.

- PSX.sv
  - db78699 2026-10-20 Area: GNET_NO_DBG, GNET_NO_DCACHE, zn2_io ZOOM_STUB; GNET_Z1FULLR sets both macros
  - 1f6d3dc 2026-10-20 Scandoubler Fx: hblank on every line for the scandoubler (issue #11)
  - f9d8e2d 2026-10-20 Issue #12: MRA DDR3 load path behind GNET_DDR3_LOAD (revision GNET_Z1FULLD, pc_build target z1fulld)
- rtl/psx_top.vhd, rtl/psx_mister.vhd, rtl/cpu.vhd
  - db78699 2026-10-20 Area: GNET_NO_DBG, GNET_NO_DCACHE, zn2_io ZOOM_STUB; GNET_Z1FULLR sets both macros
- rtl/gpu_poly.vhd
  - 53c95d2 2026-10-20 gpu_poly: watchdog counts cycles without a pixel step (issue #10)

### After 8d71028

The refactor's commits that change comments only (notices and `G-NET:`
markers) are not listed.

- PSX.sv
  - 9856c09 2026-10-21 gnet_ddr3_flcopy: buffer read margin, flash mirror off during the copy, up to 3 tries (hardware d13: DR 053E C8A7, two DDR3 reads disagreed)
  - a145fe7 2026-10-20 gnet_ddr3_flcopy: bounded waits and single-burst DDR3 reads (hardware: Main never left a load with the integrity passes)
  - daa69be 2026-10-20 Issue #12 hardware result (ERROR C094 with the flash DDR3 load): flash copier integrity passes and overlay readout
  - 7f730c5 2026-10-20 Upstream files: revert the whitespace-only edits to upstream lines (memorymux.vhd 9 lines, cpu.vhd 1, PSX.sv one blank line)
  - 6bd6952 2026-10-20 PSX.sv: remove the experiment-only macros GNET_ZOOM_SDRAM (and the derived GNET_ZOOM_SDRAM_PATH), GNET_RAM_B2B_WINDOW and GNET_NO_MDEC; comments that named them point at the archive
- rtl/psx_top.vhd
  - 55d6e91 2026-10-20 mdec.vhd, spu.vhd: the two unconditional upstream changes behind generics (IDCT_REG_STAGE, MLAB_WR_NEGEDGE), 0 = upstream, set by psx_top from CPU_CLK_SPLIT and ZN2_BOARD
  - 6bd6952 2026-10-20 PSX.sv: remove the experiment-only macros GNET_ZOOM_SDRAM (and the derived GNET_ZOOM_SDRAM_PATH), GNET_RAM_B2B_WINDOW and GNET_NO_MDEC; comments that named them point at the archive
- rtl/cpu.vhd, rtl/memorymux.vhd
  - 7f730c5 2026-10-20 Upstream files: revert the whitespace-only edits to upstream lines (memorymux.vhd 9 lines, cpu.vhd 1, PSX.sv one blank line)
- rtl/gpu.vhd
  - a43ec84 2026-10-20 GPU: reqVRAMwrap computed one clk2x after the request from registered operands (docs/area_timing.md 9)
- rtl/mdec.vhd, rtl/spu.vhd
  - 55d6e91 2026-10-20 mdec.vhd, spu.vhd: the two unconditional upstream changes behind generics (IDCT_REG_STAGE, MLAB_WR_NEGEDGE), 0 = upstream, set by psx_top from CPU_CLK_SPLIT and ZN2_BOARD

### Card save and high score save (1c93c21 to 167276d)

From `git log --format='%h %ad %s' --date=short 1c93c21..167276d --
<file>`; b6dd7c2 is a merge with changes of its own (the shared upload
mux in PSX.sv).

- PSX.sv
  - 167276d 2026-10-21 High score pause crossing launched from cdc_tx_hs_paused on clk_cpu (cdc.sdc rule); the first fits timed isPaused to cdc_rx_s1 as a clk_cpu to clk_1x path (-7.9 ns)
  - b6dd7c2 2026-10-21 Beta candidate: merge i9-nvram (card hunk journal, issue #9) with the high score save; both in GNET_Z1FULLR; zoom_mix +6.02 dB (OUT_SHIFT 15)
  - 24b2468 2026-10-21 High score save for Super Puzzle Bobble behind GNET_HISCORE (test revision GNET_Z1FULLH)
  - 617c721 2026-10-20 Issue #9: card hunk journal behind GNET_CARD_JOURNAL (test revision GNET_Z1FULLJ)
- rtl/psx_top.vhd, rtl/psx_mister.vhd
  - 617c721 2026-10-20 Issue #9: card hunk journal behind GNET_CARD_JOURNAL (test revision GNET_Z1FULLJ)
