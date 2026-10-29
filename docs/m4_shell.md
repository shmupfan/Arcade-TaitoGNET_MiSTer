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
| rtl/gnet/gnet_pause_dim.sv | OSD Dim video after 10s (section 4) |
| rtl/gnet/gnet_coin_pulse.sv | coin press to a 100 ms pulse (section 4); in GNET_Z1SHELL, GNET_Z1FULL, GNET_Z1FULLB and GNET_Z1FULLO |
| rtl/gnet/gnet_arcade_video.sv | copy of the framework's arcade_video that keeps the 480i half-line vsync when not scandoubling (section 8, issue #3) |
| rtl/gnet/gnet_dash.sv | Dash button for Chaos Heat (section 4, configuration bit 4); in the same four revisions |
| rtl/gnet/zn2_io.vhd, zn2_board.vhd, rtl/psx_top.vhd, rtl/psx_mister.vhd | EEPROM copy for the NVRAM save and its ports `zn_nv_*` (section 9), unused (and removed in synthesis) outside GNET_SHELL |
| GNET_Z1SHELL.qsf | GNET_Z1_CPU50 plus `GNET_SHELL=1`, the shell files and the debug overlay files |
| tools/pc_build.sh | target `z1shell` (DIR gn_z1shell, TASK gnz1shell) |
| sim/shell/ | tb_dotclock.vhd + run_dotclock.sh (NVC), tb_shell.sv + run_shell.sh, tb_crt_pos.sv + run_crt_pos.sh, tb_arcade_video.sv + run_arcade_video.sh (Verilator) |
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
  START2 for 3. Bit 4 = the Dash button (`gnet_dash`, chaoshea and
  chaosheaj, part `10`), see the Dash item in section 4. The MRA generator
  (tools/gnet/make_release_mras.py) writes these bits.
- Mahjong panel (taitogn.cpp ttgnmp_state mahjong_panel_r; rows KEY0-KEY3
  of mame shared/mahjong.cpp mahjong_matrix_1p): zn2_io answers A10100
  (P4) with the AND of the rows that coin bits 2, 3, 6, 7 select, bits 6-7
  of a selected row 0 (MAME's KEY ports define bits 0-5), FFh with no row
  selected. Keys on the keyboard, MAME's defaults (emu/inpttype.ipp): A to
  N, Kan LCtrl, Pon LAlt, Chi Space, Reach LShift, Ron Z, Start 1 (KEY0
  bit 5, also the pad's Start). LCtrl, LAlt, Space stay P1 buttons 1-3 as
  in MAME. Psikyo SH2's convention (mahjong keys as joystick buttons 4-23,
  MiSTer-devel Arcade-PsikyoSH2 rtl/hps2input.sv) is not used: it would
  collide with this core's joystick bits 16-17 (savestate, fast forward of
  the PSX base) and needs more buttons than a pad has.
- Mahjong panel on pad 1 (issue #2; PSX.sv `mp_*`), ORed with the keys.
  Eight inputs, numbered clockwise from the left on the D-pad and then on
  the face buttons: s1 Left, s2 Up, s3 Right, s4 Down, s5 J1 bit 12, s6
  bit 6, s7 bit 4, s8 bit 5 (MRA defaults Y, X, A, B). Two shifts, J1 bits
  13 and 14 (defaults L and R), pick the layer:

  | Held | s1 | s2 | s3 | s4 | s5 | s6 | s7 | s8 |
  |---|---|---|---|---|---|---|---|---|
  | nothing (Usagi) or L and R (both sets) | A | B | C | D | E | F | G | H |
  | R | I | J | K | L | M | N | | |
  | L | Kan | Pon | Chi | Reach | Ron | | | |

  Start stays the pad's Start. Mahjong Oh keeps its P1 stick and buttons
  1-3 on the unshifted pad, so its A-H layer is L and R together. Each
  input keeps the layer it was pressed in until released (`mp_lay`), so
  letting go of a shift before the key never turns a held key into a new
  press of another key. An input pressed with a shift held is masked off
  the P1 port (`mp_p1m`). The MRAs name the eleven J1 entries (bits 4-14)
  in `<buttons names>` and map Service, Test and Pause to nothing by
  default (L and R are the shifts); the CONF_STR J1 list, shared by every
  set, is unchanged.
- Service and Test on the pad, mahjong sets only (`mp_cs`): while Select
  (J1 Coin, bit 8) is held, L is Service and R is Test, and neither acts
  as a shift. Select still inserts a coin, but only when released with no
  L or R pressed during the hold (`mp_coin`, one clock into coin1_pulse,
  so still one 100 ms coin); Select with L or R never coins. In the
  joystick sets Select coins on press as before. Keyboard 9 and F2 are
  unchanged. Bench: sim/shell/run_mjsel.sh (section 6).
- RC wheel and trigger (gobyrc ANALOG1 IPT_PADDLE, ANALOG2 IPT_PADDLE_V
  PORT_REVERSE, 00h-FFh, centre 80h): znmcu analog channels 0 and 1. Wheel
  from the analog stick's X (80h + X), or the paddle once it moves (the
  source that moved last); trigger from the stick's Y reversed (80h - Y:
  rest 80h, stick up FFh, down 01h; issue #4, the old ~(Y ^ 80h) rested at
  7Fh); the D-pad or arrows give full deflection only while that stick axis
  is within 16 of centre, so D-pad bits set by a deflected stick never
  replace the analog value. Bench: sim/rc_input/run.sh. Calibration (MAME
  0.288, checked with these values): 1. hands off, Start; 2. wheel fully
  left and right, trigger fully up and down, Start; 3. Start again (writes
  EEPROM 478h-487h; the core saves it with the NVRAM on OSD open). Before
  step 1 the game shows any value off centre as full scale (80h or 7Fh).
  FFh on both for every other set
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

