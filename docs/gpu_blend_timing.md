# GPU drawing time on full-screen blended effects (XII Stag flash)

Branch gpu-blend (from beta-cand 167276d), 2026-10-21/22. Status: cause of
the XII Stag flash slowdown found and measured; three options implemented
behind generics (default off, defaults give the previous logic); candidates
compared per scene in the replay bench against board footage and the core
on hardware. No candidate passes every check: the held-out scenes fail
(section 7). Simulation only; no build, no hardware run of the new options.
Overnight follow-up runs are queued (section 11).

## 1. Answer

1. **Cause (XII Stag flash).** The flash draws 1 to 13 copies of one
   rotated, additive, 8-bit textured quad over the whole screen. Its spans
   walk diagonally down the texture and cross about 160 texture rows, 2.5
   times the 2 KB cache's 64. On that walk the release texture prefetch
   (4-qword group fill plus the next row) rewrites entries the next pixels
   still need: 3.06 times the fills of one-qword fills, 87% of the fetched
   qwords never read, each fill about 50 clk_2x (DDR3 latency, 8 beats,
   TEX_MISS_DELAY 13). Fills are 91% of the GPU's busy time in the flash at
   the release settings; the bench's 1 to 4-quad frames take 3.7 times as
   long as with one-qword fills. This matches the full-system sweep (D 0 to
   13 all still in the flash at 30 s): the prefetch geometry, not the wait.
2. **A second fault, with direct PS1 hardware evidence:** gpu_poly steps
   every pixel of a span outside the drawing area (it clips only at x = 0),
   one clk_2x each, without drawing it. A PS1 spends 0.758 and 0.515 of a
   full quad's time on one 1/4 and 1/2 off screen (ps1-tests `psx.log`);
   the core spent 1.000 on a quad cut by the drawing area's left edge. It
   costs 7% of XII's busy time and about 1% in Shikigami and Ray Crisis.
   Fixed behind POLY_CLIP_X; VRAM identical to upstream (section 5.2).
3. **Ruled out or minor** (section 4.2): cache clears, posted writes, mask
   bit, the wait's interplay with semi-transparency (ruled out); the
   next-row read (+8% on XII) and destination read-modify-write (6 to 17% of
   busy, but only 0.6% of the release XII slowdown) are minor.
4. **The board's fill cost.** From the KM4132G271B SGRAM datasheet (section
   6.3), one cache fill costs the board about 4 to 9 clk_2x of memory time;
   the core spends about 50 at the release settings. With a fill cost at that
   bound, Ray Crisis comes out too fast (about 1.054 against the board's
   1.078), so part of what TEX_MISS_DELAY 13 calibrated on Ray Crisis is not
   texture time.
5. **Best candidate so far** ("ch13": POLY_CLIP_X 1, TEX_CACHE_BIG 2 = an
   8 KB cache index for 8-bit and 15-bit pages only, release prefetch and
   TEX_MISS_DELAY 13 unchanged; the 8 KB index is DDR3 compensation, not a
   model of the board): XII flash 2.24 (board 2.03 to 2.07, release over
   5.8), Shikigami flash 1.85 (board 1.67, core on hardware 1.74 to 1.93),
   Shikigami demos and Night Raid 1.00. It **fails the held-out XII vortex**
   (2.28 against the board's 1.42) and **Psyvariar Revision** (2.00 on the
   frames run, board 1.00 to 1.02), and the bench does not reproduce the
   core's 1.08 to 1.10 at the end of Shikigami demo 3 (bench 1.000). These
   say the bench's paced model at L = 24 overstates GPU time in some scenes,
   or misses a term: the overnight runs test one candidate term, a GPU draw
   clock 1.476 times the PS1's (section 10).
6. **Area** (estimates, not fitted): TEX_CACHE_BIG about +280 ALMs and +3
   M10K, POLY_CLIP_X about +30 ALMs (section 9).

## 2. Evidence used, by rank

