# Crop 224 lines

OSD Video Settings item "Crop 224 lines" (status 122: On, the default,
Off), rtl/gnet/gnet_crop224.sv, wired in PSX.sv's video_aspect block. Only
the sets whose MRA sets bit 5 of the game configuration byte (ioctl index
7) crop and show the item (menu mask H4): shikigam and shikigama
(make_release_mras.py CROP224). Every other set never crops, by choice: the
crop is not offered where the game draws 240 lines. Asked for on Discord (2026-10-22): side
bars in Shikigami no Shiro on a vertical screen, and portraits cut off at
them. GitHub issue #13.

## 1. Evidence: which games draw 224 lines

MAME 0.288 oracle frames in gnet-mister `sim/oracle` (every run with
snapshots, up to 150 frames sampled per run, frames over 60% one colour
skipped). A "flat line" is a line of the native raster (a column of the
snapshot for a rotated game) with every dot but at most one the same
colour. Counted: runs of flat lines at both ends of the 240 lines (top
and bottom of the raster), at least 4 each. "35/16" is the boot screen
every game shows and is left out.

| Set | Frames | Flat lines at both ends (count) | Colour |
|---|---|---|---|
| shikigam | 355 | 8 and 8 (343) | per scene: (24,24,33) demo, (16,16,16), black |
| shikigama | 8 | 8 and 8 (8) | as shikigam |
| chaoshea | 76 | 8 and 8 (67), 21/8 (1), 10/8 (1) | black (74 of 74 checked) |
| raycris, raycrisj, nightrai, psyvaria, psyvarij, psyvarrv, xiistag, otenamih, spuzbobl, zooo, sianniv, gobyrc, mahjngoh | 1 to 698 each | none | |

Shikigami and Night Raid and XII Stag set the same mode and display range
(GP1(08h) 08000001 = 320 dots, GP1(06h) 06c58258 = 2560 GPU clocks,
GP1(07h) 07040010 = 240 lines; shiki_every and m1_*_60 gpu.log), so the
core shows Shikigami at the same size and aspect as the other vertical
games; the strips are in the picture the game draws. In the Shikigami
frames the strip covers every row (319 or 320 of 320), so anything drawn
there (portraits, the DEMONSTRATION banner) stops at its edge.

Other edge effects found, not this case: Space Invaders Anniversary and
Zooo leave flat columns at the left and right (dots, not lines) as part of
their layouts; Night Raid has 7 and 8 flat dot columns on 4 of 68 frames
(tutorial).

Second pass (2026-10-22, every released set without an earlier run): cold
MAME boots of 260 s, a snapshot each second, coin at 180 s, the same
count (sim/oracle/crop224_<set>). chaosheaj: 8 and 8 in 87 of 89 frames,
as chaoshea. No 8 and 8 run in flipmaze, kollon, mahjngoh, otenki,
raycrisj, shanghss, shangtou, soutenry, spuzboblj, usagi (a few menu or
title frames with other runs). Not reached in MAME: kollonc and otenamhf
(every boot, warm or cold, ends in 初期化中 then 正常に書き込みが終了しました,
"write complete, switch off", over four boots), gobyrc and rcdego (wheel
and trigger calibration before any game or test screen; needs analog
input), zokuoten (MAME 0.288 segfaults 5 s into a cold boot), zokuotena (no
ROM set here). Of the 31 released sets, 25 are checked and only the two
Shikigami sets draw 224 lines.

### Test mode crosshatch

Tourniquet (Discord, 2026-10-22): an operator sizes the monitor with the
game's test-mode grid, so crop when that grid is 224 lines and not
otherwise. MAME 0.288, warm NVRAM, S551:4 "Test Mode" On from power-up
(set through the DIP field's user_value; the oracle's set_value does not
change DIP switches), Button 1 on the first menu item (screen test):

| Set | Test menu, first item | Crosshatch extent (native) | Verdict |
|---|---|---|---|
| shikigam | 画面テスト (screen test), "画面の縦横比、色の確認" | outer grid lines on lines 8 and 231, red corner marks inside them; lines 0 to 7 and 232 to 239 black; dots 1 to 319 | 224 lines: crop |
| chaoshea | SCREEN ADJUSTMENT, "Adjust the ratio and color of the screen." | 640 dots, outer grid lines on lines 0 and 239 | 240 lines: no crop; its 8-line black bars in play are inside a 240-line picture |

Shikigami's attract logos (white TAITO and Alfa System screens) also keep
lines 0 to 7 and 232 to 239 black, so the game draws 224 lines on every
screen sampled. The G-NET BIOS test (S551:2, the generic "Service Mode",
menu Black Fill, Video Level, Color Bar, Hach Test, Transparency, 24bit
Gradation, Ball Sample, Sound Check) also has a hatch; MAME 0.288 crashed
(segfault) about 4.5 s into that menu in three runs, before the hatch could
be reached, so its extent is not checked. Inference, not evidence: an
operator setting up a Shikigami cabinet is more likely to use the game's
own screen test (the operator manual sends test mode to S551:4, S1 p.13)
than the BIOS one.

Not checked: sets with no oracle run (kollonc, otenamhf, usagi, flipmaze,
rcdego and the other sets in docs/gnet_set_survey.md), and how cabinets
were set up: no board or cabinet footage of Shikigami or Chaos Heat edges
was looked at. With the test-mode result above, cropping matches a monitor
adjusted to Shikigami's own grid, so the two Shikigami sets crop by
default and no other set can; Off shows the 240 lines the board outputs,
as MAME does.

## 2. Design

The first and last 8 drawn lines of a 240p frame become vertical blanking
in video_aspect (vblank high, RGB black). Every output takes video_aspect:
the debug overlay, arcade_video and the scandoubler, the rotation feed
(rot_gamma into screen_rotate, which then sizes the frame buffer 224 x
320), and VGA_DE into video_freak, so HDMI scales 224 lines with the
Original aspect (4:3, 3:4 rotated) applied to them: the picture fills the
screen, as an arcade monitor adjusted to fill the tube with the 224 lines
would. Sync is unchanged; on a CRT the 16 lines are black. 480i is never
cropped.

Line counting: the PSX video out changes vblank only inside hblank (320
dots: 30 of 106 hblank dots in; 256: 27 of 85; 640: 56 of 213) and draws
240 lines (sim/shell/run_vtrace.sh). The crop counts hblank falling edges
with vblank low from 0, and during hblank already uses the next line's
index, so its vblank edges fall on the first hblank dot after a drawn line,
a whole hblank before the next line starts (the framework's scandoubler
samples vblank at the hblank falling edge, docs/i11_scandoubler.md).

## 3. Verification

| Check | Result |
|---|---|
| sim/shell/run_crop224.sh (Verilator): run_vtrace.sh traces of modes 0, 1, 3 (256, 320, 640 dots 240p) and 4 (640 480i) through gnet_crop224 and video_aspect's rule, crop On and Off | PASS, all 8 runs. On, 240p: 224 lines per frame, source lines 8 to 231, full width on every line, 0 vblank edges outside hblank. Off: 240 lines, blank never high. 480i: 240 lines per field either way |
| tools/lint_psx.py GNET_Z1FULLR | 29 errors, all in gnet_hiscore.sv's hiscore pins; the same 29 on the unmodified tree (beta-cand 9621f0a) |
| Quartus fit, hardware | not done |
