# R1/R23 speed study: G-NET CPU throughput from PCB footage against MAME 0.288

Status: DONE for the westtrade footage (2026-10-04), including a CPU clock
sweep in a patched MAME 0.288 build (section 6.1). Evidence rank: PCB
footage is rank 4, MAME rank 5 (docs/evidence_sources.md).

## Result

On the one usable PCB recording, Ray Crisis runs slower than MAME 0.288 in
both events I could pair:

| Event | PCB | MAME 0.288 (100 MHz) | PCB / MAME | MAME clock that matches the PCB |
|---|---|---|---|---|
| Boot loader ("Prepares the start." bar) | 14.69 s | 12.34 s | 1.19 | 82 MHz (81.4 to 82.6) |
| Attract demo 1 (same deterministic demo) | 51.5 s | 47.8 s | 1.078 | none: even 67.7 MHz gives 48.1 s |
| Attract intro (timer-paced control) | 33 s, drift under 1 frame | same | 1.000 | n/a |

1. **CPU-bound code runs at about 0.82 of MAME's model.** The loader is
   CPU work on data read from flash. In the sweep its time follows
   1078 / f_MHz + 1.54 s (residual under 15 ms over 67.7 to 100 MHz), and
   the PCB's 14.69 s matches an 82 MHz crystal in MAME's model. That is
   20.5 M MAME cycles/s against MAME's 25.0 M. The ZN-1 rate (67.7376 MHz,
   16.93 M) gives 17.47 s, far too slow.
2. **The demo slowdown is not a CPU effect in MAME's model.** At every
   clock from 67.7 to 100 MHz, MAME runs demo 1 in 47.8 to 48.1 s with
   almost no dropped frames (0.7% at 67.7 MHz, 0% from 80 MHz). The PCB
   needs 51.5 s, with about 7.8% dropped frames. MAME's GPU draws
   instantly in emulated time, so the most likely cause is GPU drawing
   time (or GPU/DMA bus contention) on the real board, not the CPU clock.

My conclusion (medium confidence for item 1, medium-low for item 2):

- The effective CPU rate is about 0.82 of MAME's ZN-2 setting for this
  code, between the ZN-1 and ZN-2 settings and closer to ZN-2.
- This is an effective rate for MAME's cost model, not a clock. MAME's
  psx.cpp has approximate load/store timing and no wait states, and
  models cache timing simply. A real 50 MHz core with real memory
  penalties could produce the same 0.82, as could a slower clock.
- Game slowdown on the board depends on something MAME does not model. For
  the core, real GPU drawing time (as in the PSX_MiSTer GPU, same
  53.693 MHz crystal) is the first candidate. This demo is a ready-made
  test: 223 extra frames over demo 1 on the PCB.

## 1. Sources

| Video | Uploader, date | Capture | Use |
|---|---|---|---|
| https://www.youtube.com/watch?v=zIpQM4xNWdY "TAITO G NET Arcade Board with Ray Crisis" | westtrade, 2022-01-10 | Camera filming the CRT of a Sega Astro City cabinet, then a teardown of the board on a table (G-NET board with card, visible from about 5:30). 1280x720 H.264, 19001/317 = 59.94 fps, 62,439 frames over 1,041.7 s; frame timestamps are constant (16/17 ms steps, no gaps). PCB beyond reasonable doubt: the board is shown | Boot from power-on, two and a half attract cycles. Ray Crisis VER 2.03A (US: Americas notice, FBI, parental advisory and recycle screens). The sub-BIOS logo reads "TAITO CORPORATION MB-2011": the board runs the MB2011 modified BIOS |
| https://www.youtube.com/watch?v=A_gQx5IWtVg "Ray Crisis - 3D Arcade Shoot 'Em Up (Taito G-NET 1998)" | Gamers Bay, 2022-04-06 | Clean direct feed, 1280x720 at 60/1 fps, pillarboxed, soft scaling. Japanese version, intro then a full human playthrough. Capture source not stated: needs-review (1.1) | Not paired (human input); slowdown profile only |
| https://www.youtube.com/watch?v=j13Liu8hmiY "Night Raid - Classic Arcade Shoot 'em Up (Takumi 2001)" | Gamers Bay, 2023-06-09 | Direct feed, 1280x720 at 60/1 fps, human play, needs-review | Not paired; slowdown profile only |

The footage files are kept outside this repository. Never commit video or extracted frames: all work output is under gitignored `sim/r1/`.

### 1.1 Gamers Bay capture method

A real G-NET board refreshes at 59.826 Hz (MAME's note, and the frame
period in my MAME runs: 16.715 ms). A 60 fps recording of it that is not
genlocked shows one duplicated frame about every 5.75 s. YouTube's
transcoder would add the same if the upload were 59.83 fps.