| Evidence | Rank | Used for |
|---|---|---|
| Board footage: XII Stag YouTube j-iAwFKdZNs (flash 18.47 to 20.34 s in the video); Shikigami, Psyvariar Revision, Night Raid and Ray Crisis demos; ratios to MAME measured by the coordinating session 2026-10-21 (Ray Crisis: docs/r1_speed_study.md) | 4, one board per game | targets |
| The core on hardware, current settings: Ray Crisis demo 1 upstream 1.126, prefetch D 0 1.045, D 9 1.061, D 13 1.0748 (docs/ACCURACY.md 2.4); Shikigami demos 1.010, 1.005, 1.092, flash at half speed (1.74 to 1.93), 1.07 to 1.10 at the end of demo 3 (my capture notes, 2026-10-21) | 2, my hardware | which bench latency reproduces the core |
| DDR3 latency probe on the DE10-Nano: idle read 12.4 clk_2x, 23.2 with writes in every free cycle (docs/ddr3_latency_probe.md 6, branch ddr3-latency-probe) | 2 | bench latency |
| Samsung KM4132G271B SGRAM datasheet, Rev. 2.4 (May 1998), pages 8 and 9 (alldatasheet.net mirror, html-pdf/37263, KM4132G271BQR-8); the board carries 2 x KM4132G271BQ-8 (docs/hardware_inventory.md) | 1 for the memory, 5 for how the GPU drives it | the board's fill cost |
| ps1-tests gpu/bandwidth `psx.log` (retail PS1, v2 GPU CXD8561 family, normal DRAM, 1 MB VRAM), reference/ps1-tests f727802 | 3 for the CXD8654Q (a related chip, not the board's) | primitive costs of a real Sony GPU; clipping |
| psx-spx, GPU texture caching and GPU versions (fetched 2026-10-21) | community spec | 2 KB cache geometry of the PS1 GPU; the CXD8654Q (v2b) is "arcade-only", "the differences between v2b and v2 are currently unknown" |
| MAME 0.288 (GPU instant) and the patched build that sets the CXD8661R clock (docs/r1_speed_study.md 6.1) | 5 | GPU command streams, VRAM images, CPU-only slowdown |
| Mednafen (beetle-psx-libretro 9bcc75d) and DuckStation (48a1028) GPU timing | 5, both call it approximate | cross-checks only; no parameter taken from them |

Correction for docs/ACCURACY.md 3.3: it says the CXD8654Q "has the same
texture cache geometry (psx-spx)". psx-spx documents the 2 KB cache for the
PS1 GPU and says of the CXD8654Q only that it is an arcade revision whose
differences from v2 are unknown. The board's cache geometry is not
documented.

Unresolved: the CXD8654Q's clock (50 MHz from post-0.288 MAME, rank 5, or
the PS1's 53.69 MHz). Where a result depends on it, both are given.

## 3. What the scenes draw

MAME 0.288 GPU streams from warm boots (the attract NVRAM of the footage
runs), replayed from a MAME VRAM image (`tools/gpu_stream.py --from`).
Oracle frame f is r1 frame f + 1 (checked on snapshot luminance).

- **XII Stag flash** (seek 1405, window stream frames 4 to 58 = MAME 23.57
  to 24.49 s): per frame a fill, 26 small 4-bit rectangles and 1 to 13
  copies of a quad (GP0 2Eh: textured, semi-transparent B + F, 8-bit CLUT,
  page x 64 y 768, UV 160 x 240) rotated by about 60 degrees and zoomed over
  the 320 x 240 area; 13 quads in 31 frames. Along a span v falls by about
  0.5 per pixel and u rises by 0.3; a span crosses about 160 texture rows.
  The quads overhang the drawing area by up to 190 pixels.
- **XII vortex and white burst** (seek 1465, frames 0 to 176 = 24.49 to
  27.45 s): mostly 8-bit textured layers (36,344 8-bit and 7,881 4-bit
  psx-spx misses per frame).
- **Shikigami demo 3 cyan flash** (seek 15250, frames 14 to 118 = 255.16 to
  256.91 s): 430 to 520 commands per frame, a radial burst of 32 untextured
  Gouraud semi-transparent triangles plus the textured sprites (75% of the
  textured pixels on 4-bit pages).
- **Shikigami demo 3 late** (seek 16286, frames 1 to 299 = 272.25 to
  277.25 s), demos 1 and 2 (seek 4040 and 8600, 300 frames each), Psyvariar
  Revision demo (seek 9000), Night Raid TUTORIAL (seek 7440).
- **Ray Crisis demo 1**: the existing calibration chunk (seek 5700), about
  1,560 commands per frame, textured Gouraud quads, all 4-bit.

Texture cache fills per frame (Python model of the psx-spx geometry,
scanline order, quads as two triangles, clipped to the drawing area;
a helper script, cachesim2.py, see section 13. Check: 30,368 fills for XII frame 5
against the bench's 30,456 with one-qword fills, and 123,186 4-qword fills
against the bench's 123,523):

| Scene (frames) | Textured px / frame | 2 KB psx-spx | 8 KB direct mapped | 2 KB, 4-qword group (release) | 8 KB, 4-qword group |
|---|---|---|---|---|---|
| XII flash (71) | 475,956 | 63,591 | 27,546 | 144,544 | 7,670 |
| XII vortex and burst (146) | 420,026 | 41,084 | 35,244 | 24,151 | 9,522 |
| Shikigami flash (149) | 201,431 | 21,958 | 13,926 | 14,899 | 7,646 |
| Ray Crisis chunk (61) | 213,586 | 19,448 | 17,146 | 12,582 | 10,942 |
| Shikigami demo 1 (301) | 108,777 | 4,805 | 4,210 | 2,603 | 2,237 |
| Shikigami demo 2 (301) | 106,004 | 10,639 | 8,864 | 4,611 | 3,851 |
| Psyvariar Revision demo (301) | 129,709 | 15,162 | 13,842 | 8,416 | 7,632 |
| Night Raid TUTORIAL (218) | 155,008 | 2,040 | 1,831 | 1,045 | 960 |

The release's group fill is the only setting that makes XII worse than the
plain cache; everywhere else it saves fills.

## 4. Where the core's time goes

### 4.1 Bench and breakdown

Bench sim/gpuinfl (tb_gpu_infl, pipelined VRAM model, 2 MB VRAM, NVC), with
these additions on this branch:

- `-gPACED=true`: a stream frame is released at the first vblank after the
  GPU has finished every earlier word, keeping MAME's frame spacing: the
  game's DrawSync(0), VSync(0) loop (sianniv: docs/i10_triangle.md 4; Ray
  Crisis: docs/gpu_draw_time.md 4.2). Vblanks over frames of a window = the
  predicted ratio to MAME when the GPU is the limit.
- frames_brk.txt: per stream frame, every busy clk_2x in one class
  (texture fill including TEX_MISS_DELAY, CLUT load, destination line read,
  write FIFO full, other), plus fills, beats, destination reads, write
  beats, span steps and drawn pixels by primitive class
  (`tools/blend_stats.py`).

Latency: the bench at L = 24 reproduces the core on hardware, L = 12 does
not (section 6.2), so the tables use L = 24 unless marked.

Per frame, busy clk_2x by component ("other pixel work" is span stepping
inside the area, setup, fills, uploads and write drain):

| Scene, setting | Frames | Busy clk_2x | Texture fills | Dest. reads | Steps outside area | Other pixel work | Fills | Texture beats | Dest. reads | Write beats | Drawn px |
|---|---|---|---|---|---|---|---|---|---|---|---|
| XII flash 1-4 quads, upstream | 2-5 | 1122440 | 755321 (67%) | 65330 (6%) | 83477 (7%) | 218190 (19%) | 24831 | 24831 | 1049 | 80444 | 193664 |
| XII flash 1-4 quads, release | 2-5 | 4176827 | 3809316 (91%) | 65510 (2%) | 83477 (2%) | 218402 (5%) | 75887 | 303550 | 1049 | 113565 | 193664 |
| XII 13-quad frames, proposal | 14-20 | 1969215 | 657736 (33%) | 325966 (17%) | 0 (0%) | 985392 (50%) | 12728 | 50913 | 4031 | 235738 | 944813 |
| Shikigami flash, release | 14-117 | 1345820 | 732091 (54%) | 126318 (9%) | 7757 (1%) | 469852 (35%) | 14553 | 58213 | 3559 | 93967 | 267399 |
| Shikigami flash, proposal | 14-117 | 1334622 | 732526 (55%) | 122048 (9%) | 0 (0%) | 470247 (35%) | 14532 | 58130 | 3559 | 94004 | 267399 |
| Ray Crisis chunk, release (unpaced) | 1-48 | 1355469 | 478103 (35%) | 121335 (9%) | 7980 (1%) | 724277 (53%) | 9477 | 37908 | 4112 | 87509 | 222538 |
| Shikigami demo 3 late, release | 1-298 | 828519 | 423750 (51%) | 27418 (3%) | 1787 (0%) | 364425 (44%) | 8449 | 33797 | 888 | 67829 | 185630 |

### 4.2 The leads, one by one

XII flash frames 2 to 5 (1 to 4 quads), L = 24, per frame:

| Setting | Busy | Texture fills (clk_2x) | Fills | Texture beats | Write beats |
|---|---|---|---|---|---|
| upstream (1 qword, no wait) | 1,122,440 | 755,321 | 24,831 | 24,831 | 80,444 |
| 1 qword, wait 13 | 1,450,176 | 1,083,078 | 24,831 | 24,831 | 80,444 |
| group + next row, wait 0 | 3,175,575 | 2,808,169 | 75,887 | 303,550 | 113,565 |
| release (group + next row, wait 13) | 4,176,827 | 3,809,316 | 75,887 | 303,550 | 113,565 |
| release without the next row (ROWS 1) | 3,863,307 | 3,495,762 | 75,702 | 302,809 | 113,381 |
| release with GPU_READ_INFL 1 | 3,863,307 | 3,495,762 | 75,702 | 302,809 | 113,381 |
| release, destination reads without latency | 4,150,699 | 3,803,366 | 75,887 | 303,550 | 113,565 |
| release, texture reads without latency | 2,319,864 | 1,952,930 | 75,887 | 303,550 | 113,565 |

1. **Prefetch waste: confirmed, the main cause.** The group fill makes
   3.06 times the fills (75,887 against 24,831) and 12 times the texture
   beats. Python model on the 13-quad frames: 436,904 fills and 3.47 M
   qwords per frame for 450,520 used (87% wasted), against 158,754 fills of
   one qword with the plain cache. Ray Crisis: the same policy cuts the
   fills from 17,514 to 7,929 (67% of the fetched qwords wasted, but each
   fill saves a DDR3 wait).
2. **Read slots: minor.** The next-row read adds 8% on XII (4.18 M against
   3.86 M). With GPU_READ_INFL 1 the extra row is not fetched at all, and
   the result equals ROWS 1 exactly: posted writes change nothing. A demand
   miss never waits behind a prefetch of another miss (one fill at a time).
3. **Cache clears: ruled out.** The core clears the texture cache after
   every GP0(01), fill, copy and upload (upstream rule, rtl/gpu.vhd 1059):
   10 per frame in XII, 11 in Shikigami, 45 in Ray Crisis. Ignoring them
   changes the fills by 0% (XII, Shikigami) and 1.6% (Ray Crisis).
4. **Destination read-modify-write: minor.** 6 to 9% of busy; with those
   reads at zero latency the release XII frame is 0.6% faster. The long fill
   stalls do fragment the pixel writes: the write combiner flushes a part
   qword after 15 idle cycles, so the same pixels take 113,565 write beats
   with the group fill against 80,444 with one-qword fills (+41% port
   traffic).
5. **Semi-transparency, mask bit: ruled out.** Every GP0(E6h) command in
   the three streams (parsed by packet, sampled frames) sets 0: no mask
   check, so no extra destination reads;
   TEX_MISS_DELAY only acts in the pipeline's fill state, and destination
   reads are issued by gpu_poly/gpu_rect before the span, not by the fill.
6. **Texture latency** is 45% of the release XII frame (4.18 M against
   2.32 M with free texture reads) and TEX_MISS_DELAY 24% (75,887 x 13).

DDR3 port at vblank 7 of the flash (L = 12): upstream 144,062 read and
115,947 write beats, port busy 57%; group fill at D 0 349,592 and 50,749,
76%: 2.4 times the reads for 0.44 times the pixels drawn.

## 5. The PS1 hardware log through the core

### 5.1 Primitive costs

ps1-tests gpu/bandwidth primitives (`tools/gpu_time_bench.py`, 4 per test,
320 x 240, every texel 0), ms per primitive and PS1 / core:

| Test | PS1 ms | upstream L0 | upstream L5 | upstream L12 | upstream L24 | release L12 | release L24 |
|---|---|---|---|---|---|---|---|
| cpuToVram | 1.938 | 2.268 (0.85) | 2.268 (0.85) | 2.268 (0.85) | 2.268 (0.85) | 2.268 (0.85) | 2.268 (0.85) |
| vramToVram | 3.040 | 1.449 (2.10) | 1.464 (2.08) | 1.496 (2.03) | 1.524 (1.99) | 1.479 (2.06) | 1.524 (1.99) |
| FillScreen GP0(2) | 0.193 | 0.284 (0.68) | 0.284 (0.68) | 0.284 (0.68) | 0.284 (0.68) | 0.284 (0.68) | 0.284 (0.68) |
| Rectangle | 1.208 | 1.134 (1.07) | 1.134 (1.07) | 1.134 (1.07) | 1.134 (1.07) | 1.134 (1.07) | 1.134 (1.07) |
| Rectangle (semitransparent) | 1.820 | 1.433 (1.27) | 1.452 (1.25) | 1.476 (1.23) | 1.523 (1.20) | 1.476 (1.23) | 1.523 (1.20) |
| Rectangle textured | 2.406 | 1.508 (1.59) | 1.870 (1.29) | 2.377 (1.01) | 3.255 (0.74) | 1.688 (1.43) | 1.846 (1.30) |
| Rectangle textured (semi) | 2.406 | 1.810 (1.33) | 2.190 (1.10) | 2.725 (0.88) | 3.643 (0.66) | 2.028 (1.19) | 2.233 (1.08) |
| Polygon quad | 1.228 | 1.143 (1.07) | 1.143 (1.07) | 1.143 (1.07) | 1.143 (1.07) | 1.143 (1.07) | 1.143 (1.07) |
| Polygon quad (semi) | 1.851 | 1.465 (1.26) | 1.502 (1.23) | 1.551 (1.19) | 1.640 (1.13) | 1.551 (1.19) | 1.640 (1.13) |
| Polygon quad textured | 6.347 | 2.328 (2.73) | 3.501 (1.81) | 5.139 (1.23) | 7.973 (0.80) | 3.414 (1.86) | 4.156 (1.53) |
| Polygon quad textured (semi) | 6.347 | 2.652 (2.39) | 3.861 (1.64) | 5.551 (1.14) | 8.470 (0.75) | 3.826 (1.66) | 4.649 (1.37) |
| Polygon quad (1/4 off screen) | 0.929 | 0.859 (1.08) | 0.859 (1.08) | 0.859 (1.08) | 0.859 (1.08) | 0.859 (1.08) | 0.859 (1.08) |
| Polygon quad (1/2 off screen) | 0.631 | 0.576 (1.09) | 0.576 (1.09) | 0.576 (1.09) | 0.576 (1.09) | 0.576 (1.09) | 0.576 (1.09) |

PS1 times: `psx.log` hblank counts / 15,732 Hz / 400. With the same cycle
counts at 50 MHz the PS1 column would be 7.4% longer.

- Untextured: the core is within 7% of the PS1 on opaque fill; the PS1 is
  1.13 to 1.27 times slower on semi-transparent primitives.
- Textured: with one-qword fills at L = 12 the core matches the PS1 on the
  4-bit rectangle (1.01) and is 1.23 times faster on the 15-bit quad. With
  the core's one clk_2x per textured pixel, the PS1 spends about 18 clk_2x
  per miss on the 4-bit rectangle (20 misses per line) and about 23 on the
  15-bit quad (64 per line). psx-spx lists the PS1 v2 GPU with normal DRAM.

### 5.2 Clipping (POLY_CLIP_X)

The same flat quad, 4 per test, L = 12, ms per quad and ratio to the full
quad (helper script clipbw.py, section 13):

| Test | PS1 | upstream | POLY_CLIP_X = 1 |
|---|---|---|---|
| full | 1.228 | 1.143 | 1.143 |
| 1/4 off screen (x < 0) | 0.929 (0.758) | 0.859 (0.752) | 0.859 (0.752) |
| 1/2 off screen (x < 0) | 0.631 (0.515) | 0.576 (0.504) | 0.576 (0.504) |
| 1/4 cut by the drawing area's left edge | no test | 1.143 (1.000) | 0.859 (0.752) |
| 1/2 cut by the left edge | no test | 1.143 (1.000) | 0.576 (0.504) |
| 1/4 cut by the right edge | no test | 1.107 (0.968) | 0.859 (0.752) |
| 1/2 cut by the right edge | no test | 1.001 (0.876) | 0.576 (0.504) |

The PS1 measured only x < 0; that it treats the drawing area's edges the
same way is an assumption (Mednafen and DuckStation clip to the drawing
area, rank 5). Pictures: VRAM identical to upstream (0 of 1,048,576 pixels)
after 20 XII flash frames and 41 Shikigami flash frames.

## 6. Evidence on the board's costs

### 6.1 CPU or GPU

MAME with the CXD8661R input clock at 82 MHz (the clock that reproduces
the board's Ray Crisis loader, docs/r1_speed_study.md 6.1) and at 70.2 MHz
(the core's loader), GPU instant:

| Scene | MAME stock | 82 MHz | 70.2 MHz |
|---|---|---|---|
| XII flash | 55 frames, 0.919 s | 55 frames, 0.919 s | |
| XII vortex and burst | 177 frames, 2.959 s | 177 frames, 2.959 s | |
| Shikigami flash | 105 frames, 1.755 s | 117 frames, 1.956 s (1.115) | 122 frames, 2.039 s (1.16) |

XII is GPU-bound on the board. The Shikigami flash is partly CPU-bound in
MAME's CPU model (which has no memory waits, so the board's CPU share may
be larger). Ray Crisis demo 1 drops no frames in MAME at 82 MHz
(docs/r1_speed_study.md 6.1).

### 6.2 Which DDR3 latency reproduces the core on hardware

| Setting | Core on hardware | Bench L = 12 | Bench L = 24 |
|---|---|---|---|
| Ray Crisis, busy per destination read: upstream | 1.126 | 277.5 | 361.6 |
| prefetch, D 0 | 1.045 | 249.8 | 297.0 |
| D 9 | 1.061 | about 273 | about 322 |
| D 13 (release) | 1.0748 | 283.1 | 334.4 |
| Shikigami flash, ratio (release) | 1.74 to 1.93, every frame at 2 vblanks | 1.41 (1.48 with the CPU of 6.1) | 1.87 |

L = 12 puts upstream below D 13 on Ray Crisis and the Shikigami flash at
1.41; L = 24 follows the hardware in both. The probe measures 23.2 when
writes fill the port, the GPU's situation while it draws.

### 6.3 The board's fill cost from the SGRAM datasheet

KM4132G271B, -8 grade (Rev. 2.4, page 8 AC characteristics, page 9
operating AC parameters): tCC 12 ns minimum at CAS latency 2 (8 ns at 3);
tRCD 16 ns; tRP 20 ns; tRAS 48 ns; tRC 70 ns; tRRD 16 ns; tCCD 1 clock;
block write cycle tBWC 1 clock; page 9 note 1: cycles = time / clock period
rounded up. Assumptions (not documented): the SGRAM runs on the GPU clock;
the two x32 chips form a 64-bit bus (or a 32-bit one, given as the upper
value); one cache entry is 8 bytes.

| Fill of one 8-byte entry | GPU clocks at 50 MHz | at 53.69 MHz | clk_2x at 50 | clk_2x at 53.69 |
|---|---|---|---|---|
| row open (READ, CAS latency 2, 1 or 2 beats) | 3 to 4 | 3 to 4 | 4.1 to 5.4 | 3.8 to 5.0 |
| other row open (PRE, tRP, ACT, tRCD, READ, CL 2) | 5 to 6 | 6 to 7 | 6.8 to 8.1 | 7.6 to 8.8 |

So the board's memory time per fill is about 4 to 9 clk_2x plus an unknown
in-GPU overhead (the core's own, at zero latency, is about 5 clk_2x per
fill: docs/gpu_speed_sianniv.md 2, upstream L = 0). XII's
fills change texture row every fill and a VRAM line spans 1 or 2 SGRAM
rows, so its fills are mostly row misses: about 7 to 9 clk_2x. A
destination span read costs the board one row opening (about 4 to 5
clk_2x) where the core waits the DDR3 latency (about 24 under load).
The core's release fill costs about 50 clk_2x on XII (3,809,316 / 75,887,
section 4.2), about 6 times the datasheet's row-miss figure, and there it
makes 2.75 times the fills.

## 7. Candidates and predictions per scene

Predicted ratio to MAME, paced bench at L = 24, GPU limits only (the CPU
effect of 6.1 is folded in for the Shikigami flash in brackets). "frames
x..y only" = the run reached its vblank limit before the window's end.
Board: footage ratios; core on hardware: the release build, measured.

| Scene | Role | Board | Core on hardware (release) | release | clip only | ch13 | 8 KB, D 22 | shadow cost 8 |
|---|---|---|---|---|---|---|---|---|
| XII flash, MAME 23.57 to 24.49 s | fit | 2.03 to 2.07 | over 5.8 (full-system sim, not hardware) | 12.8 (frames 4 to 12 only) | 12.8 (frames 4 to 12 only) | 2.24 | 2.53 | 2.44 |
| Shikigami demo 3 flash, 255.16 to 256.91 s | check | 1.67 | 1.74 to 1.93 | 1.87 (1.88) | 1.85 (1.86) | 1.85 (1.86) | 1.23 (1.33) | 1.21 (1.32) |
| Shikigami demo 3 late, 272.25 to 277.25 s | check | about 1.01 | 1.08 to 1.10 | 1.000 | | 1.000 | | |
| Shikigami demo 1, frames 4040 to 4339 | check | 1.005 (whole demo) | 1.010 (whole demo) | 1.000 (0 to 147) | | 1.000 (0 to 110) | | |
| Shikigami demo 2, frames 8600 to 8899 | check | 1.003 | 1.005 | 1.000 (0 to 148) | | 1.000 (0 to 150) | 1.000 | |
| Ray Crisis chunk, bench busy per destination read, hardware ratio by interpolation of 6.2 | fit (calibration) | 1.078 (whole demo) | 1.0748 | 334.4 (1.075) | 330.0 (about 1.070) | queued (rc_ch13u) | 337.7 (about 1.081) | 311.2 (about 1.054) |
| XII vortex and burst, 24.49 to 27.45 s | held out | 1.42 | not measured | 2.31 (0 to 154) | | 2.28 (0 to 156) | | |
| Psyvariar Revision demo, frames 9000 to 9299 | held out | 1.001 to 1.019 | not measured | | | 2.00 (0 to 162) | | |
| Night Raid TUTORIAL, frames 7440 to 7739 | held out | 1.000 | not measured | | | 1.000 (0 to 215) | | |

Settings: release = TEX_FETCH_QW 4, ROWS 2, GPU_READ_INFL 2,
TEX_MISS_DELAY 13. Clip only = release + POLY_CLIP_X 1. ch13 = clip only +
TEX_CACHE_BIG 2. 8 KB, D 22 = TEX_CACHE_BIG 1, D refitted to 22 so Ray
Crisis's bench metric matches the release (no clip). Shadow cost 8 =
TEX_CACHE_BIG 1, ROWS 2, a wait of 8 clk_2x per miss of a psx-spx 2 KB
shadow cache (the datasheet's row-miss fill), D 0, clip. The Ray Crisis
"hardware ratio" column maps the bench metric through the four hardware
points of 6.2 (piecewise linear); an inference, not a measurement.

Reading:

- XII flash: every option that stops the group fill thrashing on 8-bit
  pages brings it from over 5.8 to 2.2 to 2.5; ch13 is closest to the
  board. Clipping alone does not (the thrash dominates).
- Shikigami flash: options that keep the 2 KB index for 4-bit pages stay at
  the release value (1.85 to 1.88), close to the core on hardware (1.74 to
  1.93) and about 0.2 above the board. Options with the 8 KB index for
  4-bit pages drop it to about 1.3, below the board.
- Held out: XII vortex 2.28 against 1.42 and Psyvariar 2.00 against about
  1.01 are far off, in the slow direction, for the release and ch13 alike.
  Both scenes sit just above one frame of GPU time per frame in the bench,
  so a few percent decides between 1 and 2 vblanks. The core on hardware
  has not been measured in either scene; if it runs them near the board,
  the bench overstates GPU time there (the L = 24 latency, or the paced
  DrawSync model, would be wrong for them), which the Shikigami flash and
  Ray Crisis did not show.
- Shikigami demo 3 late: the core on hardware loses 1.0 to 1.2 s after the
  flash (1.08 to 1.10 at the end); the bench's GPU never exceeds a frame
  there (busy 12.2 ms per frame at the release settings). That loss is not
  GPU drawing time as the bench models it (CPU, DMA or something the
  replay leaves out); needs-review.

## 8. Proposal and what is implemented

Generics, all default 0 = the previous logic (byte-identical bench output
at the release settings on the Ray Crisis chunk: ddr3_frames, vblank_busy
and frames_time for 57 vblanks, before POLY_CLIP_X was added; a repeat with
the final RTL is queued as rc_rel12v2):

| Generic (macro) | What | Evidence rank | Recommendation |
|---|---|---|---|
| POLY_CLIP_X (GNET_POLY_CLIP_X) | spans clipped to the drawing area on both sides | PS1 hardware log for x < 0 (rank 3 for this chip); the drawing-area edges are an assumption (emulators clip there, rank 5) | adopt: removes up to 30% wasted steps per span, picture unchanged |
| TEX_CACHE_BIG (GNET_TEX_CACHE_BIG) 1 = 8 KB index for all pages, 2 = for 8 and 15-bit pages | fewer DDR3 fills; tag valid by an epoch with a sweep every 15 clears | none for the board (its cache geometry is undocumented); DDR3 compensation only | 2 as a test build for XII Stag; 1 not recommended (moves the Shikigami flash below the board) |
| TEX_SPX_COST4/8/15 (GNET_TEX_SPX_COST4/8/15) | a fixed wait per miss of a psx-spx 2 KB shadow cache | datasheet bound for the cost (6.3); psx-spx geometry assumed for the board | not recommended now: at L = 24 the real DDR3 fills still dominate, and with the datasheet cost it underpredicts Ray Crisis and the Shikigami flash |

Pictures (VRAM after the stream, against upstream at L = 0, 0 of
1,048,576 pixels differing unless noted): POLY_CLIP_X on 20 XII and 41
Shikigami flash frames; TEX_CACHE_BIG 1 with group fills; 8 KB + shadow
cost (78 differing before a fix: a real miss started while the shadow wait
held the pipeline let a group fill rewrite the entry the pixel in stage 1
was reading; no real miss now starts during that wait); the 8 KB release
policy at L = 24; the release group fill itself (20 XII frames). ch13 at L
= 24 is queued (vq_ch24).

Not proposed: TEX_MISS_DELAY changes. Whatever the draw clock turns out to
be (section 10), the calibration of 13 on Ray Crisis may include time that
is not texture fills.

## 9. Area (estimates, not fitted)

From the latest fit (builds/20261021_1450_z1fullr_seed9): the pixel
pipeline is 735 ALMs, its tag RAM an MLAB of 256 x 11 (101 ALMs: 80 of
MLAB, 19 of read multiplexer), the cache data 4 M10K.

- TEX_CACHE_BIG: tag RAM 1,024 x 15 in MLAB (about 32 MLABs and a 32:1
  read multiplexer, about +380 ALMs), data 1,024 x 64 (7 M10K, +3), the
  256 tagValid registers and their multiplexer removed (about -130), epoch
  and sweep (+30): about +280 ALMs, +3 M10K. Moving the tags to M10K with a
  read address one stage earlier would save most of the ALMs (a pipeline
  change, not made).
- TEX_SPX_COST: shadow tags 256 x 15 MLAB plus compare and counter, about
  +130 ALMs.
- POLY_CLIP_X: two 12-bit compares, two multiplexers in front of the
  interpolant multipliers, xSize arithmetic: about +30 ALMs; the
  multiplexer sits in the path into the DSP multipliers (timing to check).

The chip is at 39,087 of 41,910 ALMs (93%) in that fit; ch13 would add
about 310 (to about 93.9%).

## 10. Terms not absorbed into the texture parameters

### 10.1 Draw rate against the PS1 (absolute rates, ps1-tests)

From the table in 5.1, with memory at an SGRAM-like latency (L = 5): the
core draws opaque untextured primitives 1.07 times as fast as the PS1,
semi-transparent ones 1.23 to 1.25 times, VRAM copies 2.08 times; it fills
(GP0 02h) 0.68 times as fast. psx-spx: the PS1 GPU's drawing clock is the
CPU's system clock (about 67.7 MHz), the same rate as the core's clk_2x, so
these are per-cycle differences of the core, not a clock ratio.

### 10.2 The G-NET GPU clock

MAME 0.288 zn.cpp:94 clocks the CXD8654Q at 53.693175 MHz and its board
notes (zn.cpp:420 to 422) place a 53.693 MHz crystal by the CXD8654Q and a
100 MHz one by the CXD8661R. MAME master aab5dcadb6 (2026-08-18) makes
53.693175 MHz the GPU's video clock (vclk, "pin 192 on SGRAM GPU") and
clocks the CXD8654Q from 100 MHz / 2 (rank 5: emulator wiring, no drawing
model). If the draw engine runs on the CPU-side clock as on the PS1, a
100 MHz board would draw up to 100 / 67.7376 = 1.476 times as fast as a
PS1, and about 1.38 times as fast as the core on non-memory work. That is
inference to test, not evidence.

Release calibrations that could be absorbing such a ratio: TEX_MISS_DELAY
13 (fitted on Ray Crisis demo 1 alone), the choice of L = 24 for the bench
(fitted on Ray Crisis's ordering and the Shikigami flash), and the
prefetch settings (chosen on Ray Crisis).

Queued test (section 11): every clk_2x and clk1x in the bench 1.476 times
faster (bench generic GSCALE; the video clock and so vblank unchanged;
DDR3 latency kept in ns as 35 cycles), ch13 geometry with TEX_MISS_DELAY 0,
on XII, the Shikigami flash and demo 3 late, Ray Crisis and Psyvariar. If
one ratio puts all of them near the board, it is a hardware-motivated
single term; if not, it is ruled out at that value.

## 11. Overnight follow-up (2026-10-22)

| Run | Settings | Decides |
|---|---|---|
| rc_ch13u | ch13 on the Ray Crisis chunk, unpaced metric | whether ch13 keeps the Ray Crisis calibration (expected 330.0 as clip only, since every Ray Crisis page is 4-bit) |
| rc_rel12v2 | release at L = 12 | the final RTL with default generics is byte-identical to gpu-speed's rc_rel12_dir0 |
| vq_ch24 | ch13 at L = 24, 20 XII frames, VRAM dump | picture check of the candidate |
| rc_k148u, xii_k148, shf_k148, s3l_k148, psy_k148 | GSCALE 1.476, latency 35 cycles, ch13 geometry, TEX_MISS_DELAY 0 | whether one draw-clock ratio predicts Ray Crisis, both XII scenes' direction, the Shikigami flash and demo 3 late, and Psyvariar (compare with sections 6.2 and 7; Ray Crisis metric divide busy per destination read by 1.476) |

Read with `tools/blend_table.py sim/gpuinfl/runs rel24 ch13 k148` and the
rcm metric in section 12.

Results (bench, read 2026-10-22):

- rc_ch13u: busy per destination read 332.2 (release 334.4, clip only
  330.0), about 1.072 by the section 7 interpolation: ch13 keeps the Ray
  Crisis calibration.
- rc_rel12v2: byte-identical to gpu-speed's rc_rel12_dir0, so the new
  generics at their defaults give the previous logic.
- vq_ch24: VRAM after 120 frames identical to the earlier candidate run
  vq_g24 (no upstream dump at that frame).
- GSCALE 1.476 (one drawing clock ratio, TEX_MISS_DELAY 0): XII flash
  1.673 (board 2.03 to 2.07), Shikigami flash 1.019 (board 1.67), Ray
  Crisis faster than the board, Psyvariar 1.557 (board about 1.01). One
  ratio overshoots three scenes and still misses Psyvariar, so it does not
  explain the board's figures by itself.

## 11a. The core on hardware (2026-10-22)

0.5 s screenshots on my MiSTer matched to MAME 0.288 every-frame
snapshots (the section 2 method), release (beta candidate settings) and a
test build of ch13 (GNET_Z1FULLR plus GNET_POLY_CLIP_X=1 and
GNET_TEX_CACHE_BIG=2, seed 8), core time over MAME time:

| Scene | Release | ch13 | Board | Bench release / ch13 |
|---|---|---|---|---|
| XII flash | 7.30 (7.02 to 7.62) | 1.59 (1.32 to 2.01) | 2.03 to 2.07 | 12.8 / 2.24 |
| XII vortex | 1.71 (1.59 to 1.80) | 1.64 (1.50 to 1.77) | 1.42 | 2.31 / 2.28 |
| Ray Crisis demo 1, demo_drift | 1.0857 | 1.0765 | 1.078 | |
| Ray Crisis demo 1, first to last frame | 1.073 (1.055 to 1.091) | 1.068 (1.055 to 1.080) | 1.078 | |
| Psyvariar frames 9000 to 9299 | 1.18 (1.10 to 1.30) | 1.175 (1.10 to 1.30) | about 1.01 | / 2.00 |
| Psyvariar whole demo | 1.040 | 1.041 | 1.001 to 1.019 | |
| Shikigami demo 3 flash | 1.88 | 1.87 | 1.67 | 1.87 / 1.85 |
| Shikigami demos 1, 2, 3 | 1.010, 1.005, 1.092 | 1.010, 1.005, 1.090 | 1.005, 1.003, 1.045 | |

- ch13 fixes the XII flash and changes nothing else beyond the
  measurement ranges; the flash is now about 0.4 s shorter than the board.
- The bench overstates GPU time in the vortex and Psyvariar (hardware 1.71
  and 1.18 against bench 2.31 and 2.00), so those bench failures are the
  bench's, not ch13's.
- The release's demo_drift figure (1.0857) is above the 1.0748 measured on
  the alpha 3 release build; not explained.
- MAME 0.288 with a lower CPU clock reproduces the core's late Shikigami
  demo 3 at 67 to 69 MHz and Psyvariar at 59.5 to 61 MHz (100 MHz
  nominal). The scenes need different clocks, so the remaining gap there
  is more likely a workload-dependent CPU cost (waits on memory or on the
  GPU) than the clock (inference).

## 12. Unresolved

1. The CXD8654Q's draw clock (10.2) and its texture cache geometry (psx-spx:
   v2b differences unknown).
2. Why the bench overpredicts the XII vortex and Psyvariar: the core on
   hardware in those scenes would settle whether the bench or the board
   model is wrong (a capture like the Shikigami one).
3. The core's extra 1.0 to 1.2 s in Shikigami demo 3 after the flash is not
   GPU drawing in the bench (7, last point).
4. Ray Crisis: with fills at the SGRAM bound the core is about 2.4 points
   faster than the board; the missing time is unlocated (per-primitive
   cost, CLUT loads, DMA or CPU).

## 13. Reproduce

- MAME 0.288 GPU streams: `tools/mame/oracle_run.sh` (main checkout) with
  ORACLE_GPU_STREAM=1 and ORACLE_VRAM_DUMPS, NVRAM from the attract runs;
  `tools/gpu_stream.py <bin> --text <txt> --from F --maxframe N`.
- Bench: `sim/gpuinfl/build.sh`, then `sim/gpuinfl/run.sh <name> <stream>
  <vram> <vblanks> -gPACED=true -gVRAM_RD_LAT=24 -gTEX_QW=4 -gTEX_ROWS=2
  -gREAD_INFL=2 -gTEX_DELAY=13 [-gTEX_BIG=1|2] [-gCLIPX=1] [-gSPX4=..]
  [-gGSCALE=..]`; job lists in sim/gpuinfl/runs/_queue (worker.sh).
- Summaries: `tools/blend_stats.py <run> <first> <last> [--frames]`,
  `tools/blend_table.py <runs> <suffix...>`; Ray Crisis metric: busy over
  destination reads, vblanks 1 to 57 (vblank_busy.txt column 2,
  ddr3_frames.txt column 15).
- Cache models and helper scripts (cachesim2.py, waste.py, counts.py,
  cpucomb.py, clipbw.py) are not in the repository: they read my local
  capture folders. The bench and tools/blend_*.py reproduce the figures.
- MAME CPU clock runs: `MAME=<MAME 0.288 G-NET build>
  ZN2_CPU_HZ=82000000 tools/r1/r1_run.sh <set> <s> <nvram> <out>`.
