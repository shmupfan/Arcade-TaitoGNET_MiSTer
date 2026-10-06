# M1: ZN-2 GPU (CXD8654Q) against the PSX_MiSTer GPU

Status: IN PROGRESS 2026-10-04.

## 1. Replay flow

- MAME 0.288 recording: `ORACLE_GPU_STREAM=1 ORACLE_VRAM_DUMPS=<frames>
  tools/mame/oracle_run.sh <set> <s> <dir>` gives gpu_stream.bin and
  vram_<frame>.bin (2 MB, MAME save item p_vram) plus the display registers.
- `tools/gpu_stream.py <bin> --text <txt> --maxframe N` converts the stream.
- `sim/m1/build.sh` compiles the PSX_MiSTer GPU and `sim/m1/tb_gpu_replay.vhd`
  with NVC 1.23 (three simulation-only patches, upstream RTL untouched).
- `nvc -H 256m -L . -e/-r tb_gpu_replay -gSTREAM=.. -gDUMPS=.. -gMAXFRAME=..`
  in sim/m1/work; speed about 13 s per emulated frame.
- `tools/vram_compare.py <core> <mame> <prefix>` compares the first 512 lines
  (the core GPU has 1 MB) and writes side-by-side and diff images.

## 2. First results (Ray Crisis warm boot, BIOS logos)

| Frame | Pixels differing (first 512 lines) | Note |
|---|---|---|
| 60 | 0 of 524,288 | identical |
| 30 | 51,525 (9.8%) in x 0-319, y 256-431 | Taito G-NET logo fade-in at a different step: frame alignment (checking neighbouring frames) |

## 2b. 2 MB GPU mode (VRAM_Y_BITS = 10), first checks

Implemented 2026-10-04 (commit c71a991): generic VRAM_Y_BITS on gpu and its
units (9 = upstream PS1 default, 10 = CXD8654Q), set from PSX.sv macro
GNET_VRAM_2MB. Replays of the Ray Crisis boot (stream_m1_300):

| Mode | Core 31 vs MAME 30 | Core 61 vs MAME 60 |
|---|---|---|
| 9 bits (PS1, regression) | 0 of 524,288 differ | 0 of 524,288 differ |
| 10 bits (ZN-2) | 0 of 1,048,576 differ | 0 of 1,048,576 differ |

Quartus (compile PC): revision GNET_M1_2MB (LEAN + 2 MB GPU) fits at 27,486
ALMs (LEAN 27,534, within fitter noise), all clocks meet timing (worst setup
+0.149 ns pll_hdmi, worst hold +0.172 ns), `builds/20261004_2333_m1vram`. The
switches-on PSX synthesis after the change is still identical to upstream V0
(`builds/20261004_2344_psxsw`).

The boot frames leave lines 512-1023 empty, so the gameplay checks (seek
replays from frame 2700, section 2c) are the real test of the upper half.

## 2c. Gameplay seek replays, all six games (2026-10-05)

Each replay starts from MAME's VRAM at frame 2700 of the 60 s warm-boot
run with a credit (`tools/gpu_stream.py --from 2700`, testbench generic
VRAM_INIT), runs 302 frames of the captured stream with VRAM_Y_BITS = 10,
and is compared with MAME's VRAM at frame 3000 (`tools/vram_compare.py`,
colour bits; the mask bit was compared separately and never differs).
Core frame 300 is the best match in five games (frames 298 to 302 checked);
in nightrai frames 298 to 302 are within 1.9% of each other (73,679 to
75,066 pixels) and the table uses frame 300 for all six.

| Game | Pixels differing (of 1,048,576) | 1 LSB | 2 LSB | more | Where | Upper half (lines 512-1023) |
|---|---|---|---|---|---|---|
| raycris | 740 | 10 | 4 | 726 | x 44-111, y 0-450 (UI textures drawn by the GPU) | identical (141,485 non-zero pixels) |
| shikigam | 11,861 | 11,859 | 0 | 2 | frame buffers | identical (145,154) |
| xiistag | 25,007 | 23,488 | 337 | 1,182 | x 704-1023, y 0-495 | identical (195,621) |
| nightrai | 74,714 | 19,041 | 12,497 | 43,176 | frame buffers (x 0-319, y 0-479) | identical (256,033) |
| psyvarrv | 114,295 | 77,688 | 16,402 | 20,205 | frame buffers (x 0-319, y 0-495) | identical (282,050) |
| psyvaria | 134,211 | 61,764 | 35,462 | 36,985 | frame buffers (x 0-319, y 0-495) | identical (317,797) |

