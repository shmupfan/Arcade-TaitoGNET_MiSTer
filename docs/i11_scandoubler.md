# Issue #11: Scandoubler Fx loses the picture

Status: 2026-10-20, branch i11-scandoubler from de4d29b (alpha 3 source,
revision GNET_Z1FULLR). Cause proven in simulation with the real video out;
fix in RTL and simulation; no Quartus build, no hardware test yet.

Report (babayaga326, Discord, alpha 3 20261015): any Scandoubler Fx setting
other than None loses the picture. Output type not known.

## 1. Result

Core bug, on every output, not only a 15 kHz CRT effect. With the
scandoubler on (Fx HQ2x or CRT 25/50/75%, or `forced_scandoubler=1` in
MiSTer.ini) the core's 31 kHz output has no vertical sync at all and no
horizontal sync for 24 source lines of every frame. The HDMI scaler, direct
video and a 31 kHz VGA monitor all need that vsync, so the picture is lost
on all of them. Alpha 1 has the same fault. The fix makes the scandoubled
output a normal 31 kHz raster in all six G-NET modes and leaves the Fx None
output unchanged on every clock.

A 15 kHz-only CRT still cannot show any Fx setting other than None (31 kHz
output, as in my other cores); that part is expected.

Users with `forced_scandoubler=1` (31 kHz VGA monitors) are hit even with
Fx None, since the forced scandoubler turns on the same path.

## 2. Files that differ from upstream

| Path | Against | Difference |
|---|---|---|
| sys/ (all files) | PSX_MiSTer upstream/main and the merge base cd17b5a | none (`git diff --stat` empty) |
| sys/arcade_video.v, video_mixer.sv, scandoubler.v, hq2x.sv | dooyong-mister and tecmo16-mister sys/ | identical md5 (cores where Fx works) |
| sys/ | alpha 1 (gnet-full e0a36a3) | none |
| rtl/gpu_videoout_async.vhd | PSX_MiSTer upstream/main, alpha 1 | none |
| rtl/gnet/gnet_arcade_video.sv | sys/arcade_video.v | copy (issue #3, alpha 3); one change: VSync taken on every dot when the scandoubler is off (lines 97-101); with the scandoubler on it is the framework's HSync-aligned latch, identical to sys/arcade_video.v:71. The copy has no screen_rotate (PSX.sv uses the framework's). |
| PSX.sv | PSX_MiSTer upstream/main | upstream has no scandoubler: `VGA_SL = 0`, CE_PIXEL = ce_pix, no Fx option; `forced_scandoubler` from hps_io is unused. G-NET adds arcade_video (alpha 1) and its copy (alpha 3), the Fx option `P1O[116:114]` (PSX.sv:353) and GNET_GAME_HBLANK (PSX.sv:2571, 2918-2919). |

So the alpha 3 module copy is not the cause; the fault is in how the G-NET
shell feeds the framework's scandoubler, and it dates from alpha 1.

## 3. Cause, with evidence

1. The video out keeps hblank high for whole lines it does not draw. In
   WAITNEWLINE hblank is set to 1 (rtl/gpu_videoout_async.vhd:681); on a
   line with no new display line (vertical blanking, vsync included) it
   goes to WAITHBLANKENDVSYNC (725) and WAITINVSYNC (744), neither of which
   clears it; only DRAW does (761). Fixed VBlank, which would draw blank
   lines instead, is forced off in every G-NET build
   (PSX.sv:1798, `GNET_OPT(..., 1'b0)` under GNET_LEAN).
2. The G-NET shell passes that hblank to arcade_video unchanged
   (GNET_GAME_HBLANK = 1, PSX.sv:2571 and 2918-2919, so the HDMI window is
   exactly the drawn 256/320/512/640 dots). Upstream PSX_MiSTer builds its
   hblank from a per-line dot counter instead, but has no scandoubler.
3. The framework's scandoubler counts its lines from hblank falling edges:
   hcnt and sd_hcnt restart there and hde_start is taken there
   (sys/scandoubler.v:184-185); hs_end and hs_start are positions in hcnt
   (195-197, 201); the output hsync and the vsync pipeline step when the
   free-running sd_hcnt (which wraps at hde_start, 162) equals them (167,
   170, 177-178); vs_out = vso[3] (204). On a line with no hblank fall,
   hcnt runs on past the line end, the stored hs positions exceed the
   half-line wrap and are never matched again until the first drawn line:
   no output hsync, and vso never shifts, so vs_out never rises. Every
   vsync sits inside those lines.
4. arcade_video latches VBlank only on an hblank fall (sys/arcade_video.v:75),
   so VBL also never goes high.
5. sys_top feeds the HDMI scaler with the core's VGA_* after the scanlines
   block (sys/sys_top.v:1383, 1717-1719). ascal starts a frame only on an
   input vsync rise (sys/ascal.vhd:1227-1229) and sets its height there
   (1279-1281), so with no vsync it never completes a frame. Direct video
   and the analog VGA output carry the same signals.

Why the issue #3 bench did not see it: sim/shell/tb_arcade_video.sv uses a
synthetic source whose hblank toggles on every line, and it compares the
copy with the framework's module (both equally affected) instead of
checking that the scandoubled output is a valid raster.

## 4. Simulation

New benches (sim/shell):

- tb_vtrace.vhd + run_vtrace.sh (NVC): runs the real
  rtl/gpu_videoout_async.vhd with the tb_dotclock.vhd clocks and GP1
  settings (modes 0-3: 256/320/512/640 dots 240p; 4, 5: 640/512 480i),
  Fixed VBlank off, and writes one record per dot enable (clocks since the
  previous one, hsync, vsync, hblank, vblank) for 4 frames (6 fields in
  480i).
- tb_sd_trace.sv + run_sd_trace.sh (Verilator): replays a trace through
  PSX.sv's GNET_SHELL chain (sync keeper alive and CRT position 0, both
  pass-through; video_aspect with GNET_GAME_HBLANK) into
  gnet_arcade_video, for Fx None, forced scandoubler, HQ2x and CRT
  25/50/75%, and measures VGA_HS, VGA_VS, VGA_DE and CE_PIXEL. `fix` adds
  gnet_sd_blank as PSX.sv wires it, with a second arcade_video on the alpha
  3 wiring compared on every clock; `alpha1` uses sys/arcade_video.v.

