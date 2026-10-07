# M4 release shell (branch gnet-shell)

Status: 2026-10-05, branch gnet-shell from gnet-cpu50 (048cf9e). RTL and
benches done; no Quartus run. Revision GNET_Z1SHELL (target `z1shell`)
is ready to queue.

The shell work of the minimum standard (memory note
feedback_core_minimum_standard) for the G-NET core: DV1 integer pixel
clock, vertical games (rotation option bits, Flip Screen), pause, black
picture with running sync, volume, keyboard keys, and the OSD. Every
change is behind the macro GNET_SHELL (set only in GNET_Z1SHELL.qsf), so
GNET_Z1, GNET_Z1_CPU50 and the upstream PSX revision build as before.

## 1. Files

| File | What |
|---|---|
| PSX.sv | GNET_SHELL blocks: OSD, game configuration byte (ioctl index 7), MAME keys, pause button, watchdog mask, sync keeper and volume instances, Flip Screen to the GPU's rotate180, game hblank and 4:3 aspect, rotation wires `gnet_rot_en` / `gnet_rot_ccw` |
| rtl/gnet/gnet_sync_keeper.sv | substitute black raster while the core's video timing is stopped |
| rtl/gnet/gnet_volume.sv | OSD volume at the final mix |
| rtl/gnet/gnet_crt_pos.sv | OSD CRT H/V position (section 8) |
| rtl/gnet/zn2_io.vhd, zn2_board.vhd, rtl/psx_top.vhd, rtl/psx_mister.vhd | EEPROM copy for the NVRAM save and its ports `zn_nv_*` (section 9), unused (and removed in synthesis) outside GNET_SHELL |
| GNET_Z1SHELL.qsf | GNET_Z1_CPU50 plus `GNET_SHELL=1`, the shell files and the debug overlay files |
| tools/pc_build.sh | target `z1shell` (DIR gn_z1shell, TASK gnz1shell) |
| sim/shell/ | tb_dotclock.vhd + run_dotclock.sh (NVC), tb_shell.sv + run_shell.sh, tb_crt_pos.sv + run_crt_pos.sh (Verilator) |
| sim/zn2/tb_zn2_io.vhd | NVRAM copy checks added |
| tools/lint_psx.py | from ddr3-arb-int, plus sys/hq2x.sv and a sync_fix stub for arcade_video |
| README.md | core README (section 10) |
| mra/*.mra | Pause in the button list; Ray Crisis MRAs carry the configuration byte 00 |

## 2. DV1 integer pixel clock

Rule: CE_PIXEL must have a fixed period that divides CLK_VIDEO exactly,
else pixels alternate in width on direct_video (DV1). In direct_video
the HDMI transmitter runs on clk_vid itself (sys/sys_top.v 1262-1268), so
every dot is exactly the divider's number of clk_vid samples wide.

Modes used, from every GP1(08h) write in the MAME 0.288 oracle logs
(sim/oracle, 60 s runs of all six games, cold-boot runs of 200 to 300 s,
the raycrisj, psyvarij and shikigama 240 s surveys; all NTSC, 240 lines,
not interlaced; GP1(06h) X1..X2 is 2560 GPU clocks in every mode):

| GP1(08h) | Width | Used by | GP1(06h) | CLK_VIDEO | Divider | Dot clock | Integer |
|---|---|---|---|---|---|---|---|
| 08000000 | 256 | BIOS (4 writes at power-on) | 06C40240 | 53.693175 MHz | 10 | 5.369318 MHz | yes |
| 08000001 | 320 | all six games | 06C58258 | 53.693175 MHz | 8 | 6.711647 MHz | yes |
| 08000002 | 512 | Ray Crisis (235 to 2,995 writes per run) | 06C67267 | 53.693175 MHz | 5 | 10.738635 MHz | yes |
| 08000003 | 640 | Ray Crisis (129 to 130 writes per run) | 06C6C26C | 53.693175 MHz | 4 | 13.423294 MHz | yes |
| (368, HorRes2) | 368 | none | | 53.693175 MHz | 7 | 7.670454 MHz | yes |

How: rtl/gpu_videoout_async.vhd derives the dot enable from clk_vid with a
counter (clkCnt to clkDiv - 1, dividers 10/8/5/4/7), not an accumulator,
and restarts its phase at the end of every line. clk_vid is the fixed
53.693175 MHz of rtl/gnet/pll_vid_fixed.v, the ZN-2 GPU crystal (MAME
zn.cpp), so the dot clocks stand in the same integer ratio to it as on the
PCB. No PLL change is needed; pll_cpu and the PS1 PLL are untouched.

Measured (sim/shell/run_dotclock.sh: the video out alone on its three
clocks with the settings above, 3 frames per mode after one frame of
settling):

| Mode | Active dot period (clk_vid) | Any dot period | Dots per line | First dot after hsync rise | Line | Lines per frame | vsync edge not on hsync rise |
|---|---|---|---|---|---|---|---|
| 256 | 10 to 10 | 10 to 13 | 256 | 622 every line | 3413 | 263 | 0 |
| 320 | 8 to 8 | 8 to 13 | 320 | 648 every line | 3413 | 263 | 0 |
| 512 | 5 to 5 | 5 to 8 | 512 | 657 every line | 3413 | 263 | 0 |
| 640 | 4 to 4 | 4 to 5 | 640 | 660 every line | 3413 | 263 | 0 |

The line is 3413 clocks, no multiple of any divider, so one dot period
per line is longer (3413 mod divider extra clocks) where the counter
restarts, 32 clocks after the hsync rise: inside hsync, more than 590
clocks before the first active dot. It changes no visible pixel, and its
place is the same on every line, so the hsync edge sampled on CE_PIXEL
in PSX.sv does not move from line to line. vsync rises and falls in the
same clock as an hsync rising edge in all four modes (the minimum
standard's csync rule); PSX.sv latches both on the same CE_PIXEL.

## 3. Vertical games

MAME 0.288 taitogn.cpp: ROT270 for shikigam, shikigama, psyvaria,
psyvarij, psyvarrv, xiistag (and the out-of-scope sianniv, aerofgtsg,
brvbladeg); ROT0 for raycris, raycrisj, nightrai (R19 stays open for Night
Raid).

- Game configuration byte, MRA ioctl index 7 (not used by PSX.sv
  otherwise): bit 0 = vertical set, bit 1 = no Taito Zoom board. Default
  (no byte) horizontal, Zoom present. MRA part: `<rom index="7"><part>01</part></rom>`
  for the six ROT270 sets, `02` for the sets without a Zoom board, `00` for
  the others (`03` for a vertical set without one: aerofgtsg and brvbladeg
  among the 2011 conversions).
- No Zoom board (bit 1, `gnet_nozoom` to psx_top `zn_nozoom`): MAME's
  init_nozoom (taitogn.cpp 416-419) for otenamih, otenamhf, zokuoten,
  zokuotena, zooo, sianniv and the 2011 conversions (aerofgtsg, brvbladeg,
  flamegung, shngmtkbg, tblkkuzug). MAME holds the Zoom MN10200 in reset at
  machine reset (467) and, for these sets, never releases it: control_w
  skips the reset line, the Zoom reset and the sound flash read-mode writes
  (519-535). The core ORs the bit into the Zoom board's reset, so the board
  is never released. The host side answers as with the board (shared RAM,
  sound_irq_r reads 0, taito_zm.cpp 87-149) and the Zoom output stays
  silent.
  Bits 3:2 = the controls (`gnet_inmode`): 0 joysticks (every other set), 1
  mahjong panel and P1 joystick (mahjngoh, part `04`), 2 mahjong panel
  (usagi, `08`), 3 RC wheel and trigger (gobyrc, rcdego, `0C`). As MAME
  0.288 taitogn.cpp INPUT_PORTS, the bits MAME marks unused read as
  released: P2 bits 0-6 for 1-3, P1 bits 0-6 for 2-3, START1/START2 for 2,
  START2 for 3. The MRA generator (tools/gnet/make_release_mras.py) writes
  these bits.
- Mahjong panel (taitogn.cpp ttgnmp_state mahjong_panel_r; rows KEY0-KEY3
  of mame shared/mahjong.cpp mahjong_matrix_1p): zn2_io answers A10100
  (P4) with the AND of the rows that coin bits 2, 3, 6, 7 select, bits 6-7
  of a selected row 0 (MAME's KEY ports define bits 0-5), FFh with no row
  selected. Keys on the keyboard, MAME's defaults (emu/inpttype.ipp): A to
  N, Kan LCtrl, Pon LAlt, Chi Space, Reach LShift, Ron Z, Start 1 (KEY0
  bit 5, also the pad's Start). LCtrl, LAlt, Space stay P1 buttons 1-3 as
  in MAME. Not on the pad: Psikyo SH2's convention (mahjong keys as
  joystick buttons 4-23, MiSTer-devel Arcade-PsikyoSH2 rtl/hps2input.sv)
  would collide with this core's joystick bits 16-17 (savestate, fast
  forward of the PSX base).
- RC wheel and trigger (gobyrc ANALOG1 IPT_PADDLE, ANALOG2 IPT_PADDLE_V
  PORT_REVERSE, 00h-FFh, centre 80h): znmcu analog channels 0 and 1. Wheel
  from the analog stick's X, or the paddle once it moves (the source that
  moved last); trigger from the stick's Y reversed (stick up = FFh); the
  D-pad or arrows give full deflection. FFh on both for every other set
  (MAME's unused ANALOG ports). Crossed to clk_cpu by cdc_bus_sync in
  zn2_cdc (whole bytes); the mahjong rows join the cdc_sync input group.
- Flip Screen (status 104, shown for vertical sets only, forced off for
  horizontal ones): the GPU video out's rotate180 (upstream PSX_MiSTer
  "Rotate" path, gpu_videoout_async.vhd: lines fetched bottom to top,
  dots right to left). The ZN-2 GPU has no flip register, so this is the
  renderer 180 turn of the standard; it acts on CRT, direct_video and HDMI
  alike, before any rotation. Display start X is 0 or 704 in all games
  (GP1(05h)), a multiple of 4, which the rotate180 line read needs.
- Rotation: owned by the DDR3 arbiter branch (ddr3-arb-int,
  docs/ddr3_arbiter.md there), which instantiates screen_rotate, its FB_*
  and video_rotated, and the DDRAM FIFO. This branch drives the agreed
  interface: `gnet_rot_en = gnet_vertical & ~status[102] & ~DIRECT_VIDEO`
  (Orientation Vertical, HDMI only) and `gnet_rot_ccw = ~status[103]`
  (Rotate Direction CCW, the upright direction for ROT270). The two
  menu items stay hidden until that branch defines GNET_ROT_DDR. At the
  merge its tie-off declarations of the two wires go.
  Merged in branch gnet-full (revision GNET_Z1FULL, pc_build target
  z1full): the arbiter's declaration and tie-off of the two wires are
  under `ifndef GNET_SHELL, GNET_ROT_DDR is set, and screen_rotate takes
  arcade_video's CE_PIXEL and VGA_* on CLK_VIDEO (docs/ddr3_arbiter.md 4).
- HDMI aspect "Original": 4:3, 3:4 when gnet_rot_en (video_freak ARX/ARY).
  The active area is the game's own hblank (GNET_GAME_HBLANK), exactly
  256/320/512/640 dots, instead of PSX_MiSTer's fixed 352/563/704-dot
  window with padding; the 4:3 applies to the picture the game draws, as
  MAME shows it (zn.cpp: a raster screen with no aspect set, so MAME's
  default 4:3) and as an arcade monitor adjusted to fill the tube does.

## 4. System and audio

- Pause: "Pause when OSD is open" (status 64, its PSX meaning, default
  On), J1 button Pause (joystick bit 11) and the P key toggle a pause, as
  upstream's button pause. The core's pause holds CPU, GPU and SPU; the
  video keeps running.
- Watchdog: gnet_ctrl's MB3773 model counts on the raw clock and would
  reset the board after one period (8 s since hw-debug-overlay 878ad18;
  MAME guesses 5 s) of pause. Its reset is ignored while paused and for the
  period plus 0.5 s after: 8.5 s, 287,884,800 clk_1x cycles, computed in
  PSX.sv from localparam GNET_WD_TIMEOUT_S, which also sets zn2_board's
  WD_TIMEOUT_S through psx_mister and psx_top (generic ZN2_WD_TIMEOUT_S).
  A running game kicks it within a frame, a hung one still resets one
  period later. (Gating the
  count itself would change gnet_fc's ports, which the cosim harnesses
  use.)
- Black picture with running sync (rtl/gnet/gnet_sync_keeper.sv): the
  PSX_MiSTer video timing stops while the core is in reset, which in this
  core covers every download (BIOS, flash images, the 40 MB card image)
  and the reset sequencer after it. Two lines after the last core hsync
  edge the keeper substitutes a black raster with the core's 320-dot
  timing (3413 x 263, hsync 252 clocks, dot every 8 clocks, first dot 648
  clocks after hsync as the core's, 320 x 240 active, vsync on an hsync
  edge); it hands back on the core's first hsync edge. In normal running
  it is a multiplexer with no added latency. One frame is disturbed at
  each hand-over (the two rasters are not phase locked).
- Volume (status 106:105): Normal, +6 dB (x2, saturating), -6 dB, -12 dB on
  the 16-bit stereo output, one register on clk_1x, after which AUDIO_L/R
  go to the framework. With the Taito Zoom board (GNET_ZOOM, branch
  gnet-full revisions GNET_Z1FULL and the release's GNET_Z1FULLO) zoom_mix (SPU x 0.3 + Zoom x 1.0, MAME
  taitogn.cpp) drives `snd_l`/`snd_r`, so the volume applies to the mix.
  Level matching against the reference (-16.4 dBFS gameplay RMS): not
  done.
- SFX Level (status 119:117, GNET_ZOOM builds): the SPU's gain in zoom_mix,
  0.3 (MAME's route, default), 0.45, 0.6, 0.9 (MAME's pre-2018 ratio:
  SPU 0.45 against Zoom 0.5), 1.2, 1.5, saturating (sim/zoommix). Why:
  MAME's spu.cpp stores but never applies the SPU main volume
  (0x1F801D80/82); the games set it low (Ray Crisis 0x1125 = 0.27 of full
  scale, Shikigami 0x0C99 = 0.20, Psyvariar 0x2FDF = 0.75, logged in
  MAME 0.288 from warm NVRAM) and spu.vhd applies it. At the same 0.3 route
  the core's effects are therefore 11.4 dB (Ray Crisis), 14.1 dB
  (Shikigami) and 2.5 dB (Psyvariar) below MAME's against the same music.
  MAME's 0.3 itself was set by ear in 2018; the PCB's analog balance is
  unknown (R13).
- Keyboard, MAME defaults: P1 arrows, LCtrl/LAlt/Space = B1-B3, 1 Start,
  5 Coin; P2 R/F/D/G, A/S/Q = B1-B3, 2 Start, 6 Coin; 9 Service, F2 Test,
  P Pause. G-NET games use three buttons, so LShift (B4) is not mapped.

## 5. OSD

Shell menu (GNET_SHELL):

| Item | Bits | Shown |
|---|---|---|
| Aspect ratio | 33:32 | not on direct_video |
| Scale | 35:34 | not on direct_video |
| Orientation (Vertical, Horizontal) | 102 | vertical sets, HDMI, rotation built |
| Rotate Direction (CCW, CW) | 103 | as Orientation, and Orientation Vertical |
| Flip Screen | 104 | vertical sets |
| Scandoubler Fx (None, HQ2x, CRT 25/50/75%) | 116:114 | always |
| CRT H Position (0, +2 .. +14, -16 .. -2 dots) | 110:107 | always |
| CRT V Position (0, +1 .. +3, -4 .. -1 lines) | 113:111 | always |
| Pause when OSD is open | 64 | always |
| Volume | 106:105 | always |
| SFX Level (PS1 SPU gain in the mix: 0.3 MAME default, 0.45, 0.6, 0.9, 1.2, 1.5) | 119:117 | GNET_ZOOM builds (zoom_mix) |
| DIP | MRA | always |
| Watchdog | 100 | always |
| Debug overlay | 101 | always (docs/hw_debug_overlay.md) |
| Reset | 0 | always |

Removed from the earlier G-NET menu: Deinterlacing (bit 41; no game sets
an interlaced mode). Nothing from the PS1 console menu is shown (CD,
memory cards, pads, multitap, savestates, cheats, region, CD speed,
texture filter, debug pages). Their logic is already fixed by GNET_LEAN
and the trim switches; status bits that upstream logic still reads keep
their default 0, which is the upstream default (HDMI blackout on mode
change, no stereo mix, no DDR3 frame buffer debug). Bit 101 is the debug
overlay, merged from hw-debug-overlay (8866055) with its line in the shell
menu.

No vertical crop: the output is 240 lines, so a 216p crop for 5x on 1080p
would cut 24 lines (10%) of what the games draw; my Dooyong core (240
lines) made the same choice. Available on
request as a one-line video_freak change (CROP_SIZE 216, CROP_OFF), HDMI
only.

## 6. Verification

| Check | Result |
|---|---|
| sim/shell/run_dotclock.sh (NVC, gpu_videoout_async with the four G-NET modes) | section 2 table; all asserts pass |
| sim/shell/run_shell.sh (Verilator) | volume: 8 vectors incl. saturation at +6 dB; keeper: core silent from power-up, 4 frames of substitute raster (line 3413, hsync 252, dot period 8 in the active area, 320 dots x 240 lines, 263 lines, vsync on hsync, black); hand-over on the core's first hsync edge (2,180 clocks after start with the edge due at 2,179); 2 frames of exact pass-through; take-over 5,828 clocks after the core stops (two lines after its last hsync edge); 2 more substitute frames. PASS |
| Verilator lint of PSX.sv (emu) with black-box stubs for the VHDL entities and PLLs, four configurations: GNET_Z1SHELL, GNET_Z1SHELL + GNET_ROT_DDR, GNET_Z1_CPU50, upstream PSX | no error; the only warning left is the framework's HPS_BUS inout; GNET_SHELL adds no width warning against GNET_Z1_CPU50 |
| Verilator -Wall lint of gnet_sync_keeper and gnet_volume | clean (power-up initial values aside) |
| sim/shell/run_crt_pos.sh (Verilator) | section 8 |
| sim/zn2/run_zn2_io.sh (NVC) with the NVRAM checks | section 9; all zn2_io tests PASS |
| NVC analysis of every VHDL file of the system build plus psx_mister.vhd (the new zn_nv_* ports) | no error |
| After merging gnet-cpu50 6cb9b78 and hw-debug-overlay 8866055: tools/lint_psx.py (from ddr3-arb-int) on GNET_Z1SHELL, GNET_Z1SHELL with -DGNET_ROT_DDR=1, GNET_Z1_CPU50, GNET_Z1, PSX; both benches rerun | no warning or error in PSX.sv for the G-NET revisions; PSX shows only upstream's IMPLICITSTATIC in the pll_cfg block; benches unchanged (PASS, same DV1 table) |

Not verified: a Quartus fit (expected cost: sync keeper about 40 ALMs,
volume about 40, keyboard and pause about 40, rotate180 now live in the
video out, which GNET_LEAN had fixed to 0); the shell on hardware; the
keeper's hand-over seen on a CRT, a DV1 DAC and the HDMI scaler.

## 7. Open questions

1. Fit GNET_Z1SHELL (`tools/pc_build.sh z1shell`).
2. 216p crop for the horizontal games (section 5): off by choice.
3. HDMI aspect 4:3 of the drawn area instead of PSX_MiSTer's padded
   window (section 3).
4. Done since: CRT H/V position (section 8), scandoubler Fx (section 8),
   EEPROM NVRAM save (section 9), button names where documented (section
   9), README (section 10). Still open: audio level matching after the
   Zoom mix; button names for Ray Crisis, both Psyvariar sets and
   Shikigami (game manuals, docs/board_evidence.md D3); high
   score saving beyond the EEPROM (hiscore.dat); card write saving (R25).
5. arcade_video adds the framework's scandoubler and HQ2x (LINE_LENGTH
   644, 24-bit): expect some hundreds of ALMs and a few M10K in the fit.
   If the budget is tight with the Zoom board, HQ2x can go (scanlines
   only).

## 8. CRT position and scandoubler Fx

CRT H/V position (rtl/gnet/gnet_crt_pos.sv, between gnet_sync_keeper and
PSX.sv's video_aspect): the source raster is untouched; hsync and vsync
are regenerated. A new hsync starts K clocks after each source hsync rise
with the source's width, K = line - 2 x crt_h x clocks per dot (picture
right = sync earlier, modulo the measured line). A new vsync starts and
ends on new hsync rises, crt_v lines earlier than the source's, with its
length in lines. The settings are taken at the source vsync. With both at
0 the source's sync passes straight through. Bench (sim/shell/
run_crt_pos.sh, 320-dot raster, 2 frames per setting after one frame of
settling):

| crt_h, crt_v | new hsync vs source (clocks) | new vsync vs source (clocks) | hsync period, width; vsync lines; vsync edges on hsync rises |
|---|---|---|---|
| 0, 0 | 0 (pass-through) | 0 | 3413, 252; 3; yes |
| -1, 0 | +18 | +18 | same |
| +1, 0 | -14 | -14 | same |
| +7, 0 | -110 | -110 | same |
| -8, 0 | +130 | +130 | same |
| 0, +1 | +2 | -3411 | same |
| 0, +3 | +2 | -10237 | same |
| 0, -4 | +2 | +13654 | same |
| +5, -2 | -78 | +6748 | same |
| -6, +2 | +98 | -6728 | same |

Every moved setting is exactly -16 x crt_h - 3413 x crt_v clocks plus a
constant 2 clocks (the line counter and the output register). PASS.

Scandoubler Fx: PSX.sv's own gamma_corr and VGA_* assignments are replaced
in GNET_SHELL by the framework's arcade_video (WIDTH 640, DW 24, gamma
inside), fed from video_aspect and the debug overlay; video_aspect and the
overlay now step on the core's dot enable ce_pix, since CE_PIXEL is the
mixer's output. With Fx None and no forced scandoubler CE_PIXEL is ce_pix
delayed (DV1 unchanged). Scandoubled, the 512-dot mode (one dot every 5
clocks) gives alternating 2 and 3 clock dots at 31 kHz; that output is not
direct_video.

## 9. EEPROM save and button names

What G-NET keeps: the AT28C16 at 0x1FAF0000 (2 KB, zn2_io), the games'
settings and records, loaded from the MRA's `<nvram index="6"
size="2048"/>` (existing loader, ioctl index 6). The flash chips are
rebuilt from the card on a cold boot and the card writes (R25) stay open.

Save path: zn2_io keeps a copy of the EEPROM in two 1024 x 8 block RAMs
(even and odd bytes), written by both EEPROM ports (shell load and
power-up erase, CPU writes) and read on clk_1x, the hps_io clock, so the
copy itself is the clock crossing. hps_io's upload of index 6 steps
ioctl_addr by 2 and takes the 16-bit word at that address (low byte even),
the download format. A CPU write toggles `cdc_tx_nvtog` in zn2_io; PSX.sv
synchronises it (cdc_sync) and marks the copy dirty; when the OSD opens
with the copy dirty, `ioctl_upload_req` asks Main_MiSTer to save index 6
(the core pauses on OSD open by default). Needs checking on hardware:
that Main_MiSTer saves the arcade NVRAM on this request (the hiscore
autosave of my Hyper Duel core uses the same request).

Bench (sim/zn2/tb_zn2_io.vhd): after the shell preload ("TAITO_TG", rest
FFh) and the existing EEPROM tests, words 0 and 3 read 4154h and 4754h,
word 8 3CFFh (the accepted CPU write at 11h), word 10 FFFFh (the write
refused while busy is not in the copy), word 1023 FFFFh, and the write
toggle has toggled once.

Button names (shell-test MRAs in gnet_games/test_z1, gitignored): MAME
gives none and the game manuals are open (docs/board_evidence.md
D3). Named where a source exists: XII Stag button 1 "Shot" (its
how-to screen, gnet_games_test_matrix.md); Night Raid "Shoot, Wave, Bomb"
(arcade-history, secondary). The other four keep Button 1 to 3.

## 10. README

README.md now describes the core for users: supported games, what files
are needed, the MRA layout by ioctl index, controls, OSD options, known
issues, layout, credits; first person, no em or en dashes.