("1 LSB" = largest 5-bit channel difference of the pixel.)

Readings:
- The 2 MB mode holds up in play: everything in the upper half (texture
  pages and CLUTs the games load there) is bit-identical after 300 frames
  of drawing, transfers and copies.
- No difference is in uploaded data; all are in pixels the GPU draws.
- Ray Crisis: 77% of the differing pixels have the core's value within one
  pixel in MAME's image, on the edges of rotated or scaled glyphs. This is a
  one-pixel sampling or edge-coverage difference, not misplaced content.
- Night Raid: the differences above 2 LSB sit on the rotated, scaled
  background texture (texel choice differs); the grid lines, sprites and
  text match. Screens shown side by side are the same picture. At 12
  random pixels differing by more than 2 LSB, the last primitive whose
  bounding box holds the pixel (`tools/prim_at.py`) is a textured quad in
  11 (GP0 2Ch flat textured 7, 3Ch Gouraud textured 4) and a textured
  rectangle in 1: texture coordinate interpolation across rotated quads.
- 1-LSB differences dominate shikigam and xiistag and are a large share of
  the rest. MAME 0.288's psxgpu.cpp has no dithering code (no match for
  "dither"); PSX_MiSTer dithers when E1 bit 9 is set, as the PS1 GPU does.
  Dither test: the same replays with dithering forced off
  (tb_gpu_replay generic DITHER_OFF = '1'), compared with MAME frame 3000:

  | Game | Differing, dither on | Differing, dither off | 1 LSB on / off |
  |---|---|---|---|
  | raycris | 740 | 740 | 10 / 10 |
  | shikigam | 11,861 | 7,507 | 11,859 / 7,505 |
  | xiistag | 25,007 | 24,175 | 23,488 / 22,915 |
  | nightrai | 74,714 | 73,477 | 19,041 / 18,100 |
  | psyvarrv | 114,295 | 99,349 | 77,688 / 65,687 |
  | psyvaria | 134,211 | 128,319 | 61,764 / 57,734 |

  Dithering accounts for 4,354 pixels in Shikigami and 573 in XII Stag;
  the rest of the 1-LSB group has another cause. In Shikigami the
  remaining pixels are single-channel (7,495 of 7,507), in fixed columns
  running the full height of horizontal colour gradients (the green text
  band and the blue background), core blue one lower or red/green one
  higher than MAME. That is a per-pixel colour interpolation (Gouraud
  step) rounding difference between the two rasterisers.
  `tools/prim_at.py` (primitives whose bounding box holds a pixel) ties
  them to two quads: a full-screen semi-transparent Gouraud quad (GP0 3Ah,
  colour FFFF00h at x 0 to FFFFFFh at x 320, so blue rises 0 to 255 across
  the screen), where row 300 differs at x = 10, 20, ... 160, one column per
  5-bit blue step; and an opaque Gouraud quad (38h) from black to green
  at x 23 to 72, the green text band. The two rasterisers place the
  colour steps of a Gouraud gradient one pixel apart. XII Stag's
  remainder is mostly core one higher than MAME, in up to three channels,
  in its frame buffers (x 704-1023). At 12 random differing pixels the
  last primitive drawn there is a semi-transparent textured rectangle
  (GP0 67h in 11, 64h in 1), and in frames 298 to 300 the game draws 354
  semi-transparent rectangles in blend mode 0 (E1 bits 5-6 = 0, half
  background plus half foreground). The two implementations round mode 0
  differently: MAME 0.288 halves each term and then adds
  (psxgpu.cpp p_n_f05 and p_n_*b05 tables: B/2 + F/2, each truncated),
  PSX_MiSTer adds and then halves (gpu_pixelpipeline.vhd 916-918,
  (B + F) / 2). Where both channel values are odd, the core is one higher,
  which is the pattern seen.
  Psyvariar Revision: at 12 random 1-LSB pixels (dither off) the last
  primitive is the same full-screen semi-transparent Gouraud quad (GP0
  3Ah, blend mode 1 = background plus foreground, low colours such as
  blue 10h to 40h), a tint over the whole scene: the Gouraud step placement
  again.

  Summary of the 1-LSB group: dithering (MAME has none) explains 0 to 37%
  of the differing pixels per game (none in Ray Crisis; Shikigami 4,354 of
  11,861; Psyvariar Revision 14,946 of 114,295); the rest is Gouraud step
  placement (Shikigami, Psyvariar) and blend mode 0 rounding (XII Stag).