- Pause, as the official MiSTer arcade cores (Galaga, Centipede, Cave):
  the J1 button Pause (joystick bit 11, either player; the MRAs leave it
  unmapped) and the P key always toggle a pause, and a reset cancels it.
  The "Pause Options" page has "Pause when OSD is open" (status 64, its
  PSX meaning, default On) and "Dim video after 10s" (status 120, 0 = On,
  default On): after 10 s of any pause (button, P key or OSD) the RGB is
  halved to reduce burn-in, restored as soon as the pause ends
  (rtl/gnet/gnet_pause_dim.sv, written for this core: Pause_MiSTer is
  GPL-3). The dim is applied to the core RGB ahead of arcade_video and the
  rotation feed, so HDMI, direct video and analog all dim; the syncs do
  not pass through it. The core's pause holds CPU, GPU and SPU; the video
  keeps running. Alpha 2's "Pause Button" on/off item (status 120, Off by
  default) is gone; bit 120 now means Dim.
- Service Menu (status 121, default Off): holds the board's test switch
  S551:4 on, the same switch as the MRA DIP item "Test Mode (S551:4)" (MRA
  DIP bit 3, active low as MAME taitogn.cpp DSW). PSX.sv passes zn_dsw as
  the MRA byte with bit 3 ANDed with NOT status 121, so with the option On
  the game sees Test Mode on whatever the DIP item says; Off leaves the DIP
  item in charge. When a game reads the switch (at boot or while running)
  is game code, not checked here: if the menu does not appear, reset with
  the option On. It is not the J1 Test
  button (the service port's test input).
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
  P Pause. G-NET games use three buttons, so LShift (B4) is not mapped,
  except as Dash (P1 LShift, P2 W) for the sets with configuration bit 4.
- Dash (issue #7, rtl/gnet/gnet_dash.sv, configuration bit 4): Chaos Heat
  dashes on a double tap of a direction. The chaoshea and chaosheaj MRAs
  name Button 1, Button 2, Button 3, Dash, Start, Coin, Service, Test,
  Pause (default A, B, X, Y, Start, Select, L, R), so Dash is pad bit 7;
  with bit 4 set, gnet_dash_remap moves bits 8-12 back to the J1 list's
  7-11 and takes bit 7 as Dash (bits 16 and 17 untouched). Dash pressed
  while a direction is held, from the next VBLANK: the direction released
  4 frames, pressed 4, released 4, pressed 4, then the stick again (still
  held, the player runs on). P1 and P2; the frame count stops while
  paused. Measured in MAME 0.288 (sim/oracle/dash, player X/Z words
  0x1426ec/0x1426f0 every frame, both VBLANK phases): a dash when the
  second press starts at most 14 frames after the first (15 in one phase)
  and the release before it is at least 2 frames (1 in one phase); first
  presses of 2 to 12 frames work, 16 or more do not (a held direction is a
  walk), and from a held direction the release before the first tap is
  needed. 4/4 puts the second press 8 frames after the first. The
  sequence dashed in all 8 directions in both phases (150 units a frame
  against a walk's 82). Bench: sim/shell/run_dash.sh. Shell builds only.
- Coin pulse (issue #1, rtl/gnet/gnet_coin_pulse.sv): Coin 1 and Coin 2
  (J1 Coin, keys 5 and 6) give one 100 ms pulse per press (3,386,880
  clk_1x clocks), however long the button is held, then at least 100 ms
  released; one press made during a pulse or that gap is kept and follows.
  The timer stops while the core is paused. Why: Space Invaders
  Anniversary treats a coin held for 30 VBLANKs (0.5 s) as a jammed mech,
  shows COIN ERROR and loops until the watchdog resets it (MAME 0.288,
  routine 0x8001102c); a 0.1 s coin is counted, as from a real mech's short
  pulse. This is an input-handling choice of the core, not board
  behaviour. Service, Test and Start are unchanged. Shell builds only.
- Coin lockouts (zn2_io): as MAME, a coin the game has locked out reads as
  not inserted. Coin register 0x1FA20000 bit 1 clear locks coin 1, bit 5
  clear locks coin 2 (zn.cpp coin_w 233-241); MAME drops a locked-out coin
  input (ioport.cpp 1312-1327, coin_lockout option on by default). The
  lockouts start unlocked and survive a reset, as MAME's bookkeeping.

## 5. OSD

Shell menu (GNET_SHELL):

| Item | Bits | Shown |
|---|---|---|
| Orientation (Vertical, Horizontal) | 102 | vertical sets, HDMI, rotation built |
| Rotate Direction (CCW, CW) | 103 | as Orientation, and Orientation Vertical |
| Flip Screen | 104 | vertical sets |
| Video Settings page (P1): Aspect ratio | 33:32 | not on direct_video |
| Video Settings: Scale | 35:34 | not on direct_video |
| Video Settings: Scandoubler Fx (None, HQ2x, CRT 25/50/75%) | 116:114 | always |
| Video Settings: Deinterlacing (Weave, Bob) | 41 | not on direct_video |
| Video Settings: CRT H Position (0, +2 .. +14, -16 .. -2 dots) | 110:107 | always |
| Video Settings: CRT V Position (0, +1 .. +3, -4 .. -1 lines) | 113:111 | always |
| Audio Settings page (P2): Volume | 106:105 | always |
| Audio Settings: SFX Level (PS1 SPU gain in the mix: 0.3 MAME default, 0.45, 0.6, 0.9, 1.2, 1.5) | 119:117 | GNET_ZOOM builds (zoom_mix) |
| Pause Options page (P3): Pause when OSD is open (On, Off) | 64 | always |
| Pause Options: Dim video after 10s (On, Off) | 120 | always |
| DIP | MRA | always |
| Service Menu (Off, On; holds S551:4 Test Mode on) | 121 | always |
| Advanced page (P4): Watchdog | 100 | always |
| Advanced: Debug overlay | 101 | always (docs/hw_debug_overlay.md) |
| Reset | 0 | always |

Layout (2026-10-14): rotation items at the top, then the Video Settings,
Audio Settings and Pause Options pages, DIP and Service Menu, and the
Advanced page. Every item keeps its status bit, so saved settings carry
over. A page is "Pn,Name;" and its items "PnO[..]"; the H mask letter goes
in front of the page prefix ("H0P1O[33:32]"), as upstream's
"DEP1O[62]".

Deinterlacing (bit 41, Weave or Bob, the PSX_MiSTer item and wiring
HDMI_BOB_DEINT) was first left out because none of the first six games
sets an interlaced mode. It is back since issue #3: Zooo, Mahjong Oh,
Zoku Otenamihaiken, Kollon, Otenami Haiken Final and Flip Maze use the
interlace bit (docs/m1_gpu_zn2.md 4). It only drives the HDMI scaler, so
it is hidden on direct_video (H0). Nothing from the PS1 console menu is shown (CD,
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
| Coin pulse and lockouts (issue #1, 2026-10-14): tb_shell.sv coin cases (1 s hold, two presses, a press during a pulse, a pause) and tb_zn2_io.vhd lockout cases (each coin locked, both, after a reset); tools/lint_psx.py GNET_Z1FULLO and GNET_Z1 | lint clean; sim/shell/run_shell.sh PASS, sim/zn2/run_zn2_io.sh PASS (2026-10-14) |
| Pause options and Service Menu (2026-10-14): sim/shell/run_pausedim.sh (Verilator) runs PSX.sv's own pause block, pause button wire and zn_dsw expression (gen_pausewd.py) with gnet_pause_dim at DIM_CLKS 1000: pad P1, pad P2 and P key toggle with no gate; no dim before 1000 clocks, RGB halved after; restored within 3 video clocks of unpause; Dim Off never dims; Dim On mid-pause; OSD pause dims; OSD pause Off; reset cancels the button pause; Service Menu clears DSW bit 3 only. tools/lint_psx.py GNET_Z1FULLO, GNET_Z1FULLR, GNET_Z1 | PASS, 23 checks; lint clean |
| Mahjong Select + L / R (2026-10-14): sim/shell/run_mjsel.sh (Verilator) runs PSX.sv's own mahjong pad block, zj1 and coin1_pulse; Usagi and Mahjong Oh: Select tap = one 100 ms coin after release; Select + L = Service held, L not a shift, no coin; Select + R = Test held, R not a shift, no coin; R alone + s1 = tile I, no coin; keyboard 9 / F2; joystick sets: Select coins on press, no Service or Test | PASS, 27 checks |
| Issue #3 (480i), PASS 2026-10-14: run_dotclock.sh modes 4 and 5 (08000027h, 08000026h; vsync intervals must alternate 895,913 / 895,912), run_crt_pos.sh 480i runs, run_arcade_video.sh (240p identical to the framework's arcade_video for every Fx; 480i Fx None intervals within one dot of 262.5 lines) | sections 2 and 8 |
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

480i (issue #3, 2026-10-14): in an interlaced mode every second field's
source vsync rises and falls mid-line, 1707 clocks after the hsync rise
(rtl/gpu_videoout_async.vhd), and that half line is what makes a CRT
interleave the fields. The block above rebuilt vsync on new hsync rises,
so with any non-zero setting it dropped the half line. It now records
the clocks from the source hsync rise to each source vsync rise; when that
is not 0 the field's new vsync edges come the same number of clocks after
their new hsync rise, and since the field lengths alternate (263 and 262
new hsyncs between vsyncs), the next field's line count and phase are
taken from two fields back. The 240p logic is kept as it was: it runs
whenever neither of the last two source vsyncs rose mid-line, so 240p
output is unchanged. The bench has a 480i source added (fields A and B,
every setting above): field B's new vsync edges 1707 clocks after the new
hsync rise, both fields at -16 x crt_h - 3413 x crt_v + 2 from their
source vsync, vsync intervals alternating 895,912 and 895,913; then the
240p settings again. Not run yet.

Scandoubler Fx: PSX.sv's own gamma_corr and VGA_* assignments are replaced
in GNET_SHELL by the framework's arcade_video (WIDTH 640, DW 24, gamma
inside), fed from video_aspect and the debug overlay; video_aspect and the
overlay now step on the core's dot enable ce_pix, since CE_PIXEL is the
mixer's output. With Fx None and no forced scandoubler CE_PIXEL is ce_pix
delayed (DV1 unchanged). Scandoubled, the 512-dot mode (one dot every 5
clocks) gives alternating 2 and 3 clock dots at 31 kHz; that output is not
direct_video.

Since issue #3 the instance is rtl/gnet/gnet_arcade_video.sv, a copy of
the framework's module (sys/ stays as upstream) with one change. The
framework takes VSync only on an HSync rising edge, which moved the 480i
mid-line vsync to the next line start: the fields came out 262 and 263
lines apart (894,206 and 897,619 clocks) instead of 262.5, and a CRT on
direct video or 15 kHz analog drew them on top of each other. The copy
takes VSync on every dot enable when the scandoubler is off (Fx None and
no forced scandoubler) and keeps the HSync-aligned latch when it is on
(31 kHz, HQ2x, scanlines). In 240p the source's vsync edges come on the
same clock as its hsync rises (section 2, "vsync edge not on hsync rise:
0"), so both latches give the same VSync and the output is unchanged.
Scaled HDMI was never affected (the scaler weaves on VGA_F1). Bench:
sim/shell/run_arcade_video.sh runs the copy beside the framework's module
on the same input; not run yet.

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
(arcade-history, secondary); Zooo "Swap, Binoculars" (two buttons per
Amusement Journal, May 2004 and the TOPS control sheet; Success's game page
names button 1 and the four-use Binoculars hint, so button 2 carries the
hint). Zooo's Button 3 is not used: it is named "-" so it takes no default
pad button, and BUTTON_DEFAULTS gives the set its four named defaults (the
default list counts only named buttons). The other four keep Button 1
to 3.

## 10. README

README.md now describes the core for users: supported games, what files
are needed, the MRA layout by ioctl index, controls, OSD options, known
issues, layout, credits; first person, no em or en dashes.
