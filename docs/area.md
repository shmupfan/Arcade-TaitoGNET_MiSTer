# Area: freeing FPGA resources for timing closure (plan step 4)

Date: 2026-10-20. Branch `area` (worktree ../gnet-mister-area) from alpha4
59d57d1. RTL commit db78699. No Quartus run, no hardware test, no tier 2
regression (section 6 lists what was and was not checked).

Why: the release revision GNET_Z1FULLR fills 87% of the Cyclone V
5CSEBA6U23I7 (36,364 to 36,458 ALMs of 41,910 over the four alpha 4 seeds of
2026-10-20, 36,441 in the alpha 3 release fit) and 462 of 553 M10K. The HDMI
setup failures are placement pressure in sys/ascal.vhd
(gnet-mister-hdmitiming docs/hdmi_timing.md), so a fit closes on some seeds
and not others. Freeing area the games cannot see gives the placer room.

Rule for this branch: nothing a game can see changes. Each change is behind
a GNET_ macro (PSX.sv) and a psx_top or entity generic whose default keeps
every other revision, and upstream PSX, as before.

## 1. Where the area is

Source: `tools/fit_entities.py` on
`gnet-mister-a3cal/builds/20261020_1848_z1fullr_seed2/GNET_Z1FULLR.fit.rpt`
(alpha 4 without issue #12; 36,415 ALMs, 462 M10K, 102 of 112 DSP). The
alpha 3 release fit (builds/20261015_2100_z1fullr) differs by less than 1%
per block; its numbers are given where the audit quoted them.

| Block (hierarchy) | ALMs | M10K | DSP | Notes |
|---|---|---|---|---|
| gpu | 5,844 | 27 | 32 | gpu_poly 2,155 ALMs and 29 DSP, six dividers 660 ALMs |
| zoom_board | 4,712 | 151 | 5 | mn10200 1,863, zsg2 1,346, tms57002 922 ALMs and 68 M10K, pcache 33 and wram 32 M10K |
| spu | 4,307 | 82 | 13 | spu_ram 1,069 ALMs and 75 M10K (64 of them the reverb RAM, section 3.4) |
| gte | 3,103 | 0 | 9 | |
| cpu | 2,495 | 76 | 6 | datacache 64 M10K (section 3.3); I-cache, scratchpad, tag MLAB 210 ALMs |
| sys ascal | 1,928 | 42 | 15 | framework |
| zn2_board | 1,803 | 11 | 1 | gnet_fc 1,236; zn2_io 95 ALMs and 6 M10K |
| dma | 1,259 | 3 | 0 | |
| sys audio_out | 1,009 | 0 | 8 | framework |
| sys osd x2 | 1,062 | 8 | 0 | framework |
| memorymux | 835 | 0 | 0 | |
| sys own logic | 803 | 0 | 0 | framework |
| gnet_arcade_video | 785 | 27 | 0 | scandoubler, HQ2x (Fx) |
| hps_io | 655 | 0 | 0 | framework |
| mdec | 660 | 17 | 9 | sianniv needs it (LANDMINE, never drop) |
| sys pll_hdmi_adj | 535 | 0 | 0 | framework |
| savestates | 399 | 0 | 0 | reset sequencer (LANDMINE, never remove) |
| emu own logic | 319 | 0 | 0 | |
| cpu_split | 298 | 2 | 0 | |
| sdram | 291 | 0 | 0 | |
| gnet_ddr3_arb | 285 | 4 | 0 | |
| crt_pos | 244 | 0 | 1 | |
| zn_dbg_regs | 182 | 0 | 0 | debug overlay capture (section 3.1) |
| zn_dbg_overlay | 115 | 1 | 0 | debug overlay video side (section 3.1) |

The console-only parts of PSX_MiSTer are already out of the release: CD
(HAS_CD 0), pads and memory cards (HAS_PADS 0), cheats, the savestate
manager, and every console OSD option GNET_LEAN ties to a constant (texture
filter, fps and error overlays, widescreen, turbo modes; their logic is
swept by Quartus). What is left falls into three groups: blocks the games
use, framework blocks in sys/ (not ours to trim), and a few structures that
survive although their output can never matter. The last group is what this
branch removes.

## 2. Summary of changes on `area`

| Change | Switch | Frees (estimate) | Game-visible change |
|---|---|---|---|
| Debug overlay and capture block out | `GNET_NO_DBG` (PSX.sv), psx_top `ZN2_DBG` 0 | 297 ALMs, 1 M10K (measured in the alpha 4 fit) | none; the OSD option "Debug overlay" (Advanced) disappears |
| CPU turbo data cache out | `GNET_NO_DCACHE` (only with GNET_LEAN), cpu and psx_top `HAS_DCACHE` 0 | 64 M10K, about 30 to 100 ALMs (not measured) | none |
| zn2_io mailbox stub out | zn2_io `ZOOM_STUB`, driven 1 - ZOOM by zn2_board | 2 M10K, under 10 ALMs | none |

GNET_Z1FULLR sets `GNET_NO_DBG=1` and `GNET_NO_DCACHE=1`. The mailbox change
needs no macro: every ZOOM = 1 build loses the unreachable stub.

Total: about 330 to 400 ALMs (0.8 to 1.0% of the device) and 67 M10K
(462 to 395, 83.5% to 71.4%). No DSP is freed (102 of 112 stay). Against the
alpha 4 seed 2 fit that is roughly 36,415 to 36,000-36,090 ALMs. Issue #12
(gnet_ddr3_flcopy, in alpha4 but not in that fit) adds an estimated 150 to
250 ALMs and 2 M10K (docs/i12_ddr3_load.md), so the area build should land
near or a little under the alpha 3 release's 36,441 ALMs with about 69 fewer
M10K than alpha 4.

The M10K reduction matters beyond the count: the 64 data cache blocks are
spread over X38 to X76, Y3 to Y18 in the seed 2 fit, each fed by the same
address and data buses, and they sit on CPU timing paths (sdram
ch1_dout32_f to the cache's port B data input at 2.29 ns; the cache's
address register to writebackData), so their removal also takes routing out
of the CPU region. Whether that helps HDMI setup in ascal is for the seed
sweep to show.

## 3. Candidates

### 3.1 Debug overlay (implemented, GNET_NO_DBG)

- Resources: zn_dbg_overlay 115.2 ALMs and 1 M10K (512 bits), zn_dbg_regs
  181.7 ALMs, alpha 4 seed 2 fit (alpha 3 release: 121.9 and 194.2, the
  audit's "about 316 ALMs"). Also swept with them: the DDR3 arbiter's status
  word (rotation high-water mark, overflow flags), only read by the DR row.
- Evidence G-NET never uses it: it is a tester tool (OSD Advanced, Off by
  default), not part of the board. With the option Off the overlay's RGB
  output is its input for every pixel, combinationally
  (rtl/gnet/zn_dbg_overlay.vhd:371, no register on the path), so wiring
  `video_aspect`'s RGB straight through gives the same picture and the same
  timing as the release with the option Off. The capture block only reads
  CPU and board signals (PC, data address, watchdog, control register, ATA
  commands); zn_dbg_wd, the watchdog reset itself, is driven by zn2_board and
  stays.
- Change: PSX.sv `ifndef GNET_NO_DBG` around both OSD lines and the overlay
  instance (with the DR word); `else` assigns rgb_dbg and ties zn_dbg_idx to
  0. psx_top generic ZN2_DBG (default 1): `gzndbg` builds zn_dbg_regs only
  with ZN2_DBG = 1, `gzndbg0` drives zn_dbg_word to 0 otherwise. The code
  stays; every other revision keeps the overlay.
- Risk: low for the games. It reverses audit decision D8 ("keep") and the
  release README's "Debug overlay" entry, so README and TESTING_GUIDE need
  the option removed if an area build ships. **Conflict:** issue #12
  hardware step 4 (docs/i12_ddr3_load.md 11) reads the DR row after an `all`
  load; do that step on an alpha 4 RBF without this branch.
  GNET_CPU50_B1.sdc's overlay constraints already skip empty collections.

### 3.2 zn2_io mailbox stub (implemented, ZOOM_STUB)

- Resources: mbox_lo and mbox_hi, 2 M10K (the audit found them in the alpha 3
  release report; zn2_io has 6 M10K = EEPROM 2, NVRAM copy 2, mailbox 2),
  plus a few ALMs of decode and read mux.
- Evidence it is unreachable: with ZOOM = 1, zn2_board's `zoom_hit` covers
  exactly BE0000-BE01FF (rtl/gnet/zn2_board.vhd:258-264) and `io_req` is
  `zn_req and not gnet_hit and not zm_hit and io_hit` (line 291), so zn2_io
  never latches a BE0 address and neither writes nor reads its mailbox.
  MAME maps the same range to the Zoom's shared RAM (taitogn.cpp:487,
  taito_zoom_device::shared_ram_r/w). The sets without a Zoom board (MAME
  init_nozoom: otenamih, zokuoten, zooo, otenamhf and others) do not change
  this: the core's nozoom bit only holds the Zoom board in reset
  (psx_top.vhd:3485); the routing is static.
- Change: zn2_io generic ZOOM_STUB (default 1); the mailbox RAM and its
  process are in `gmbox` (ZOOM_STUB = 1), `gnombox` ties mb_q to 0.
  zn2_board passes `ZOOM_STUB => 1 - ZOOM`. ZOOM = 0 builds keep the stub.
- Check: sim/zn2/run_zn2_io.sh (NVC, directed): PASSED with the default.
  The same bench with ZOOM_STUB 0 (scratch copy): every check passes except
  "mbox 0/1" and "mbox fe/ff", which read 0, as intended (in a ZOOM = 1
  board those accesses go to the Zoom port).
- Risk: very low.

### 3.3 CPU turbo data cache (implemented, GNET_NO_DCACHE)

- Resources: cpu datacache, 16384 x 32 = 524,288 bits in 64 M10K, plus its
  write address and data muxes and the cache's read path into
  spad_cache_dataread (30 to 100 ALMs, estimate).
- Evidence G-NET never uses it: the data cache is not PS1 or ZN-2 hardware
  (the R3000A core has only the I-cache and the 1 KB scratchpad); it is
  PSX_MiSTer's turbo option (OSD O[80:79]). GNET_LEAN ties TURBO_CACHE and
  TURBO_CACHE50 to 0 (PSX.sv `GNET_OPT(TURBO_CACHE, 1'b0)`). In cpu.vhd,
  dcache_read_hit is read only as `TURBO_CACHE = '1' and ... and
  dcache_read_hit = '1'` (lines 2233 and 2388 of alpha4); dcache_read_data
  only reaches spad_cache_dataread (2123), which feeds gte_writeData and
  writebackData only inside the branch taken for a scratchpad read or a
  TURBO_CACHE hit, and for a scratchpad read the mux selects the scratchpad.
  So with TURBO_CACHE 0 nothing the cache holds ever reaches a register.
  Quartus already removed the cache's tag RAM (the hit is unused), but kept
  the 64-block data RAM because its output still feeds the mux
  structurally.
- Change: cpu generic HAS_DCACHE (default 1): the upstream instance sits
  unchanged inside `gdcache`; `gnodcache` ties hit and data to 0. psx_top
  and psx_mister pass HAS_DCACHE through. PSX.sv sets it to 0 only when both
  GNET_NO_DCACHE and GNET_LEAN are defined; without GNET_LEAN the macro is
  ignored, so the OSD turbo option can never lose its cache. Even if
  HAS_DCACHE 0 met TURBO_CACHE 1, the CPU would only miss every time, which
  is the TURBO_CACHE 0 behaviour.
- Risk: low. The argument is from the code (above); no simulation compares
  the two builds yet (section 6).

### 3.4 SPU reverb RAM (document only, keep)

- Resources: spu_ram iram_reverb, 32K x 16 = 64 M10K.
- It is not a reverb-only buffer: spu_ram.vhd:165-178 and 227-229 make it the
  only storage of SPU RAM 0x70000 to 0x7FFFF (reads in that range come from
  it, never from DDR3), whatever the game keeps there.
- Games use reverb: in MAME's register traces
  (gnet-mister sim/oracle/games_*_warm60/spu.log, 60 s warm boots),
  Shikigami no Shiro sets SPUCNT bit 7 (reverb master enable), mBASE FC18h
  (work area from 0x7E0C0, inside this RAM) and reverb volume 4000h.
  Night Raid, Psyvariar, Ray Crisis and XII Stag leave reverb off in those
  60 s, which says nothing about later scenes or other games.
- Removing it would mean routing 0x70000 to 0x7FFFF to DDR3, a change of
  voice and reverb timing. Not done.

### 3.5 Other candidates (document only)

| Candidate | ALMs / M10K / DSP | Why not now | Risk if done |
|---|---|---|---|
| SPU capture RAM (spu_ram iram_capture, SPU RAM 0x0000-0x0FFF) | about 0 ALMs / 4 M10K | game-readable SPU RAM; voice 1 and 3 capture is written whatever the game does | game-visible |
| DMA channel 3 (CD) | not measured; part of dma's 1,225 ALMs own logic, a channel's registers and engine are perhaps 100 to 150 ALMs | its MADR/BCR/CHCR registers are CPU-visible (the BIOS initialises every DMA channel); removing them changes reads | game-visible |
| savestates engine | 399 ALMs | already trimmed to reset mode (HAS_SAVESTATES 0: only the type 12 to 16 zero fills run); it is the reset sequencer (LANDMINE) | boot behaviour |
| savestate_ui (PSX.sv) | 31 ALMs | with GNET_NO_SAVESTATES its keyboard and joystick shortcuts still change status[38:37] and show "slot" messages on the OSD; harmless, shell-visible only | low, OSD only; candidate for a later GNET_NO_SAVESTATES tidy |
| MDEC | 660 ALMs / 17 M10K / 9 DSP | sianniv plays MDEC stills and movies (LANDMINE) | game breaks |
| Framework (ascal, osd, audio_out, pll_hdmi_adj, shadowmask) | 1,928 / 1,062 / 1,009 / 535 / 134 ALMs | sys/ is the unchanged MiSTer framework; its switches (MISTER_SMALL_VBUF etc.) change scaler features users see | user-visible |
| Zoom debug ports (zoom_board dbg_*) | 0 | already open or unread, swept by Quartus | none |

No candidate frees a DSP block without changing what games see.

## 4. Files changed (db78699)

- PSX.sv: GNET_NO_DBG around the two "Debug overlay" OSD lines and the
  overlay instance; localparams GNET_HAS_DCACHE and GNET_ZN2_DBG; two
  psx_mister generics.
- GNET_Z1FULLR.qsf: `GNET_NO_DBG=1`, `GNET_NO_DCACHE=1` with a comment block.
- rtl/psx_mister.vhd, rtl/psx_top.vhd: generics HAS_DCACHE and ZN2_DBG
  (default 1), the gzndbg condition and gzndbg0.
- rtl/cpu.vhd: generic HAS_DCACHE (default 1), gdcache/gnodcache around the
  upstream instance (upstream lines unchanged, not re-indented).
- rtl/gnet/zn2_io.vhd: generic ZOOM_STUB, mailbox in gmbox/gnombox.
- rtl/gnet/zn2_board.vhd: `ZOOM_STUB => 1 - ZOOM`.
- docs/hw_debug_overlay.md: the build switch.

## 5. Proof that nothing else moves

- Preprocessor: `verilator -E -P` of PSX.sv with GNET_Z1FULLR's macros, with
  and without the two new ones. The only differences: the OSD line, the two
  localparams (1 to 0) and the overlay instance replaced by the two assigns.
  Without the new macros the preprocessed PSX.sv equals alpha4's apart from
  the two new localparams (= 1) and the two generic map lines, whose values
  equal the generics' defaults; so every other revision's netlist is
  unchanged except that ZOOM = 1 revisions lose the unreachable mailbox.
- Elaboration: NVC 1.23 analysis of every VHDL file of psx_top (plus the ZN-2
  layer and the stubs of sim/cpu50) and elaboration of psx_top with the
  release generics (CPU_CLK_SPLIT 1, ZN2_BOARD 1, ZOOM_BOARD 1, ...) twice:
  defaults, and ZN2_DBG 0 with HAS_DCACHE 0. Both elaborate; the only
  warnings are the expected unbound SystemVerilog components (zoom_board,
  gnet_fc). Script: scratchpad elab.sh, not committed (sim/cpu50/run.sh top
  stopped working when psx_top gained `entity work.zn2_*` instances; it
  still lists no rtl/gnet files).
- zn2_io bench as section 3.2.
- Lint hook (GHDL syntax, Verilator lint with the qsf macros): clean on every
  edited file.

Not done (left for the main session, in this order):
1. Tier 2 regression (docs/regression.md, branch regress-a3) on an area
   build is not needed for the overlay or the mailbox (proved above) but is
   the check for the data cache argument: the fullsys harness passes psx_top
   generics directly, so add `HAS_DCACHE => 0, ZN2_DBG => 0` (sim/fullsys
   zn2full.sh) and compare against the golden run; results must be
   IDENTICAL. Not run here: an overnight run is using the Mac.
2. The Quartus build and seed sweep (section 7).

## 6. Hardware checks for an area RBF

- OSD Advanced shows Watchdog only (no Debug overlay).
- Ray Crisis and Shikigami: boot, attract, coin, start, play to the first
  boss; Zoom music plays (the Zoom mailbox path is the one that still
  answers BE0000).
- Zooo or Otenami Haiken (no Zoom board, MAME init_nozoom): boots (BE0000 accesses go to the held
  Zoom port as before).
- HDMI video_info as for every build (pll_hdmi counter X0_Y5_N1).
- Issue #12 step 4 (overlay DR row) cannot be done on this RBF.

## 7. Build request

- Branch `area`, commit db78699 (or the branch HEAD: later commits on `area`
  touch docs only), worktree ../gnet-mister-area.
- Revision GNET_Z1FULLR (Aggressive Performance, as committed).
- Four-seed sweep: seeds 1, 2, 3 and 4 (the same seeds as the
  20261020_1848 alpha 4 sweep, so the fits compare seed by seed).
- Gates per build: all clocks met at Slow 1100mV 100C (the flow gate) and
  hold at every corner; fit report pll_hdmi counter PLLOUTPUTCOUNTER_X0_Y5_N1.
- Area check per build with tools/fit_entities.py `--node 'sys_top$'
  --node 'emu:emu$' --node 'psx_top:ipsx_top$'`: no zn_dbg_overlay, no
  zn_dbg_regs, no cpu|datacache; zn2_io 4 M10K; M10K total about 395 plus
  issue #12's buffer (about 397); ALMs about 330 to 400 below an alpha4 fit
  of the same seed. If an alpha4 (with #12) sweep of seeds 1 to 4 exists,
  report the per-seed ALM, M10K and worst HDMI setup slack of both.
- Report the worst setup slack on the HDMI clock and on clk_cpu/clk_cpu2x
  per seed, against the 20261020_1848 sweep.
