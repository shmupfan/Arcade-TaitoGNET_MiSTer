# GPU speed: Space Invaders Anniversary band mode (follow-up to issue #10)

Branch gpu-speed (from alpha4 59d57d1). Status: hardware time estimated,
options measured in the GPU replay bench, one option (TEX_FETCH_DIR 2 with
TEX_MISS_DELAY 15) proposed for a hardware build. Simulation only; no build
made.

## 1. The question

docs/i10_triangle.md: sianniv's coloured band mode draws the emulated Space
Invaders screen as one rotated 256 x 240 textured quad (GP0 2C, 4-bit). Its
spans walk down texture columns, so nearly every pixel misses the texture
cache. With the alpha 3 prefetch and TEX_MISS_DELAY 13, and the issue #10
watchdog fix (in alpha 4), the bench needs 34.6 ms of GPU time per frame at
L = 12 (the measured idle DDR3 read latency). Questions: how long would the
CXD8654Q take, and can the core draw this faster without moving the Ray
Crisis calibration (TEX_MISS_DELAY 13: Ray Crisis demo 1 at 1.0748 on the
alpha 3 build against the board's 1.078, docs/gpu_read_infl.md 10).

## 2. What the frame costs in the core

Bench sim/gpuinfl (tb_gpu_infl, 2 MB VRAM), stream MAME frames 2700 to 2705
(i10 capture), VRAM_INIT = MAME vram_2700.bin, 8 vblanks. New in the bench:
texmiss.txt (per vblank: texture miss events = rising edges of the
pipeline's texReqActive, the clk2x cycles it is high, and the misses that
start while gpu_poly or gpu_rect is drawing).

Misses per frame with the upstream cache fill (one qword per miss, the PS1
geometry), L = 0: 61,487, of which 53,807 in the quad and 7,680 in the two
248 x 240 rectangles (3,840 each, 16 per line). A Python model of the
psx-spx / Mednafen cache geometry (256 entries of 4 halfwords, index
(v mod 64) x 4 + qword) gives 54,241 for the quad drawn as two triangles in
the core's order and 3,840 per rectangle: the core's upstream cache behaves
as the documented PS1 cache on this frame. (The quad does not miss on every
pixel as docs/i10_triangle.md 2 assumed: the triangles' spans are shorter than 256 near the
split, and some rows survive to the next span.)

Frame = GPU span of stream frame 2 (frames_time.txt), clk2x at 67.7376 MHz;
one vblank period is 1,132,400 clk2x (16.72 ms).

| Config | L | Frame clk2x | ms | Periods | Quad clk2x | Misses / frame | clk2x / miss |
|---|---|---|---|---|---|---|---|
| upstream | 0 | 574,364 | 8.48 | 0.51 | 335,312 | 61,487 | 5.1 |
| upstream | 12 | 1,332,578 | 19.67 | 1.18 | 991,985 | about 61,500 | 17.3 |
| alpha 4 release (QW 4, ROWS 2, INFL 2, D 13) | 0 | 1,660,174 | 24.51 | 1.47 | 1,412,073 | about 55,600 | 25.3 |
| alpha 4 release | 12 | 2,344,820 | 34.62 | 2.07 | 2,066,738 | about 55,200 | 37.5 |

What dominates at alpha 4, L = 12: texture miss cycles are about
55,200 x 37.5 = 2.07 M of the 2.34 M clk2x. Each miss costs the request,
12 cycles of latency, 8 beats (two rows of a 4-qword group) and the 13-cycle
delay; the second row is v + 1, which this walk (v falling along the span)
rarely uses, and of each 4-qword group only one qword is used before it is
evicted. The prefetch saves about 10% of the misses here and makes each one
2.2 times dearer than upstream at the same latency.

## 3. What the real GPU would take

### 3.1 Sources

- psx-spx, GPU texture cache (fetched 2026-10-20): 2 KB; 64 x 64 texels in
  4-bit mode; 256 entries of 8 bytes (16 4-bit texels); one entry per
  number, so entry n of two cache blocks cannot be held together. No miss
  penalty, no fetch timing. Memory: "The New GPU uses s normal DRAM chip
  (with single 32bit databus) ... The exact timing differences are
  unknown".
- MAME src/devices/video/psx.cpp (master, fetched): no texture
  cache and no drawing time ("not handled: clear cache"). MAME's 60 Hz
  drawing in this mode says nothing about hardware speed.
- Mednafen (beetle-psx-libretro mednafen/psx, fetched): cache of 256
  entries of 4 halfwords, same index as the core; a miss costs 4 units of
  DrawTimeAvail, a textured polygon pixel 2, a semi-transparent sprite pixel
  1.5, triangle setup 46 + 180 (textured). The unit is 2 x the CPU clock
  (gpu.c: `DrawTimeAvail += sys_clocks << 1`), i.e. clk2x. The source calls
  these timings approximate ("Base timing is approximate, and could be
  improved", "FIXME, correct time").
- DuckStation (src/core/gpu.cpp, fetched): ticks are 2 x the CPU clock
  (`SystemTicksToGPUTicks: sysclk_ticks << 1`). Triangles: area x 2 when
  textured, no texture cache term at all. Rectangles: 4-bit textured 2 per
  pixel; 8 and 15-bit add a cache reload term (comment: "Texture cache
  reload every 2 pixels, reads in 8 bytes").
- JaCzekanski ps1-tests gpu/benchmark: measures DrawSync time on hardware,
  but the published screenshot is the flat-triangle mode only; no texture
  cache figure.
- MiSTer forum thread "MiSTer PSX Core: GPU Review, Technical Details &
  Benchmarks Against Real PSX" (misterfpga.org p=33860): returned 403, not
  read (not retried).
- Peip's PSX_MiSTer: no published texture miss timing found (one search).

No source gives a measured miss cost for the PS1 or the CXD8654Q, nor any
figure for rotated (column-walking) textures.

### 3.2 Estimates

Emulator models (both use the same cache geometry, so the same miss count):

- Mednafen: fill 9,886 + rectangles 2 x 89,296 + 4 x 7,680 misses + quad
  setup 452 + 2 x 60,945 pixels + 4 x 54,241 misses = 558,504 clk2x,
  8.25 ms per frame (quad 339,306, 5.01 ms).
- DuckStation: quad 121,890 and rectangles 297,600 clk2x (fill not
  counted), about 6.2 ms; it has no miss cost for polygons.

Board-anchored estimate (scratchpad hwest.py; Ray Crisis demo chunk 5700,
vblanks 1 to 57, L = 12):

- The calibrated core (alpha 4 release, D 13; within 0.3% of the board)
  spends 85.98 clk2x of texture miss time per destination read (the bench's
  unit of drawing work, docs/gpu_read_infl.md 1), 283.1 in all.
- The upstream fill (one qword per miss, the documented geometry) needs
  4.629 misses per destination read on the same stream.
- If the board's texture time equals the calibrated core's and it misses as
  often as the documented cache, a hardware miss costs
  85.98 / 4.629 = 18.6 clk2x (275 ns). Upstream at L = 12 measures 17.8.
- sianniv: non-texture time of the upstream L = 12 frame 264,405 clk2x plus
  61,630 misses x 18.6 = 1,409,137 clk2x = 20.8 ms (1.24 vblank periods);
  with the model's 61,921 misses, 20.9 ms.

Assumptions: board time scales with GPU time (the calibration's own
assumption, needs-review); the board misses like the documented cache (one
8-byte entry per miss); the per-miss cost is the same for both games. The
last is likely optimistic for sianniv: every pixel of the quad reads a
different VRAM line, and on the GPU's DRAM a new row costs more than a
column access in an open row, while Ray Crisis's misses are mostly along
lines. The frame exceeds 16.7 ms whenever a miss costs more than
(1,132,400 - 264,405) / 61,630 = 14.1 clk2x (208 ns).

### 3.3 Answer

On the only hardware anchor available (the Ray Crisis board calibration),
the CXD8654Q needs about 20.8 ms for this frame, so the real board is also
over one vblank period (two vblanks per drawn frame, if the game waits for
the next vblank after DrawSync). The emulator models (8.3 and 6.2 ms) are
under 16.7 ms, but neither is measured and DuckStation has no polygon miss
cost. Alpha 4 at 34.6 ms is 1.66 times the board-anchored estimate and
crosses two vblank periods (33.4 ms), so on alpha 4 a drawn frame would take
three vblanks where the board takes two. (Alpha 3 needed 19.6 ms only because
the watchdog cut the quad.) Whether the game logic slows with the drawing
rate is still open (i10 open question 1).

## 4. Options tried (simulation)

New generic TEX_FETCH_DIR (gpu_pixelpipeline, gpu, psx_top, psx_mister,
PSX.sv macro GNET_TEX_FETCH_DIR, default 0 = alpha 4 logic): with
TEX_FETCH_ROWS > 1, when a miss is on a lower texture row (page y and v)
than the previous miss, the fill covers this row and the rows above it
(v - 1, ...) instead of v + 1, ...; the VRAM reads and cache entries start
TEX_FETCH_ROWS - 1 rows up, still inside the cache block. 1 = any such
miss; 2 = only when the previous miss was on the same screen line (a span
walking up the texture); 3 = as 2 and at most 2 pixels right of the
previous miss. Not tried: a larger or set-associative cache (the board has
the documented 2 KB geometry and the estimate in 3 says it is already this
slow; a bigger cache would make sianniv faster than the board and Ray
Crisis faster than the calibration), and exempting these fills from
TEX_MISS_DELAY (arithmetic only: DIR at D 0 for these misses would be about
1.36 M - 29,100 x 13 = 0.98 M clk2x, 14.5 ms, faster than the estimate).

sianniv, L = 12, same stream and measure as 2:

| Config | Frame clk2x | ms | Periods | Quad clk2x | Misses / frame | clk2x / miss |
|---|---|---|---|---|---|---|
| alpha 4 release (D 13) | 2,344,820 | 34.62 | 2.07 | 2,066,738 | about 55,200 | 37.5 |
| ROWS 4, INFL 4, D 13 | 2,770,976 | 40.91 | 2.45 | 2,478,706 | about 56,300 | 45.1 |
| DIR 1, D 13 | 1,360,664 | 20.09 | 1.20 | 1,082,487 | about 29,100 | 37.5 |
| DIR 2, D 13 | 1,360,664 | 20.09 | 1.20 | 1,082,487 | about 29,100 | 37.5 |
| DIR 3, D 13 | 1,360,292 | 20.08 | 1.20 | 1,082,237 | about 29,100 | 37.5 |
| DIR 1, ROWS 4, INFL 4, D 13 | 998,270 | 14.74 | 0.88 | 705,732 | 16,227 | 45.1 |
| DIR 2, D 15 | 1,420,568 | 20.97 | 1.25 | 1,137,748 | about 28,900 | 39.6 |
| board-anchored estimate (3.2) | 1,409,137 | 20.80 | 1.24 | | 61,630 (1 qword) | 18.6 |

Ray Crisis demo chunk 5700, vblanks 1 to 57, L = 12 (busy = GPU non-idle
clk2x per destination read, the calibration metric; work = destination
reads, the GPU takes MAME's pacing so a faster GPU does more):

| Config | busy / dst | vs release | dst reads | misses / dst |
|---|---|---|---|---|
| alpha 4 release (D 13, calibrated) | 283.1 | | 227,584 | 2.265 |
| upstream | 277.5 | -2.0% | 232,222 | 4.629 |
| DIR 1, D 13 | 276.4 | -2.4% | 233,173 | 2.091 |
| DIR 2, D 13 | 278.6 | -1.6% | 231,309 | 2.177 |
| DIR 3, D 13 | 280.5 | -0.9% | 229,754 | 2.210 |
| DIR 2, D 15 | 283.5 | +0.14% | 227,267 | 2.182 |
| DIR 1, ROWS 4, INFL 4, D 13 | 260.9 | -7.8% | 243,065 | 1.466 |

Ray Crisis also has spans that walk up its textures, so every DIR variant
at D 13 makes it faster. What that means on the board, extrapolated from
the two hardware points of the calibration (bench D 9 to D 13 is 272.9 to
282.1, interpolated in the docs/gpu_read_infl.md 10 sweep, +3.4%; board
ratio 1.061 to 1.0748, +0.0138): about 0.004 of demo ratio per 1% of bench busy. DIR 2 at
D 13 would put demo 1 near 1.068, DIR 3 at D 13 near 1.071, DIR 2 at D 15
near 1.075 (board 1.078, alpha 3 1.0748). Linear extrapolation, needs the
board.

Checks:
- DIR 0 on this branch: Ray Crisis ddr3_frames.txt and vblank_busy.txt
  identical (59 of 59 lines) to the i10 release run B_fix_rel12, and
  frames_time.txt identical except its last, truncated frame (that run
  stopped at 59 vblanks); sianniv quad lengths identical to i10 f_rel12.
- Picture: sianniv VRAM after 8 vblanks (all six stream frames drawn) equals
  MAME vram_2705.bin (colour bits, 0 of 1,048,576 pixels differ) for DIR 1,
  2, 3, DIR 1 ROWS 4 and DIR 2 D 15, and for upstream L = 0. Ray Crisis at
  L = 0 (GPU keeps up), VRAM after frame 30: DIR 2 D 15 byte-identical to
  upstream.
- Elaboration: psx_top (NVC, ZN-2 release generics) with
  TEX_FETCH_DIR 2, QW 4, ROWS 2, INFL 2, D 15 elaborates.

## 5. Recommendation

Change, as a test build first: TEX_FETCH_DIR 2 with TEX_MISS_DELAY 15
(GNET_Z1FULLR macros GNET_TEX_FETCH_DIR=2, GNET_TEX_MISS_DELAY=15; on this
branch).

- sianniv band mode: 34.6 ms to 21.0 ms per frame in the bench, within 1%
  of the board-anchored 20.8 ms; two vblanks per drawn frame instead of
  three, the same as the estimate for the board.
- Ray Crisis: bench calibration metric +0.14% (283.5 against 283.1); the
  extra 2 cycles of delay give back what the direction rule saves on Ray
  Crisis's own upward walks.
- Pictures unchanged in both games against MAME or upstream.

Not recommended: DIR at D 13 (Ray Crisis 0.9 to 2.4% faster in the bench),
ROWS 4 with INFL 4 (Ray Crisis 7.8% faster; slower for sianniv without DIR),
leaving alpha 4 as is (1.66 times the board-anchored estimate for this mode).

Risks: STA (TEX_MISS_DELAY closed timing on 1 of 5 seeds; DIR adds a 10-bit
compare and the row offset in the miss path); the delay change needs the Ray
Crisis demo 1 hardware check; other games with upward texture walks get
slightly faster fills and slightly dearer delay (net effect not measured
beyond Ray Crisis and sianniv; needs-review, e.g. the i10 six-game seek
replays at L = 12). The prefetched rows above the miss carry the same
coherence caveat as the alpha 3 rows below it (a texture drawn into without
GP0(01) could be served from the cache earlier than on the board).

## 6. Build request

- Branch gpu-speed, revision GNET_Z1FULLR (alpha 4 settings plus
  GNET_TEX_FETCH_DIR=2 and GNET_TEX_MISS_DELAY=15).
- Hardware checks: Ray Crisis demo 1 drift ratio (board 1.078, alpha 3
  1.0748; expect about 1.075); sianniv band mode: drawn frame rate against
  the alpha 4 build (a frame-by-frame capture of the invaders' march: two
  vblanks per frame expected here, three on alpha 4); sianniv board footage
  for the same count would settle 3.3 directly.
- If the build misses timing, alpha 4 settings with GNET_TEX_FETCH_DIR=0
  are the fallback (DIR 0 is the alpha 4 logic).

## 7. Reproduce

- `sim/gpuinfl/build.sh` (M1_BUILD=<dir> builds a separate library;
  run.sh takes the same M1_BUILD), then for sianniv
  `sim/gpuinfl/run.sh <name> stream_2700_2705.txt vram_2700.bin 8 -gDUMPS=8
  -gGTIME=true -gVRAM_RD_LAT=12 -gTEX_QW=4 -gTEX_ROWS=2 -gREAD_INFL=2
  -gTEX_DELAY=15 -gTEX_DIR=2` and for Ray Crisis
  `sim/gpuinfl/run.sh <name> sim/m1/gtime/streams/demo_5700.txt
  sim/oracle/gtime_raycris_demo1/vram_5700.bin 60 -gGTIME=true` with the
  same generics (streams and VRAM images are game-derived, not committed).
- Busy per destination read: vblank_busy.txt column 2 over
  ddr3_frames.txt column 15, vblanks 1 to 57; misses: texmiss.txt.
- About 2.5 minutes per sianniv run and 15 to 25 minutes per Ray Crisis
  run on the Mac.

## 8. Issue #14 (2026-10-23): beta 1 tester report, every version slow

Report (cmdittmer, GitHub #14, beta 1): gameplay slow in every Space
Invaders version (player, invaders and shots); menus and attract not
noticed as slow.

MAME 0.288 (sim/oracle/i14_*, warm from ttgnirq/sianniv_cold, coin 32 s,
version picked with P1 Left/Right from 34 s, Start at 39 and 44 s): the
version carousel is Monochrome, Cellophane (default), Color, Upright,
Space Invaders Part II Upright, and to the left of Monochrome Space
Invaders 3D. In MAME frames 2990 to 3049 every 2D version draws the
emulated screen as the rotated 2C quad once per frame: Monochrome,
Cellophane, Color and Part II at 256 x 240 (vertices as in
docs/i10_triangle.md 2), Upright (the Earth background) at 192 x 240
(screen x 64 to 255, texture v 0 to 191). Space Invaders 3D draws no
textured polygon of 20,000 pixels or more.

Bench, merged onto beta-cand 223e69a (branch i14-speed, beta 1 settings:
QW 4, ROWS 2, INFL 2, TEX_CACHE_BIG 2, POLY_CLIP_X 1, L = 12; the
TEX_FETCH_DIR fill index widened to the cache index width CA, which is 10
with TEX_CACHE_BIG): GPU time per frame, one vblank 1,132,400 clk2x.

| Stream (MAME 3000 to 3005) | Beta 1 (D 13, DIR 0) | DIR 2, D 15 |
|---|---|---|
| Cellophane | 2,344,820 (34.6 ms, 3 vblanks) | 1,420,568 (21.0 ms, 2 vblanks) |
| Upright | 1,527,094 (22.5 ms, 2 vblanks) | 907,804 (13.4 ms, 1 vblank) |
| Ray Crisis demo 5700, busy per destination read | 282.4 | 283.3 (+0.3%) |

Pictures: VRAM after all six frames identical between the two settings in
both versions (0 pixels differ). Both differ from MAME's frame 3005 by the
same 406 pixels in Upright (x 8 to 63, outside the quad), so that is not
from this change. Cellophane figures equal the alpha 4 bench (section 4):
TEX_CACHE_BIG 2 keeps 4-bit pages on the 2 KB index and POLY_CLIP_X does
not cut this quad.

Inference (not measured on a board): the board-anchored estimate for
Cellophane is 20.8 ms (section 3), two vblanks a frame, so beta 1 runs this
mode at about two thirds of the board's rate and the change matches it. No
board estimate was made for Upright; the change puts it under one vblank.
Build: GNET_Z1FULLR seeds 5 to 8, FIT_OC 0.4 (patch on 223e69a in the
build folders).