The Ray Crisis video has no such cadence. It has 368 repeat-like frames in
957 s of motion, in clusters, with no 345-frame spacing. Stage 1 action
runs without dropped frames.

That fits an emulator running at 60 Hz, or a genlocked capture re-timed to
60, equally well. I keep it at needs-review and do not use it for timing.
Night Raid shows 2,125 repeat-like frames in 828 s (about 4%), clustered in
heavy scenes, so that capture does show load-dependent slowdown.

## 2. Method

1. **PCB signature:** `tools/r1/r1_lum.py` decodes the video with ffmpeg and
   writes, per frame, the mean colour and mean absolute difference to the
   previous frame of the screen area. For westtrade the crop is
   500x390+390+190, the CRT.
2. **MAME signature:** `tools/r1/r1_run.sh` runs MAME 0.288 under
   nice -n 15 with `tools/r1/r1_frames.lua`. Per emulated frame the script
   records time, visible size, mean colour and difference to the previous
   frame over a 32x24 sample grid, plus optional PNG snapshots.
3. **Matching the PCB's BIOS:** stock raycris (V2.03O) boots the 1998
   sub-BIOS, while the PCB shows MB-2011. In MAME I closed JP1
   (`R1_JP1=1`), so the MB2011 EPROM's flasher rewrote U30. The flasher
   showed "初期化中" and then "正常に書き込みが終了しました" (written
   normally), done by 141 s. Then I booted with JP1 open, so the BIOS
   copied the card into flash ("Loading now.", about 140 s), and booted
   again. That third boot is the warm boot the PCB shows. Its timeline is
   frame for frame the same as the stock warm boot, and the MAME logo still
   reads 1998 (open point, 6.3).
4. **Events:** I matched discrete events by transition frames (scene cuts,
   resolution changes). For the attract I used `tools/r1/r1_align.py`: it
   cross-correlates the z-scored luminance traces in 3 s windows at 0.5 s
   steps (120 Hz resampling) and reports the best MAME time offset, the
   correlation and the second-best peak. Inside one segment of
   deterministic content, a drifting offset means one machine took longer.
5. **What the loader does:** the M0 oracle (`tools/mame/oracle.lua`) on the
   MB2011 warm boot shows the loader reading only the U30 flash,
   about 500,000 reads between 2 s and 14 s at 36,000 to 53,000 per second.
   There is no ATA access in that window.

## 3. Events

Times in seconds; PCB frames are 59.94 fps camera frames, MAME frames are
59.826 Hz.

### 3.1 Boot (westtrade 0:52 to 1:16, MAME warm boot with the MB2011 flash)

| Event | PCB video time (frame) | MAME time (frame) |
|---|---|---|
| Sub-BIOS logo fades in | 52.3 (CRT still warming, slow ramp) | 0.318 (19), full at 0.585 (35) |
| Logo disturbance (blue/green bars, then the logo again) | 54.31 to 54.91 | none |
| Loader screen on ("Prepares the start.") | 57.78 (1065/1066) | 2.959 (177) |
| Loader screen off | 72.47 (1946) | 15.294 (915) |
| Notice on | 75.77 (2144) | 18.470 (1105) |
| Notice off | 77.79 (2265) | 20.476 (1225) |

| Interval | PCB | MAME | PCB / MAME |
|---|---|---|---|
| Loader screen | 880.5 frames = 14.690 s | 738 frames = 12.336 s | 1.191 |
| Loader off to notice on | 3.30 s | 3.18 s | 1.04 |
| Notice shown | 121 frames = 2.019 s | 120 frames = 2.006 s | 1.006 (timer-paced: confirms the two clocks agree) |

- **Power-on:** I can't measure power-on to logo on the PCB. The screen is
  dark until the CRT warms up, so the boot start is not visible.
- **Logo disturbance:** the PCB shows something MAME does not, a second
  display init with corrupted bars. It may come from the MB2011 build on
  that board or from a card retry; I did not count it.
- **Flash reads cannot explain the loader gap:** 2.35 s over about 500,000
  reads would be about 4.7 us per read. The Intel flash parts on the board
  take about 0.1 us.

### 3.2 Attract (westtrade 1:22 to 4:40, MAME 300 s run)

