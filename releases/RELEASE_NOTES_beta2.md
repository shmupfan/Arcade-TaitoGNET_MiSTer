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
  demo stays within 0.3% of beta 1 in the same simulation. On my MiSTer
  (2026-11-02, Cellophane, the same start with no other input on both
  RBFs, invader march speed from screenshots every 0.5 s) the invaders
  move 1.4 times as fast as on beta 1: 0.60 of MAME's speed against 0.43.
  MAME draws in no time, so it is the upper limit, not the board; the
  board estimate above puts the board at the same two refreshes per drawn
  frame as beta 2. I have not measured Upright.
- **Shikigami no Shiro: side bars on a vertical screen and cut-off
  portraits
  ([#13](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/13)).**
  Shikigami no Shiro draws its game in 224 of the 240 lines the board
  sends, and its own test mode grid fills those 224 lines. A new OSD item,
  Video Settings > **Crop 224 lines** (On by default, shown only for
  Shikigami no Shiro), turns the top and bottom 8 lines into blanking, so
  over HDMI the 224 lines fill the screen as on an arcade monitor adjusted
  to that grid. On a CRT the sync and picture size are unchanged; the 16
  lines are only blanked to black, and as the game's own strips are
  already black or nearly black there, the option makes no visible
  difference on a CRT.
  Off shows all 240 lines, as MAME does. Only the two Shikigami no Shiro
  sets can crop; the other games draw 240 lines. The Shikigami MRAs in
  this release turn the option on; older MRAs do not show it. On my
  MiSTer with this RBF a screenshot of the Shikigami title (the picture
  the HDMI scaler receives) is 320 x 224, against 320 x 240 for XII
  Stag. On my CRT the picture stays stable with the option On and Off.
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
  beta 1, apart from the Space Invaders change above. On my MiSTer with
  this RBF (2026-11-02, same screenshot method as beta 1, 95 screenshots
  matched to MAME frames) Ray Crisis demo 1 takes 1.073 of MAME's time,
  against the board's 1.078. Two more board timings, checked on the same
  day with this RBF: Ray Crisis's "Prepares the start." loader takes 14.5
  to 14.7 s from a warm boot (board 14.69 s, MAME 12.34 s), and Night
  Raid's attract cycle, from one high score table to the next, takes 199
  to 200 s (board 200.0 s, MAME 178.3 s; the board and the core both draw
  the title screen at about half rate, 9.9 s against MAME's 5.0 s).
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