Trace check (mode 1, Python over the trace): 92 of 1051 lines have no
hblank fall, 23 per 263-line frame (trace lines 236 to 258, vsync on
241 to 243).

Alpha 3 (no fix), every mode, every scandoubler setting:

| Mode | Fx None | Scandoubler on (forced, HQ2x, CRT 25/50/75%) |
|---|---|---|
| 0-3 (240p) | HS 3413 clocks, VS every 897,619, 240 DE lines | HS 1705/1706..81,910/81,911 clocks, **VS rises 0** |
| 4, 5 (480i) | HS 3413, VS 895,909..895,916 (half line kept) | HS up to 81,911 clocks apart, **VS rises 0** |

81,911 clocks is 24 source lines (24 x 3413 = 81,912) without an output
hsync. Alpha 1 wiring (`alpha1`, modes 1, 3, 4): the same, VS rises 0 for
every scandoubler setting.

With the fix, every mode:

| Mode | Scandoubler on | Fx None vs alpha 3 |
|---|---|---|
| 0 (256) | HS 1705..1708, VS 897,619, 526 HS and 480 DE lines per frame, 256 dots per line (512 HQ2x) | 0 of 2,513,877 clocks differ |
| 1 (320) | HS 1706..1707, VS 897,619, 526 / 480, 320 (640 HQ2x) | 0 of 2,513,881 |
| 2 (512) | HS 1705..1708, VS 897,619, 526 / 480, 512 (1024 HQ2x) | 0 of 2,513,882 |
| 3 (640) | HS 1706..1707, VS 897,619, 526 / 480, 640 (1280 HQ2x) | 0 of 2,513,881 |
| 4 (640i) | HS 1706..1707, VS 894,206 / 897,619 (262 and 263 lines), 524..526 / 480, 640 | 0 of 4,309,395 |
| 5 (512i) | HS 1705..1708, VS 894,206 / 897,619, 524..526 / 480, 512 | 0 of 4,309,395 |