| Segment | PCB time | Offset MAME minus PCB | Reading |
|---|---|---|---|
| Intro (Con-Human to title) | 84.0 to 116.5 | -59.683 to -59.675 (corr 0.95 to 0.998) | No drift over 32.5 s: the camera and MAME clocks agree to under one frame |
| US-only screens (parental advisory) | about 120 to 123 | jumps to -61.96 | Inserted screens, not speed |
| Demo 1, ocean stage then city | 125.5 to 177.0 | -62.183 to -65.917 (corr 0.990 at both ends) | PCB takes 3.734 s longer over 47.77 s of MAME time (+7.8%). The drift builds steadily (5 to 9% in each 5 to 10 s stretch), not in steps at stage changes |
| Demos 2 and 3 | 190 to 276 | not usable | Correlation too low or ambiguous. The attract order diverges (US screens shift the cycle) |

- **ALERT screen to white flash** (event check inside the intro): PCB
  10.11 s, MAME 9.96 s.
- **Slowdown in MAME itself:** MAME repeats no frame in the matched span
  (63.3 to 111.1 s, 2,860 frames, `tools/r1/r1_measure.py`); its repeated
  frames fall in the title part before it. The PCB's extra 3.734 s is 223
  game frames, so the board dropped about 7.8% of frames where MAME
  dropped none.
- **Camera limits:** a CRT filmed at 59.94 fps mixes adjacent fields, so
  individual repeated frames are not reliably visible in the footage. The
  drift measures them in aggregate.

## 4. Interpretation

1. **Loader:** the loader is CPU work. Its flash reads cost far less than
   the gap, and its duration scales exactly with the CPU clock in MAME
   (6.1). So the PCB executes this code at about 0.82 of MAME's modelled
   speed. MAME could be optimistic here for several reasons, none
   separable with this footage:
   - instruction cache misses (MAME's psx core has a cache but simple
     timing);
   - RAM and flash access cycles (com_delay and BIU registers, unknown);
   - DMA or refresh contention;
   - a lower CPU clock.
2. **Demo:** the game drops more frames on the PCB than in MAME, steadily
   through both stages. MAME's demo length is insensitive to the CPU clock
   (6.1), so the CPU is not the limit in MAME's model even at the ZN-1
   rate. Frames on the board must be limited by something MAME does not
   model:
   - GPU drawing time (MAME draws instantly);
   - GPU FIFO or DMA stalls;
   - GTE timing;
   - memory contention.
   
   The PSX_MiSTer GPU draws with real timing, so the core may reproduce
   this naturally. The core should be checked against this demo.
3. **Clock bounds (MAME's model):** loader 81.4 to 82.6 MHz (camera
   transition uncertainty of about 5 frames). The ZN-1 rate (17.47 s) and
   MAME's 100 MHz (12.34 s) are both excluded.

## 5. What would settle it

From PLAN.md R1, rank 1:

- A frequency counter on the CXD8661R clock output.
- A timing test program on any CXD8661R board (ZN-2, Namco System 12, or
  G-NET via the MB2011 BIOS with a plain ATA card):
  - an ALU loop against VBlank (53.693 MHz GPU crystal) for the clock;
  - growing loop footprints for the instruction cache size;
  - timed loads per region (RAM, flash, BIOS ROM) for wait states.

From this study, rank 4, cheap and useful:

- A direct 59.826 Hz capture (genlocked or with a known cadence) of the
  same board's warm boot and attract demo. That would remove the camera's
  field mixing and give per-frame repeat counts in the demo.
- The same capture from a board with the original sub-BIOS, to exclude
  any MB2011 effect on the loader.
- A direct capture of in-game slowdown on a board, compared against
  the core with real GPU timing rather than against MAME.

## 6. Next steps and open points

### 6.1 MAME clock sweep (done)

MAME 0.288 has no supported runtime setter:

- Lua exposes no CPU clock or clock-scale method. I checked
  `cpu.clock`, `unscaled_clock`, `clock_scale` and
  `attoseconds_per_cycle` (all nil), and `manager.ui` has no slider list.
- The overclock slider (-cheat) exists only in the interactive UI.

I built a patched MAME:

- **Source:** a shallow clone of tag mame0288 (27a8d9e8), outside this
  repository.
- **Patch:** `src/mame/sony/zn.cpp`, in `zn_state::zn2`, takes the
  CXD8661R input clock from the environment variable `ZN2_CPU_HZ`
  (default 100 MHz) as a plain clock, not `XTAL()`, because XTAL values
  are checked against MAME's crystal list.
- **Build:**
  `make SUBTARGET=gnet SOURCES=src/mame/sony/taitogn.cpp,src/mame/sony/zn.cpp
  SYMBOLS=0 NOWERROR=1 OPTIMIZE=3 USE_LIBSDL=1 LDOPTS="-L/opt/homebrew/lib -lSDL3"`
  with `CPATH=/opt/homebrew/include`, plus `REGENIE=1` after changing
  `USE_LIBSDL`.
  - Without these, the link looks for an SDL3 framework that Homebrew does
    not install.
  - About 18 minutes on the M4 Pro (14 cores).
  - 378 MB build tree, 1.6 GB with source.