Classification so far (needs-review until the dither test and hardware
evidence are in): the 1-LSB group is expected to be MAME's missing
dithering (MAME wrong); the texel and edge groups are rasteriser
differences where PS1 hardware tests (JaCzekanski/ps1-tests gpu/*, rank 1
for the shared rasteriser, evidence_sources.md) have to decide. Result of
those tests: section 2d.

Video output: `tools/video_compare.py` compares the testbench's captured
display (video_<f>.ppm) with MAME's snapshot. The displayed pictures match
in content; the pixel counts are dominated by the same dither and texel
differences, so VRAM is the better measure. Rotated games (Psyvariar) are
compared after undoing MAME's rotation.

Second window (frames 1500 to 1800, all six games, dither on): replay from
MAME's VRAM at 1500, compared with MAME frame 1800. Core frame 301 is the
best match in all six here (one frame later than in the 2700 window; the
seek start falls at a different point of the frame).

| Game | Differing | 1 LSB | 2 LSB | more | Upper half |
|---|---|---|---|---|---|
| raycris | 740 | 10 | 4 | 726 | identical (141,048 non-zero) |
| shikigam | 12,179 | 12,177 | 0 | 2 | identical (144,788) |
| xiistag | 39,696 | 38,683 | 238 | 775 | identical (195,479) |
| nightrai | 83,013 | 28,246 | 13,514 | 41,253 | identical (255,599) |
| psyvarrv | 140,982 | 39,505 | 31,712 | 69,765 | identical (281,795) |
| psyvaria | 136,014 | 47,597 | 38,871 | 49,546 | identical (317,796) |

The same picture as the 2700 window: the upper half and the mask bit never
differ, and all differences are in drawn pixels of the kinds classified
above (Ray Crisis again exactly 740 pixels in its UI texture area).

## 2d. PS1 hardware tests (JaCzekanski/ps1-tests, 2026-10-05)

Source: https://github.com/JaCzekanski/ps1-tests (MIT, commit f727802), tests
gpu/transparency, triangle, uv-interpolation, quad, lines, rectangles.
There is no toolchain or BIOS here, so `tools/ps1test_stream.py` restates
each main.c in Python and writes the GP0/GP1 words the PS-EXE sends, in the
replay format. Library calls follow the PSn00bSDK sources of the time
(82a441e, 2019-08-17, and afffa97, 2021-01-08; the functions used are
identical in both): SetDefDrawEnv sets tpage 0Ah with dither on, PutDrawEnv
sends E3, E4, E5 and E1 (no E2), LoadImage sends 01h, A0h and the data.
quad, transparency, lines and rectangles were committed with an older main.c
(draw area 320x240, white clear); each stream follows the version its
vram.png was committed with (commits in the tool's header). The drawing code
itself is the same in those versions and in f727802.

Method:
- Core: my own build in sim/m1/ps1t (gitignored; build.sh steps with the
  work directory moved), elaborated with VRAM_Y_BITS = 9, DUMPS = 2,3,
  MAXFRAME = 4. All words go in at frame 0, GP0 through the DMA port (the
  testbench sends a DMA word only while the FIFO is empty). VRAM at frames
  2 and 3 is identical in all six runs; frame 3 is compared.
- MAME 0.288: `tools/mame/ps1test_replay.lua` writes the same words to GP0
  and GP1 through the main CPU's address space at frame 10 of a raycris
  boot and dumps p_vram right after the last word (MAME draws inside the
  write; every stream clears lines 0 to 511 first). `tools/mame_gpu_model.py`,
  a Python transcription of the psxgpu.cpp paths these tests use, gives the
  same VRAM as those runs for quad, triangle, transparency and
  uv-interpolation (0 differing pixels in lines 0 to 511).
- Comparison: `tools/ps1test_compare.py <dump> <test> --detail`, lines 0
  to 511, 5-bit channels (every value in the six PNGs is the 5-bit value
  shifted left by 3), mask bit ignored. "1 LSB" = largest 5-bit channel
  difference of the pixel.

Pixels differing from vram.png (of 524,288):

| Test (image commit) | Core | MAME 0.288 |
|---|---|---|
| transparency (da6b472) | 0 | 0 |
| triangle (78ab568) | 0 | 36,769 (35,085 at 1 LSB, 1,684 more) |
| uv-interpolation (eb10e45) | 0 | 34,203 (18,343 at 1 LSB, 15,860 more) |
| quad (603a536) | 0 | 59,864 (59,002 at 1 LSB, 862 more) |
| lines (d1a63ee) | 64, all on the excluded segments | 3,352 (3,287 outside them) |
| rectangles (86a6f3c) | 0 | 1,188 (all at 1 LSB) |

lines: the last segment of the two Gouraud polylines ends at a colour the
test never sets (LINE_G4 r3, g3, b3 are stack contents), so those 66
pixels are excluded. rectangles: the loop blends semi-transparent
rectangles over the previous frame's, so the stream repeats the loop body
16 times; MAME's VRAM is the same after 8, 16 and 32 repeats.

The four questions from 2c, and dithering:
1. Gouraud colour step placement: core right. Triangles 1 and 2 (dither
   off): core 0; MAME 3,740 and 18,743 pixels at 1 LSB, with MAME's channel
   lower in 3,625 of 3,814 and 19,615 of 19,623 differing channels. G4 rows
   with dither off (uv-interpolation, y 256 to 511): core 0, MAME 3,886.
   MAME adds truncated 16.16 steps from the left edge (GouraudPolygon), so
   its colour steps land later than the hardware's.
2. Blend mode 0: core right, (B + F) / 2. quad draws mode 0 polygons (mode
   from PutDrawEnv's E1) over white (B = 31): where F = 31 (colour FFh) the hardware gives 31, MAME 30
   (B/2 + F/2); all 59,002 1-LSB pixels of quad have MAME lower.
   rectangles, mode 0 band: 1,188 pixels, all in semi-transparent
   untextured rectangles (62h, 63h, 6Ah, 6Bh, 72h, 73h, 7Ah, 7Bh), all MAME
   lower. transparency cannot tell the two formulas apart (F is 0 or 16,
   never odd) and both match it.
3. UV interpolation: core right. uv-interpolation draws one-line FT4 quads
   of width w = 0 to 255 with U 0 at the left and U 1 at the right, over a
   red texel (U 0) and a green one (U 1). The hardware turns green at about
   half the width (w = 9: 5 red, 4 green; w = 255: 128 red, 127 green);
   MAME draws every pixel of every row red (U truncated, 0 of 256 rows with
   a green pixel; 15,860 pixels). The core matches row for row.
4. Edge and fill rules: core right. quad (five semi-transparent quads
   sharing edges, then 16 abutting squares) and the three triangles: core 0.
   MAME gives 350 seam pixels of quad to a neighbouring quad (for example
   96 where the hardware has the centre quad, (15,15,15), and MAME the right
   one, (15,15,30)); on the triangle edges MAME leaves out 206, 432 and 206
   pixels the hardware draws and draws 204, 432 and 204 it does not.
- Dithering: core right. Triangle 3 and the G4 rows with dither on match
  the core bit for bit (dither pattern and which pixels dither); MAME, with
  no dithering, differs there in 12,602 and 14,457 pixels at 1 LSB. The
  dithered flat and Gouraud lines also match the core only (MAME 497 and
  476 pixels at 1 LSB). rectangles sets the dither bit in modes 1 to 3; the
  hardware does not dither rectangles and neither does the core.

Other MAME 0.288 deviations seen: fill (02h) takes the width as given, so
quad's 1023-wide clears leave column 1023 unfilled in MAME, while the
hardware image has it white (512 of the 862 larger differences);
line pixel placement differs on 1,658 pixels of the horizontal and
vertical lines and 80 of the circle. The core matches all of these.

Provenance of the images: not stated. README.md calls the suite "for
emulator development and hardware verification" (the GitHub description
says only "for emulator development"). The commits that added or changed
the six vram.png files (603a536, da6b472, 0f804df, 78ab568, eb10e45,
b0a94a8, 6f3e0f9, d1a63ee, 86a6f3c) do not say how they were captured,
and none of the 39 README.md versions does (GitHub API, 2026-10-05). So
"hardware" rests on the suite's stated purpose only; if an image came from
an emulator, a match shows agreement with that emulator. needs-review:
the author's statement or a console run.

Consequence for 2c, assuming the images are console captures and the
CXD8654Q keeps the PS1 rasteriser (evidence_sources.md): the Gouraud step
group (Shikigami, Psyvariar), mode 0 rounding (XII Stag), texel choice on
rotated quads (Night Raid; the test shows MAME's U truncation on unrotated
quads, the same code path), edge pixels (Ray Crisis) and dithering are
MAME 0.288 deviations; these tests give no reason to change the core.

Reproduce (from the repo root; nvc from sim/m1/ps1t/<test>):
`tools/ps1test_stream.py <test> sim/m1/ps1t/<test>/stream.txt`, then
`nice -n 15 nvc -H 256m -L .. --work=../work -r tb_gpu_replay
--exit-severity=failure --ieee-warnings=off`, then
`tools/ps1test_compare.py sim/m1/ps1t/<test>/vram_3.bin <test> --detail`.
MAME: `PS1T_STREAM=<stream.txt> PS1T_OUT=<out.bin> mame raycris -rompath
roms -video none -sound none -nothrottle -seconds_to_run 5
-autoboot_script tools/mame/ps1test_replay.lua` (output lines 512 to 1023
hold game data: keep it under sim/m1/ps1t).

## 2a. Upper VRAM is used by every game

MAME 0.288, warm boot, 60 s with a credit at 20 s, VRAM dumps every 300
frames (`sim/oracle/m1_<set>_60`). Non-zero pixels in lines 512-1023:

| Set | From frame | Pixels in lines 512-1023 (steady) |
|---|---|---|
| raycris | 1200 | 141,485 |
| psyvarrv | 1200 | 282,050 |
| xiistag | 600 | 195,621 |
| shikigam | 600 | 145,154 |
| nightrai | 600 | 256,033 |
| psyvaria | 1200 | 317,797 |

So the 2 MB VRAM mode is required for all six games; the PS1 GPU's 1 MB is
not enough once gameplay data is loaded.

Frame numbering: in the replay, core vblank N+1 corresponds to MAME frame N
(core frames 26-34 against MAME frame 30: only core 31 is identical).

## 3. GPU differences MAME implements for the CXD8654Q (type 2)

From [MAME 0.288 psxgpu.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/video/psx.cpp) (rank 5; no Sony document found):

| Item | MAME type 2 | PSX_MiSTer (PS1 GPU) | Change needed |
|---|---|---|---|
| VRAM | 1024 x 1024 (2 MB), all Y & 1023 | 1024 x 512 | 10-bit Y in every unit (fill, copy, CPU/VRAM transfers, rasterisers, texture fetch, video out) |
| Texture page (E1/poly tpage) | tx bits 0-3; ty = bit 4 (256) or bit 11 (512); ix bit 12, iy bit 13; GPUSTAT bit 15 from bit 11 | ty from bit 4 only (bit 11 = texture disable on PS1) | add the bit-11 page; check flip bits |
| Draw area E3/E4 | x bits 0-9, y bits 10-19 | same packing, Y 9 or 10 bits | 10-bit Y |
| Draw offset E5 | x bits 0-10, y bits 11-21 | same | none expected |
| Display start GP1(05h) | x bits 0-9, y bits 10-19 | y bits 10-18 | 10-bit Y |
| GP1(10h) info 3/4/5 | packs as above | PS1 | follow |
| GP1(09h) | logged "not handled" | PS1: texture disable allow | the BIOS writes 09000001 first; MAME ignores it |

Implementation plan: a generic on the GPU (2 MB mode) so the PS1 behaviour
stays the upstream default; VRAM address width to 21 bits in the DDR3 map.

## 4. Display timing (R14)

PSX.sv ties `syncVideoOut` to 0, so the video timing comes from
`rtl/gpu_videoout_async.vhd` on the 53.693175 MHz video clock (in the LEAN
build a fixed PLL, `rtl/gnet/pll_vid_fixed.v`), not from the CPU clock. A
change of the CPU rate (R1) therefore does not move the frame rate.

| Source | Clocks per line | Lines (240p) | Line rate | Frame rate |
|---|---|---|---|---|
| PSX_MiSTer async video out (RTL constants) | 3413 | 263 | 15.7320 kHz | 59.8173 Hz |
| MAME 0.288 psxgpu.cpp `refresh = 59.8260978565` | 3412.5 (my derivation: 53,693,175 / 59.8260978565 = 897,487.5 = 3412.5 x 263) | 263 | 15.7341 kHz | 59.8261 Hz |
| taitogn.cpp note (measured, by whom not stated) | | | 15.4333 kHz | 59.8260 Hz |

Readings:
- The note's 59.8260 Hz agrees with MAME's 3412.5 x 263 (59.8261) and is
  0.0088 Hz (147 ppm) above PSX_MiSTer's 3413 x 263. Over a 10-minute game
  that is about 5 frames. A crystal tolerance of 50 to 100 ppm cannot
  explain all of it, but one measured figure of unknown precision is not
  enough to change the RTL. Needs-review: a PCB frame-rate measurement
  (R14) decides between 3413 and an average of 3412.5 (for example
  alternating 3412 and 3413 per line).
- The note's 15.4333 kHz does not fit 59.826 Hz with 263 lines (it would
  need 258 lines) or the 53.693175 MHz clock with 3412.5 or 3413 clocks per
  line (15.73 kHz). I treat the horizontal figure as unreliable until a
  measurement confirms it.
- The 480i rate (MAME 59.9400523286) is 3412.5 x 262.5; PSX_MiSTer
  alternates 263 and 262 lines per field with 3413 clocks (59.9313 Hz). None
  of the six games uses it: in the 60 s streams of all six (and the Ray
  Crisis 40 s canary) every GP1(08h) write is NTSC, 240 lines, not
  interlaced. Widths: 320 in five games; Ray Crisis also 512 and 640
  (values 01h 902, 02h 2,364, 03h 129 writes; 00h only during the four
  BIOS writes at start).

## 5. GP1(10h) index 7, GPU type (2026-10-05)

The full-system Verilator simulation (branch fullsys-sim, docs/fullsys_sim.md
there) found the BIOS asks the GPU for its type with GP1(10h) index 7. MAME
0.288 answers m_n_gputype, 2 for the CXD8654Q (psxgpu.cpp, case 0x07 of
GP1(10h)); PSX_MiSTer's gpu.vhd ignored index 7 and left GPUREAD stale, so
the BIOS sent one extra E1h command. gpu.vhd now answers 2 for index 7 when
VRAM_Y_BITS = 10 (ZN-2 mode); PS1 mode is unchanged. The edit compiles and
elaborates in the M1 testbench; the extra E1h is expected to disappear in
the next system run (needs-review until rerun).

Open from the same run: after a GPU reset MAME sets the draw area bottom
right to 1023,1023 and gpu.vhd to 0, so the BIOS reads back a different
value and sends E4000000 instead of E40FFFFF (no visible effect seen;
needs-review against PS1 behaviour before changing).
