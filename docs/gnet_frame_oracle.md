# Frame oracle: MAME frame hashes for automated comparison

Status: 2026-10-05. Purpose: compare the core's video with MAME's
automatically, frame by frame, without saving images. The format is shared
with the fullsys harness (fullsys-sim 6963642, tb_fullsys.cpp writes
`<run>/frames.tsv`; sim/fullsys/frame_ref.py is its pure-Python reference).
The full field definitions are in the docstring of `tools/frame_hash.py`.

## Files

| What | Where (gitignored, game-derived) |
|---|---|
| Shikigami warm boot, 0 to 60 s, 3,590 frames | sim/oracle/frames/shikigam_warm60/{frames,samples,changes}.tsv |
| Ray Crisis warm boot, 0 to 60 s, 3,590 frames | sim/oracle/frames/raycris_warm60/{frames,samples,changes}.tsv |
| Psyvariar Medium Unit, XII Stag, Night Raid warm boots, 0 to 60 s | sim/oracle/frames/{psyvaria,xiistag,nightrai}_warm60/ |

Both runs use the post-copy flash images with no EEPROM file and an
unmodified card (what the warm-boot MRA loads), no input before 40 s, then
coin at 40 s, start at 42 s, and fire with left/right movement from 45 s.

## frames.tsv

One row per frame: frame, t_s (emulated seconds since power-on at the
frame's vblank start), w, h, crc555, crc555_x1, ahash, dhash, luma.

- **Integer arithmetic:** hashes use 5-bit channels and integer luma Y =
  299 r5 + 587 g5 + 114 b5, so both sides agree bit for bit.
- **crc555_x1:** covers MAME columns 0..w-2 and core columns 1..w-1. The
  core's frame starts at the GP1(05h) x and MAME's at x + 1 (fullsys
  doc D3).
- **Pair rows by t_s, not by frame number.** The core counts frames from
  power-on, including the SDRAM init.

Check: I converted five MAME frames (320 x 240 attract frames, and black
256, 512 and 640 x 240 frames) to PPM. `frame_hash.py ppm` and
`frame_ref.py` gave identical rows (w, h, crc555, crc555_x1, ahash, dhash,
luma).

## Use

```
tools/mame/frame_oracle.lua      MAME side: raw frames + times.tsv (FRAME_OUT, FRAME_STOP, FRAME_COIN_AT)
tools/frame_hash.py mame <dir>   raw frames -> frames.tsv (deletes the raw frames)
tools/frame_hash.py events <frames.tsv> <out>   samples.tsv (every 30th frame), changes.tsv
tools/frame_hash.py diff <mame frames.tsv> <core frames.tsv>
tools/frame_hash.py first <core frames.tsv> <mame frames.tsv> [--tmax 40]
```

`first` reports the first core frame with no MAME frame of the same
resolution and an ahash within 10 bits inside ±0.5 s (timing or content),
and inside ±10 s (content, beyond a lag). It also counts core frames whose
crc555_x1 equals the nearest MAME frame's. The core lags MAME by about 2.7 s
by the Shikigami CAT702 point (full-system run), so the ±0.5 s result mostly
measures that lag. Before comparing, check the core run's progress.log for
"WATCHDOG RESET (applied)"; frames after it belong to a second boot.

`diff` pairs every 30th MAME frame with the nearest core frame in time.
It prints the ahash Hamming distance (match at 10 or less) and whether
crc555_x1 agrees. It then pairs the change events in order and gives each
time offset.

A change event is a run of consecutive frames whose dhash differs from
the previous frame's in 12 or more bits, or whose resolution changes.

- **Shikigami** gives 12 events: the first frames, the prepare bar at
  2.87 s, the black screen at 5.13 s, NOTICE at 7.91 s, TAITO at 10.91 s
  and its fade at 12.97 s, the story scenes at 19.42 and 20.78 s, coin at
  40.23 s and how-to-play at 45.87 s. The fade into the Alfa System logo
  (about 14 to 16 s, mostly white) stays under the threshold.
- **Ray Crisis** gives 57 events. They include the mode changes to
  256 x 240 at 15.51 s, 640 x 240 at 18.35 s (NOTICE), 512 x 240 at
  20.53 s (TAITO) and 320 x 240 at 22.15 s.

Changes inside dark scenes can fall under the threshold.

Known difference: MAME shows the BIOS screens at 320 x 240, and the core
at 256 x 239 (fullsys harness). Their crc555 cannot agree there; ahash
still compares.
