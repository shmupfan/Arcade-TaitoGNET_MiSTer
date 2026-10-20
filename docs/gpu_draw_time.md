# R23: GPU drawing time of the core per frame

Status: DONE 2026-10-07 for the seek windows of all six games, Ray Crisis
attract demo 1, a PS1 hardware calibration and one VRAM latency
sensitivity run. Question from docs/r1_speed_study.md: in Ray Crisis
attract demo 1 the PCB shows about 223 more frames than MAME 0.288 (7.8%),
MAME's GPU draws instantly, so is GPU drawing time the cause, and does the
core's GPU reproduce it?

## Result

1. **Without latency, the core's GPU fits every gameplay frame I measured
   in the frame period.** Over 3,612 seek frames (six games, two windows
   each), the longest frame is 9.95 ms against 16.715 ms.
2. **Ray Crisis demo 1 is the heaviest load measured.** The median frame
   takes 12.33 ms and the longest 18.63 ms. In 81 of 2,859 frames the
   GPU work would end after the next vblank. With the game's frame loop
   (section 4.2) that predicts 81 extra frames. The PCB shows 223.
3. **The PCB's slowdown does not follow the core's GPU load.** Up to MAME
   frame 4759 the PCB already shows 75 extra frames, while the core's
   longest frame there is 14.44 ms, about 2.1 ms under the limit after the
   kick offset. Scaling the
   core's GPU time by one factor does not match the PCB profile. A factor
   of 1.15 gives the right total (235) but 2 extra frames by frame 4759
   instead of 75. A factor of 1.3 gives the right start but 1,069 in total.
4. **On PS1 hardware, drawing is up to 2.7 times slower than in the
   core.** Measured with the ps1-tests gpu/bandwidth primitives:
   - untextured rectangles and quads: the console is within 9% of the core;
   - semi-transparent primitives: 1.26 to 1.27 times slower;
   - textured rectangles: 1.33 to 1.59 times slower;
   - textured 15-bit quads: 2.39 to 2.73 times slower.

   A GPU this slow on textured quads would push most demo frames past
   the frame period and give far more than 223 extra frames.
5. **VRAM latency has a large effect.** With 12 extra clk2x cycles per
   VRAM read burst, the mean GPU time per frame in the heaviest demo chunk
   rises from 14.08 ms to 18.58 ms (+32%), and the GPU is busy through the
   whole of every vblank interval.

Verdict on R23 (medium confidence): drawing time alone, as the core models
it, does not explain the PCB's slowdown. With ideal VRAM the core predicts
about a third of the extra frames (81 of 223), and in other places than the
PCB shows them. The PCB's drift is steady, at 5 to 10% in every stretch,
including stretches where the core's GPU has 3 ms or more to spare. A
limit that is near the frame period in every frame fits that better than
GPU peaks do. Candidates are CPU time on the slower CPU (0.82 of MAME, R1)
plus DMA bus contention, which MAME does not model, or a GPU whose speed
differs from both the core and the PS1. The core's own frame rate in this
demo depends strongly on its VRAM (DDR3) latency, which this testbench does
not model.

## 1. Which clock the core draws on

- Every GPU process (command FIFO, drawing units, pixel pipeline, VRAM
  arbiter) is clocked by clk2x, 67.7376 MHz (rtl/gpu.vhd, testbench T2X
  14,762 ps). The real CXD8654Q runs from the 53.693175 MHz crystal (the
  testbench's clkvid, used only for video timing).
- The core ships with REPRODUCIBLEGPUTIMING = 0 (PSX.sv line 995). The
  upstream drawing time rule is therefore off. That rule is a minimum
  per command, in clk2x cycles:
  - polygons: 500 + bounding box area x 2 (untextured, opaque) or x 4
    (textured or semi-transparent), gpu_poly.vhd lines 632 to 634;
  - rectangles: 50 + area x 2 or x 4, gpu_rect.vhd lines 261 to 263.

  Without it, drawing runs at the pipeline's own speed (WAITIMING is
  entered only when the generic is 1).
- So the core draws at up to one pixel per clk2x cycle: 1.134 ms for a
  320 x 240 untextured rectangle (section 5), which is 14.8 ns per pixel.

## 2. Method

