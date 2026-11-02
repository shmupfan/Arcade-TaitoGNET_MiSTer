# Taito G-NET core, beta 2

Core: `Arcade-TaitoGNET_20261102.rbf` (md5 `1a7b90cd8d64167a596a1e42023ef63a`, see
[README.md](README.md)).

Beta 2 is beta 1 plus the fixes for the issues reported against it. The
accuracy questions I know of are listed in the README's Known issues and
in docs/ACCURACY.md; test reports, and board footage most of all, are what
can settle them.

## Fixes

- **Space Invaders Anniversary runs too slowly in the 2D versions
  ([#14](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/14)).**
  In every 2D version the game draws the emulated Space Invaders screen
  as one big rotated picture each frame. Its texture is read walking up
  the texture columns, so almost every pixel missed the graphics chip's
  texture cache. Beta 1 needed about 34.6 ms per frame for Cellophane
  (three screen refreshes per drawn frame) and 22.5 ms for Upright. Beta 2
  fills the cache in the direction the drawing walks. In my graphics
  simulation this brings Cellophane to 21.0 ms (two refreshes per frame)
  and Upright to 13.4 ms (one). The only estimate I have for the real
  board, 20.8 ms for Cellophane, also means two refreshes per frame. It
  comes from the Ray Crisis board timing, not from footage of this game.
  The pictures are the same pixel for pixel, and Ray Crisis's
  demo stays within 0.3% of beta 1 in the same simulation. TO CONFIRM
  invader speed on my MiSTer (Cellophane and Upright).
- **Shikigami no Shiro: side bars on a vertical screen and cut-off
  portraits
  ([#13](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/13)).**
  Shikigami no Shiro draws its game in 224 of the 240 lines the board
  sends, and its own test mode grid fills those 224 lines. A new OSD item,
  Video Settings > **Crop 224 lines** (On by default, shown only for
  Shikigami no Shiro), turns the top and bottom 8 lines into blanking, so
  over HDMI the 224 lines fill the screen as on an arcade monitor adjusted
  to that grid. On a CRT the 16 lines are black and the sync is unchanged.
  Off shows all 240 lines, as MAME does. Only the two Shikigami no Shiro
  sets can crop; the other games draw 240 lines. The Shikigami MRAs in
  this release turn the option on; older MRAs do not show it. TO CONFIRM
  HDMI and CRT on my MiSTer.
- **Zooo button names
  ([#15](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/15)).**
  Button 2 is now called Binoculars and button 3 Unused.
- **HDMI timing.** One part of the HDMI scaler missed timing in many
  builds of this release's code. It now takes one more clock, with the
  same picture (checked in simulation for progressive, framebuffer, bob
  and weave video). It does not change anything you see; it lets the
  release build meet timing on every clock.

## Not changed

- The slowdown calibration (Ray Crisis demo 1 against the board, about
  1.077 of MAME's time on beta 1, board 1.078) and the other games' timing are as in
  beta 1, apart from the Space Invaders change above. TO CONFIRM Ray
  Crisis demo 1 on my MiSTer.
- XII Stag's first boss explosion still slows down a lot on the core. I
  have traced it to the graphics chip's texture reads, which take about
  33 ms per frame there in simulation, and to the game making the CPU wait
  for the drawing on every flash frame. How fast a board draws it is not
  known: I have found no board footage of it. A small test program to
  measure the texture read cost on real hardware is in progress.

## Install

Copy `Arcade-TaitoGNET_20261102.rbf` to `/media/fat/_Arcade/cores/` and the
MRAs as in [README.md](README.md); remove `Arcade-TaitoGNET_20261022.rbf`.
The zips and the NVRAM files from beta 1 work unchanged.