- **Binary:** `gnet` in that tree, version
  "0.288 (mame0288-dirty)".
- **Check:** with the variable unset, the binary matches stock MAME 0.288
  on all 1,496 frames of a 25 s MB2011 warm boot.

Sweep: `tools/r1/r1_sweep.sh`, 135 s from the same post-copy MB2011 NVRAM,
3 at a time, nice -n 15. I measured the loader with `r1_measure.py` and
demo 1 by aligning the PCB windows at 125.5 s (3 s) and 177.0 s (4 s) with
`r1_align.py`. Correlation is 0.990 at both ends for every clock.

| CXD8661R clock (MHz) | MAME cycles/s | Loader (s) | Demo 1 span in MAME (s) | PCB / MAME demo | MAME repeated frames in demo 1 |
|---|---|---|---|---|---|
| 67.7376 | 16.93 M | 17.467 | 48.075 | 1.071 | 19 / 2876 (0.7%) |
| 75 | 18.75 M | 15.913 | 47.825 | 1.077 | 4 / 2861 (0.1%) |
| 80 | 20.00 M | 15.010 | 47.767 | 1.078 | 0 |
| 82 | 20.50 M | 14.676 | 47.767 | 1.078 | 0 |
| 84 | 21.00 M | 14.375 | 47.767 | 1.078 | 0 |
| 86 | 21.50 M | 14.074 | 47.767 | 1.078 | 0 |
| 88 | 22.00 M | 13.790 | 47.767 | 1.078 | 0 |
| 92 | 23.00 M | 13.255 | 47.775 | 1.078 | 0 |
| 96 | 24.00 M | 12.770 | 47.767 | 1.078 | 0 |
| 100 (stock) | 25.00 M | 12.336 | 47.767 | 1.078 | 0 |
| PCB | | 14.690 | 51.5 | | about 223 extra frames |

- **Loader fit:** loader = 1078.1 / f_MHz + 1.540 s (least squares,
  maximum residual 0.015 s). The PCB's 14.69 s gives 82.0 MHz, and the
  +/- 0.09 s transition uncertainty gives 81.4 to 82.6 MHz.
- **Frame timing:** MAME's frame period is 16.715 ms and its mode 320x240
  in both the intro and the demo, so the demo drift is not a refresh-rate
  effect.

### 6.2 Not separable from footage

- CPU clock vs instruction cache size and miss cost.
- RAM, BIOS ROM and flash wait states.
- GPU drawing time (MAME has none).
- SPU/DMA bus contention.
- ATA/card timing: not involved in either event measured here.

### 6.3 Open points

- MAME's MB2011-flashed boot still shows the 1998 logo, and the PCB shows
  "MB-2011". Either the PCB's U30 holds a different MB2011 build, or
  MAME's flasher image differs. The loader is the game's own code from
  flash, so I assume it is unaffected (needs-review).
- The PCB is V2.03A (US) and MAME's raycris is V2.03O. The demo content
  matched (correlation 0.95 to 0.99); region screens only shift the
  attract cycle.
- The fixed 1.54 s part of the loader (not CPU-scaled in MAME) could hide
  card or flash timing on the PCB; the fit absorbs it in MAME only.
- Demos 2 and 3 could be paired with a longer MAME run started in the same
  attract phase as the PCB, or by matching the US screen order. I have not
  done that yet.

## 7. Files

- `tools/r1/r1_run.sh`: MAME 0.288 runner (warm boot from a post-copy
  NVRAM set, `R1_JP1=1` for the MB2011 flasher, `R1_SNAP_EVERY`,
  `R1_COIN_AT`).
- `tools/r1/r1_frames.lua`: per-frame screen signature and optional
  snapshots.
- `tools/r1/r1_lum.py`: per-frame signature of a video region.
- `tools/r1/r1_align.py`: windowed cross-correlation alignment of PCB and
  MAME traces.
- `tools/r1/r1_measure.py`: loader duration and repeated frames in a MAME
  trace.
- `tools/r1/r1_sweep.sh`: clock sweep with the patched build
  (`MAME=.../gnet`, `ZN2_CPU_HZ`).
- Work data (not committed, `sim/r1/`):
  - `west/` (PCB traces);
  - `mame_*` (MAME runs; `mame_mb2011_a` holds the post-copy MB2011
    NVRAM);
  - `align_*.txt`;
  - `sweep/hz_<clock>/` (sweep runs);
  - `gb_rc/`, `gb_nr/` (Gamers Bay traces).