**Instrumentation.** I added it to sim/m1/tb_gpu_replay.vhd, nothing in
rtl/ changed. The instrumentation started in commit 9b1e398; the
GPUREAD_DRAIN option and the vblank column came later.
- Generics: GTIME, VIDCAP, VRAM_RD_LAT, GPUREAD_DRAIN.
- I read the GPU's internal signals through VHDL-2008 external names.
- **Idle condition:** no command in progress (proc_idle), command FIFO
  empty with no word in flight (fifoIn_Empty, fifoIn_Wr, fifoIn_Valid),
  pixel pipeline idle (pipeline_busy), pixel write FIFO drained
  (fifoOut_idle, pixelWrite). This is the drawing part of gpu.vhd's
  SS_Idle condition. VRAM arbiter states are not part of it, because
  video-out line reads occupy the arbiter without drawing.
- **frames_time.txt**, one line per stream frame:
  - start: the first word of the frame presented to the GPU;
  - end: the first clk2x edge, at least 4 edges after the frame's last
    word, at which the GPU is idle;
  - span: end minus start;
  - busy: the non-idle edges in [start, end);
  - overrun: the next frame's first word came before the GPU went idle.
- **vblank_busy.txt:** non-idle clk2x edges per vblank interval.

**Replay.** tb_gpu_replay releases the words of MAME frame F at the GPU's
vblank F and feeds them as fast as the GPU accepts them:
- CPU writes wait out bus_stall;
- DMA words go one per clk1x while the GPU requests data.

Settings: VRAM_Y_BITS = 10, dithering on, VRAM model with one cycle of read
latency and no busy. Builds: `M1_BUILD=gtime sim/m1/build.sh` (own
directory, sim/m1/gtime/, gitignored) and `tools/gpu_time_run.sh`, one
work library per run, under nice -n 15, at most 3 of my runs at a time.

**Why this is a lower bound on the drawing time:**
- On the board the CPU produces part of the commands during the frame
  (Ray Crisis sends its CLUT uploads 1.0 to 13.5 ms after the vblank, gpu.log).
  The replay sends them as soon as the GPU accepts them.
- The VRAM model answers in one cycle and never stalls. The MiSTer core
  reads VRAM from DDR3.

So span is the shortest time in which the core's GPU can finish the frame.
A frame whose span exceeds the frame period would force a dropped frame on
hardware with the same GPU. In every frame that did not overrun, span and
busy differ by at most 0.011 ms. So when fed without pause, the GPU is the limit.

**VRAM to CPU reads.** GP0 C0h keeps the GPU busy until the data is read.
MAME's DMA2 read from the GPU is a kind 4 record in the stream, with no
payload. My first demo run therefore stopped: GPU busy until MAXFRAME from
MAME frame 3900, and from the first frame of the 4260 chunk. GPUREAD_DRAIN
reads one word per clk1x, as the DMA would. The demo streams contain 105
such commands (in groups of 3 in the frames I inspected, 16 x 64 pixels
each). The seek
streams contain none. I reran all runs with the option on.

## 3. Seek windows, all six games

Streams: sim/m1/work/seek_<game> (MAME frames 2700 to 3001) and
seek1500_<game> (1500 to 1801), with credit, from the m1_<game>_60 oracle
runs (docs/m1_gpu_zn2.md 2c). There are 302 frames per run. A few MAME
frames hold no GPU words and are skipped:
- shikigam 1500 window: 32, 36, 42;
- xiistag 1500 window: 195, 196, 202;
- the last frame of each 2700 window.

Span per frame (ms), both windows pooled
(`tools/gpu_time_stats.py seek <game> sim/m1/gtime/seek_<game> sim/m1/gtime/seek1500_<game>`):

| Game | Frames | Min | Median | p95 | Max | Over 16.715 ms | Median words per frame |
|---|---|---|---|---|---|---|---|
| raycris | 603 | 8.60 | 8.64 | 8.66 | 8.67 | 0 | 893 |
| nightrai | 603 | 2.91 | 3.35 | 3.85 | 4.93 | 0 | 963 |
| psyvaria | 603 | 6.31 | 6.91 | 7.79 | 9.32 | 0 | 6,144 |
| psyvarrv | 603 | 1.76 | 6.91 | 9.71 | 9.95 | 0 | 5,148 |
| shikigam | 600 | 0.15 | 3.98 | 4.05 | 4.89 | 0 | 321 |
| xiistag | 600 | 0.34 | 4.64 | 6.14 | 8.89 | 0 | 2,128 |

Notes:
- No frame overran in any seek run.
- The median is under 60% of the frame period in every game.
- The 1500 window of Psyvariar Revision is lighter (median 3.04 ms) than
  its 2700 window (7.25 ms).
- These windows are ordinary play shortly after a credit, not the games'
  known heavy scenes.

## 4. Ray Crisis attract demo 1

### 4.1 Capture