The bench fails on: no VGA_VS, an HS gap over 1800 clocks, any DE line
with a wrong dot count, or any Fx None difference; all six PASS. The
1705..1708 hsync spread in the 5- and 10-clock modes is the scandoubler's
half-line rounding of an odd 3413-clock line, as before. In 480i the
scandoubled fields are 262 and 263 lines (the framework's HSync-aligned
vsync, kept on purpose for 31 kHz in the issue #3 copy); each field is
shown as a progressive 480-line frame.

The issue #3 bench (run_arcade_video.sh) still passes (module unchanged).
`tools/lint_psx.py GNET_Z1FULLR`: no warnings or errors in PSX.sv.

## 5. Fix

rtl/gnet/gnet_sd_blank.sv, between video_aspect and arcade_video
(PSX.sv, before the gnet_arcade_video instance), enabled by
`(|status[116:114]) | forced_scandoubler`:

- It counts dots from each hsync rise and remembers where hblank fell and
  rose on the last drawn line.
- On a line where hblank does not fall at that dot, it drives hblank low
  from that dot to the remembered rise and holds vblank high over the same
  stretch, so arcade_video latches VBlank = 1 for the line (no DE, no
  extra picture line) and the scandoubler gets its line edge.
- Outputs are combinational from video_aspect's signals and state updated
  on ce_pix, so no delay is added; with the scandoubler off they equal the
  inputs exactly (0 differing clocks above).

The rotation feed (screen_rotate via rot_gamma) still takes video_aspect
directly and is unchanged. The CRT H position moves hsync on drawn and
undrawn lines alike, so the remembered dots follow it. Cost: about 40
registers and two 12-bit compares on clk_vid.

Files: rtl/gnet/gnet_sd_blank.sv (new), PSX.sv (instance, HBlank/VBlank of
arcade_video), the five GNET_SHELL revisions' qsf (GNET_Z1SHELL, Z1FULL,
Z1FULLB, Z1FULLO, Z1FULLR: one SYSTEMVERILOG_FILE line), sim/shell benches
above.

## 6. Build request (main session)

- Target: GNET_Z1FULLR (release revision) from branch i11-scandoubler.
- Gate: STA all clocks met, pll_hdmi outclk on PLLOUTPUTCOUNTER_X0_Y5_N1
  (issue #8 check), the usual TEX_MISS_DELAY seed caveat applies.
- Hardware checks: (1) HDMI, Fx None: unchanged picture, video_info 59.8 Hz;
  (2) HDMI, each of HQ2x, CRT 25/50/75%: picture present, scanlines or
  HQ2x visible; (3) a 480i game (Zooo or Mahjong Oh) with CRT 50%: picture
  present; (4) direct video Fx None on a 15 kHz CRT: unchanged, 480i still
  interlaced (#3); (5) if available, a 31 kHz VGA monitor with
  `forced_scandoubler=1`.

## 7. Draft reply to the tester (not posted)

> Thanks for the report. I found the cause: with any Scandoubler Fx setting
> the core's doubled 31 kHz signal had no vertical sync, so the picture was
> lost on HDMI and on a VGA monitor as well. Alpha 1 had the same problem.
> I have a fix and it will be in the next build. One question so I can
> test the right thing: what are you connected with (HDMI, direct video,
> or analog to a 15 kHz CRT or a 31 kHz VGA monitor)? If it is a 15 kHz
> CRT, keep Scandoubler Fx at None: every Fx option outputs 31 kHz, which
> a 15 kHz CRT cannot show, as in other MiSTer arcade cores.
