# Issue #10: Space Invaders Anniversary formation cut along a diagonal

Branch i10-triangle (from de4d29b, the alpha 3 release source, revision
GNET_Z1FULLR seed 8). Status: cause proven in the GPU replay bench, fix
committed on this branch, hardware build not yet made.

## 1. Symptom

Tester photos (alpha 3, RBF 20261015): in game, every invader on one side of
a straight diagonal through the formation is missing, invaders on the line
are cut in half, and two columns on the far side are drawn. The coloured
bands (p2) and the Earth background (p1) are drawn in full.

## 2. What draws the formation (MAME 0.288)

Capture: tools/mame/oracle.lua (gnet-mister main checkout copy, with
ORACLE_PLAN), set sianniv, warm start from
sim/oracle/ttgnirq/sianniv_cold, coin at 32.0 s for 0.1 s, Start at 35.0 s
and 40.0 s (the i1_si_C plan), ORACLE_GPU_STREAM=1, VRAM dumps at frames
2700, 2704 to 2707, 3000, 3060. The run is deterministic (vram_2700.bin is
byte-identical across two runs) and reaches the coloured band mode of photo
p2 (hi-score 8840 in both). The Earth mode of photo p1 was not captured.

Each in-game frame draws the whole screen into the back buffer (E3/E4/E5:
area and offset y 0 or 240, 256 x 240) with four GP0 commands from one DMA
list, then uploads the next frame's formation texture:

| Command | What |
|---|---|
| 02 fill | clear 256 x 240 |
| 66 (E1 081A) | textured semi-transparent rectangle 248 x 240, 4-bit, texpage x 640 y 768, CLUT 7F47 (the coloured bands) |
| 2C | flat textured opaque quad, colour 808080, 4-bit, texpage word 0812 (x 128, y 768 with the 2 MB bit 11), CLUT 7F40 (x 0, y 509) |
| 66 (E1 0859) | textured semi-transparent rectangle 248 x 240, texpage x 576 y 768, CLUT 7F46 (score text overlay) |
| 80 copy | 2 x 1 |
| GP0 01, A0 | clear texture cache, CPU to VRAM 64 x 256 halfwords at (128, 768): the formation texture for the next frame |

The 2C quad is the emulated Space Invaders screen (256 x 224 bitmap, the
formation, shields, bases and lives) drawn rotated by 90 degrees:

| Vertex | Screen (x, y) | Texture (u, v) |
|---|---|---|
| 0 | 255, 0 | 0, 0 |
| 1 | 255, 239 | 239, 0 |
| 2 | 0, 0 | 0, 255 |
| 3 | 0, 239 | 239, 255 |

u follows screen y and v runs from 255 to 0 as screen x goes from 0 to 255,
so each span walks down a texture column: every pixel is a different texture
row. In the 4-bit cache layout (64 x 64 texel blocks, 64 rows of 4 entries,
rtl/gpu_pixelpipeline.vhd tag_addr) the 256 rows of a span fall in four
blocks with the same entry indices, so every pixel of the quad is a texture
cache miss (61,440 pixels). The core splits the quad into triangle (v0, v1,
v2), the upper right half of the buffer, and (v2, v1, v3), the lower left
half (rtl/gpu_poly.vhd ISSUE, lines 559 to 582).

## 3. Core replay: the second triangle is abandoned by a watchdog

Bench: sim/gpuinfl (tb_gpu_infl, pipelined VRAM model, 2 MB VRAM), seek
replay from MAME frame 2700 (`tools/gpu_stream.py --from 2700`, VRAM_INIT =
MAME vram_2700.bin). The bench now reports every drawing-unit watchdog abort
and every polygon or rectangle longer than 262,144 clk2x (process at the end
of tb_gpu_infl.vhd).

Release generics (TEX_FETCH_QW 4, TEX_FETCH_ROWS 2, GPU_READ_INFL 2,
TEX_MISS_DELAY 13) at L = 12 (the measured idle DDR3 latency,
docs/gpu_read_infl.md 10) reproduce the photos: the first triangle and both
rectangles are drawn, the lower left triangle is missing except for a strip
at its start, and the bench logs `WATCHDOG poly abort` in every frame, with
the polygon unit out of IDLE for 1,048,528 clk2x.

Mechanism, rtl/gpu_poly.vhd (upstream PSX_MiSTer code, Robert Peip,
aca1036 and a295670, unchanged in this tree):

- line 252: `timeout : integer range 0 to 1048575`
- lines 451 to 459: `timeout` counts every clk2x cycle while `state /= IDLE`;
  at 1,048,575 it sets `error`, `state <= IDLE` and `done`.
- The second triangle of a quad is started from ISSUE without passing
  through IDLE (`nextQuad`, lines 559 to 582 and the line-end branch of
  PREPARELINE), so the counter covers both triangles of the quad together.

1,048,575 clk2x is 15.48 ms at 67.7376 MHz. A primitive that draws for
longer than that is cut off wherever the rasteriser is; for this quad that
is early in the second triangle. Real hardware has no such limit, and MAME
draws the whole quad.