The 60 s oracle captures do not cover demo 1:
- the demo runs from MAME 63.3 s to 111.1 s (docs/r1_speed_study.md 3.2);
- the m1_raycris_60 and gs_canary runs insert a coin at 20 s.

I ran one MAME 0.288 oracle run (stock binary, nice -n 15, no other MAME
running):
- `ORACLE_NVRAM_FROM=<gnet-mister-r1>/sim/r1/mame_mb2011_a`
  `ORACLE_GPU_STREAM=1 ORACLE_SNAP_EVERY=60`
  `ORACLE_VRAM_DUMPS=3780,4260,4740,5220,5700,6180`
  `tools/mame/oracle_run.sh raycris 113 sim/oracle/gtime_raycris_demo1`
- 52 s wall time; 6,761 frames; 37,065,429 stream words (events.log).
- It starts from the same post-copy MB2011 NVRAM as the R1 300 s run
  (mame_mb2011_300).
- Its snapshots at frames 600, 1200, 3780, 3840, 4800, 5400, 6000, 6600
  and 6720 are pixel-identical to that run's, so frame numbers line up with
  the R1 alignment.

Demo 1 is MAME frames 3788 to 6646 (2,859 frames). I replayed it in six
chunks of 481 frames, each seeking from the MAME VRAM dump at its start
(`tools/gpu_stream.py --from S --maxframe S+480`).

### 4.2 Frame loop

From gpu.log, in every one of the 2,859 frames:
- right after the frame starts, the game flips the display (GP1 05h,
  alternating y 0 and 240) and starts two or more DMA2 transfers to
  the GPU (linked lists in the frames I inspected);
- the offset of that kick after MAME's frame notifier is 0.119 to
  0.501 ms (median 0.153 ms).

This is the usual DrawSync, VSync, flip, DrawOTag loop. The list drawn in
frame F has until the next vblank. If the GPU is still drawing then, the
flip waits one more vblank, so a frame whose kick offset plus GPU time
passes the period costs ceil((offset + time) / 16.715 ms) - 1 frames. The
CPU builds the next list in parallel, and MAME shows that the CPU alone
keeps 60 fps (R1).

### 4.3 Core GPU time

`tools/gpu_time_stats.py demo 3788 6646 sim/oracle/gtime_raycris_demo1/gpu.log sim/m1/gtime/demo_*`:

| Measure | Value |
|---|---|
| Frames | 2,859 |
| Span min / median / p95 / max | 0.36 / 12.33 / 15.28 / 18.63 ms |
| Median words per frame | 8,792 |
| Frames with span over 16.715 ms | 44 |
| Frames that overran into the next frame (backlog) | 80 |
| Work per frame (backlog runs shared evenly), frames whose kick offset + work passes 16.715 ms | 81 |
| Predicted extra frames | 81 |
| PCB extra frames over the same span | about 223 |

A typical heavy frame (MAME 5701) holds 1,631 commands over about 1.04
million pixels of primitive area, mostly textured Gouraud quads:
- 492 opaque (582,000 pixels);
- 103 semi-transparent (259,000 pixels).

Profile, cumulative extra frames from MAME frame 3788 (PCB: points of the
R1 alignment with correlation of at least 0.97, and the 177.0 s end point;
core: GPU work scaled by k):

| MAME frame | 4040 | 4323 | 4759 | 5401 | 6646 |
|---|---|---|---|---|---|
| PCB | 16.5 | 32.9 | 75.3 | 121.7 | 223.4 |
| core, k = 1.00 | 0 | 0 | 0 | 32 | 81 |
| k = 1.10 | 0 | 0 | 0 | 64 | 179 |
| k = 1.15 | 0 | 0 | 2 | 85 | 235 |
| k = 1.20 | 0 | 0 | 22 | 125 | 333 |
| k = 1.30 | 15 | 43 | 173 | 380 | 1,069 |
| k = 1.40 | 116 | 229 | 427 | 759 | 1,784 |

Where the core's frames would drop:
- at k = 1, the extra frames fall in two heavy stretches, MAME 5220 to
  5251 and 5814 to 5862 (median span 14.98 ms in 5708 to 5947);
- in 3788 to 4987 the core's longest frame is 14.44 ms, so no factor up
  to 1.15 produces a drop there;
- the PCB gains 75 frames in that stretch.

## 5. Calibration against PS1 hardware

`tools/gpu_time_bench.py` re-creates the drawing commands of
JaCzekanski/ps1-tests gpu/bandwidth (reference/ps1-tests, f727802):
- 320 x 240 primitives, 8 per test (the console ran 400);
- draw area 0,0 to 1023,511, E1 tpage 0Ah with dither;
- VRAM all zero, as after the test's clearScreen().

The console times come from the test's own log
(gpu/bandwidth/psx.log, hblank count / 15,732 Hz / 400). Core times are
span / 8 (sim/m1/gtime/bench).

| Test | PS1 ms per primitive | Core ms per primitive | PS1 / core |
|---|---|---|---|
| FillScreen GP0(02h) | 0.193 | 0.286 | 0.68 |
| Rectangle | 1.208 | 1.134 | 1.07 |
| Rectangle (semi-transparent) | 1.820 | 1.433 | 1.27 |
| Rectangle textured (4-bit) | 2.406 | 1.511 | 1.59 |
| Rectangle textured (semi) | 2.406 | 1.814 | 1.33 |
| Polygon quad | 1.228 | 1.143 | 1.07 |
| Polygon quad (semi) | 1.851 | 1.466 | 1.26 |
| Polygon quad textured (15-bit, UV 0 to 255) | 6.347 | 2.328 | 2.73 |
| Polygon quad textured (semi) | 6.347 | 2.652 | 2.39 |
| Polygon quad, 1/4 off screen | 0.929 | 0.859 | 1.08 |
| Polygon quad, 1/2 off screen | 0.631 | 0.576 | 1.09 |
| vramToVram 320 x 240 | 3.040 | 1.451 | 2.10 |
| cpuToVram 320 x 240 | 1.938 | 2.268 | 0.85 (testbench feed limit) |

Notes:
- Every texel is 0 (transparent) in both. The core then skips the VRAM
  write, so its textured times are a lower bound, and the textured ratios
  an upper bound.
- This is a PS1 GPU, not the CXD8654Q. No ZN-2 GPU timing measurement is
  known (docs/evidence_sources.md).
- Reading: the core matches the PS1 on untextured drawing. It is 1.3 to
  2.7 times faster on semi-transparent and textured drawing, and on VRAM
  copies.
- If the ZN-2 GPU drew textured Gouraud quads at the PS1 rate, demo frames
  would need roughly k = 1.3 or more, which predicts over 1,000 extra
  frames (table in 4.3), not 223.

## 6. VRAM latency sensitivity

Demo chunk 5700 with VRAM_RD_LAT = 12 (12 extra clk2x cycles before each
read burst's data, an arbitrary test value, not a measured DDR3 figure):

| Run | Mean busy per frame | Median busy | GPU busy share of all vblank intervals |
|---|---|---|---|
| no added latency (481 frames) | 13.92 ms | 13.24 ms | 83.3% |
| VRAM_RD_LAT = 12 (433 complete frames before MAXFRAME) | 18.58 ms | 17.78 ms | 99.99% |

Comparing the same 433 frames, the mean rises from 14.08 to 18.58 ms. So
on MiSTer the core's drawing time in this demo depends on the DDR3 read
latency at least as much as on the drawing logic. Before anyone compares
the core with PCB slowdown, that latency has to be measured, for example
with a GPU busy counter in the core on hardware.

## 7. What would settle it

- Run demo 1 on the core on MiSTer with a frame counter (or a capture), and
  count repeated frames against MAME. This includes the DDR3 latency and the
  CPU.
- A per-frame repeat count from a direct capture of the PCB (R1 section 5).
  It would show whether drops are spread evenly, which points to a steady
  CPU or bus limit, or clustered in the heavy stretches, which points to
  the GPU.
- The ps1-tests gpu/bandwidth program on a ZN-2 or G-NET board (MB2011
  BIOS path, R1 section 5), for the CXD8654Q's own drawing rates.

## 8. Files

- `sim/m1/tb_gpu_replay.vhd`: generics GTIME, VIDCAP, VRAM_RD_LAT and
  GPUREAD_DRAIN (instrumentation from commit 9b1e398).
- `sim/m1/build.sh`: M1_BUILD=<dir> for a separate build directory.
- `tools/gpu_time_run.sh`: one timing run in sim/m1/gtime/<name>/.
- `tools/gpu_time_stats.py`: seek and demo statistics, demo prediction and
  scale table.
- `tools/gpu_time_bench.py`: ps1-tests gpu/bandwidth stream and
  comparison.
- Work data (gitignored, game-derived):
  - `sim/oracle/gtime_raycris_demo1/` (MAME run, gpu.log, VRAM dumps);
  - `sim/m1/gtime/` (streams, run directories, frames_time.txt and
    vblank_busy.txt per run);
  - `sim/m1/gtime/run1_*` hold the first demo runs without GPUREAD_DRAIN,
    for reference only.