Length of the formation quad (fixed RTL, so the length is not capped; one
frame of the same stream; clk2x):

| Generics | L = 0 | L = 12 | L = 24 |
|---|---|---|---|
| upstream | 335,312 | 991,985 | 1,651,570 |
| TEX_FETCH_QW 4 | | 1,149,477 | |
| QW 4, ROWS 2, INFL 2 (prefetch), D = 0 | | 1,365,056 | |
| TEX_MISS_DELAY 13 alone | | 1,700,943 | |
| prefetch, D = 9 | | 1,852,354 | |
| prefetch, D = 13 (alpha 3) | 1,412,054 | 2,066,738 | 2,725,554 |

Old-RTL runs at the same settings: upstream at L = 0 and 12 and posted
writes alone (GPU_READ_INFL 2) draw the whole formation; every
configuration with a length above 1,048,575 shows the cut. Upstream at L = 12
is 5.4% under the limit, which is why the GPU before the prefetch work
did not show it in the bench; upstream at L = 24 already cuts. The
prefetch makes this quad slower, not faster: its extra rows are the
following rows of the cache block (v + 1), while these spans walk v
downwards, and the 4-beat group fill costs beats for entries the next pixel
does not use. TEX_MISS_DELAY then adds 13 clk2x to each of the 61,440
misses.

Which build Lee saw without the triangle, or in which mode, is not known
(open question 2).

## 4. The game waits for the GPU before its frame-start reset

The frame-start writes in MAME (stop DMA2 with CHCR 401h, GP1(02),
GP1(01)) would also cut a slow primitive if the game issued them while the
GPU is drawing. A register trace with PCs (oracle.lua extension
ORACLE_IOWIN, frames 3000 to 3003) and a RAM dump at frame 3001 show the
Psy-Q libgpu calls:

- 8002EDF4 DrawSync(0): loops until the software queue is empty, DMA2 CHCR
  bit 24 is clear (8002EE6C) and GPUSTAT bit 26 is set (8002EE8C), with a
  240-vblank timeout (8002EF30, 8002EF64).
- 8002ECB8 ResetGraph(1 or 3): CHCR = 401h (8002ED80), GP1(02), GP1(01)
  (8002EDBC).

Every frame the trace shows DrawSync's two reads, then ResetGraph's writes.
On hardware the game therefore waits for the quad to finish; GP1(01) does
not cut it. The core's GPUSTAT bit 26 is 0 while a primitive is processed
(rtl/gpu.vhd 967 to 968, 1022 to 1023), so DrawSync waits on the core too.
The watchdog is the only thing in the path that abandons the quad.

## 5. Fix

rtl/gpu_poly.vhd PROCPIXELS: `timeout <= 0` whenever the span walker steps
one pixel (the existing `pipeline_stall = '0'` step condition). The watchdog
now measures cycles without a pixel step instead of the length of the whole
primitive. A real stall (a VRAM read that never returns, a pipeline that
never accepts) still trips it after 1,048,575 clk2x; a legal primitive is
finite (at most 1,024 pixels per line and 512 lines per triangle), so it
cannot run forever while stepping.

The change can alter behaviour only for a primitive that the old watchdog
would have aborted; in every other case `timeout` only feeds `error` and the
abort branch, so the GPU is cycle-identical. No generic: the default build
changes only where upstream would cut a primitive.

Not changed: gpu_rect.vhd and gpu_line.vhd have the same whole-primitive
watchdog (gpu_rect.vhd 123, 186 to 193; gpu_line.vhd 159, 203 to 210). No
captured game has a rectangle or line longer than 262,144 clk2x (bench
LONG reports), so they are left alone (needs-review: a full-screen 15-bit
textured rectangle at 640 x 480 could reach the limit on DDR3).

## 6. Results

### 6.1 sianniv, against MAME

Stream frames 2700 to 2705 (49,517 words) replayed to completion (30 bench
frames), VRAM compared with MAME vram_2705.bin (tools/vram_compare.py,
colour bits, 1,048,576 pixels):

| RTL, generics | Watchdog aborts | Pixels differing from MAME 2705 |
|---|---|---|
| old, release, L = 12 | 6 | 4,698 |
| fixed, release, L = 12 | 0 | 0 |
| old, upstream, L = 0 | 0 | 0 |
| fixed, upstream, L = 0 | 0 | 0 |

The fixed release replay is byte-identical to the fixed and old upstream
L = 0 replays.

### 6.2 Regression (old against fixed RTL, same bench and generics)

Bench sim/gpuinfl, the old RTL (de4d29b gpu_poly.vhd, library
sim/gpuinfl/pre) against the fixed RTL, same stream, VRAM image and
generics:

| Stream | Generics | Compared | Result |
|---|---|---|---|
| Ray Crisis attract demo chunk (sim/m1/gtime/streams/demo_5700.txt, MAME vram_5700.bin), 59 frames | release, L = 12 | ddr3_frames.txt, frames_time.txt, vblank_busy.txt (57 frames), VRAM at frames 30 and 59 | all byte-identical; no aborts, no primitive over 262,144 clk2x |
| same | upstream, L = 0 | same (59 frames) | all byte-identical; no aborts |
| raycris, shikigam, xiistag, nightrai, psyvarrv, psyvaria: M1 seek replays from MAME frame 2700 (m1_*_60 captures) | release, L = 12 | VRAM at frame 30; ddr3_frames.txt rows written before the runs stopped (55 to 58 vblanks per game) | all identical; no aborts, no primitive over 262,144 clk2x |
| sianniv frames 2700 to 2705 | upstream, L = 0 | VRAM at frame 30 | identical (6.1) |

The six-game runs were set to 61 frames and were stopped by a network
outage after their frame-30 dumps; the frames compared are the ones both
runs of a pair completed. As expected from section 5, the fix changes
nothing where no primitive reaches the old limit.

### 6.3 Frame time: the fix makes the full cost visible

GPU busy time per sianniv frame (bench frames_time.txt; one frame at
59.82 Hz is 1,132,400 clk2x, 16.72 ms):

| RTL, generics, L | clk2x per frame | ms |
|---|---|---|
| upstream, 0 | 574,364 | 8.5 |
| upstream, 12 | 1,332,478 | 19.7 |
| old, release, 12 (quad cut at the watchdog) | 1,326,692 | 19.6 |
| fixed, release, 0 | 1,660,526 | 24.5 |
| fixed, release, 12 | 2,344,820 | 34.6 |
| fixed, release, 24 | 3,030,388 | 44.7 |

The game calls DrawSync(0) before each frame (section 4), so a frame that
needs more GPU time than one vblank period stretches to the next vblank. If
the hardware latency is near L = 12, alpha 3 already needs about two vblank
periods per game frame for this mode, and with the fix about three. Whether
sianniv's game logic runs once per drawn frame (slower game) or catches up
from the vblank count is not known (open question 1). What the CXD8654Q
spends on this quad is not known either; it has the same cache geometry
(psx-spx), so it also misses on every pixel here.

## 7. Build request

- Branch i10-triangle, commit 53c95d2, revision GNET_Z1FULLR (seed 8,
  no other change; the RTL change is in rtl/gpu_poly.vhd only).
- Why: issue #10 fix (gpu_poly watchdog).
- Hardware checks: sianniv in game, coloured band mode and Earth mode,
  formation complete; compare game speed with MAME (invader march tempo or a
  stopwatch over a wave) on this build and on alpha 3; Ray Crisis demo 1
  timing unchanged (1.0748 on alpha 3).
- STA: TEX_MISS_DELAY fits closed timing on 1 of 5 seeds; a new seed may be
  needed even for this one-line change.

## 8. Open questions

1. Does sianniv run at MAME speed on alpha 3 and on the fixed build? The
   bench says the band mode frame needs 19.6 ms (alpha 3) and 34.6 ms
   (fixed) of GPU time at L = 12. If the game slows, the cost is in the
   texture miss path for vertical texture walks: TEX_MISS_DELAY 13 and the
   row prefetch both add to it (section 3 table); a direction-aware row
   prefetch, or a miss delay calibrated on more than the Ray Crisis demo,
   would be the next step. Needs board evidence (sianniv PCB footage) before
   changing the calibration.
2. Lee's earlier alpha 3 test screenshot without the cut: build and game
   mode unknown. Every prefetch configuration at L = 12 exceeds the old
   limit on this quad in the bench.
3. Earth mode (photo p1) not captured in MAME; its shields are drawn in the
   photo, so they come from another primitive in that mode.
4. GPUSTAT bit 26 is 1 for about one clk2x cycle between two queued
   primitives (rtl/gpu.vhd 1022 to 1023, then 967 to 968); a DrawSync poll
   that lands there would let ResetGraph's GP1(01) clear the rest of the
   list. Upstream behaviour, not seen, not tested.

## 9. Reproduce

- MAME: scratch copy of tools/mame/oracle_run.sh and oracle.lua (main
  checkout) with ORACLE_PLAN as above; the ORACLE_IOWIN and ORACLE_RAMDUMP
  extensions used in section 4 are in the session scratchpad, not committed.
- `tools/gpu_stream.py gpu_stream.bin --text s.txt --from 2700 --maxframe 2705`
- `sim/gpuinfl/build.sh`, then `sim/gpuinfl/run.sh <name> s.txt vram_2700.bin
  30 -gDUMPS=30 -gVRAM_RD_LAT=12 -gTEX_QW=4 -gTEX_ROWS=2 -gREAD_INFL=2
  -gTEX_DELAY=13`; `grep -E 'WATCHDOG|LONG' sim/gpuinfl/runs/<name>/run.log`.
- Old RTL for A/B: `git show de4d29b:rtl/gpu_poly.vhd` into rtl/, build with
  `M1_BUILD=pre sim/gpuinfl/build.sh`, restore, and run against library
  sim/gpuinfl/pre.
