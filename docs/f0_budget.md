# F0: trial fit and trim budget

Status: IN PROGRESS (2026-10-04). V0 measured; reference and trim builds
queued. Every figure below cites its build folder under `builds/`
(gitignored; reports kept locally) and was tabulated with
`tools/fit_entities.py`.

Device: 5CSEBA6U23I7, 41,910 ALMs, 553 M10K, 112 DSP blocks (fit report
totals; this confirms the 553 M10K figure, which was needs-review in my
earlier planning notes).

Base: PSX_MiSTer main cd17b5a, merged as 357766b. Quartus 17.0.2 Lite, PSX.qsf
settings unchanged (SEED 1), compile PC E-cores only.

## 1. V0: unmodified PSX_MiSTer

Build `builds/20261004_1426_psx` (flow 54 min 20 s, rc 0, RBF md5
e01535e3e986977bc4c585bd23725588).

| Resource | Used | Device | % |
|---|---|---|---|
| ALMs needed | 40,456 | 41,910 | 96.5 |
| M10K | 406 | 553 | 73.4 |
| DSP blocks | 112 | 112 | 100.0 |
| Block memory bits | 2,535,460 | 5,662,720 | 44.8 |

Timing (sta.summary, slow model): setup -0.332 ns (TNS -0.579) on the HDMI
PLL clock, hold -0.112 ns on emu pll general[0] (clk_1x domain per the
PLL order, needs-review); every core setup clock positive (worst +0.939 ns
on emu pll general[2]). So the upstream design at SEED 1 is already at the
edge on this toolchain; small negative slack on framework clocks is not a
G-NET problem but shows how little headroom a 96.5% design has.

### 1.1 PSX blocks (psx_top children)

| Block | ALMs | M10K | DSP | G-NET |
|---|---|---|---|---|
| gpu | 7,421.5 | 59 | 34 | keep (2 MB VRAM change later) |
| spu | 5,103.1 | 82 | 13 | keep (MAME routes SPU at 0.3) |
| gte | 4,689.8 | 1 | 15 | keep |
| cpu | 3,843.1 | 88 | 6 | keep |
| cd_top | 3,258.2 | 71 | 6 | **trim** (no CD on ZN-2) |
| dma | 1,646.1 | 3 | 0 | keep |
| joypad | 1,052.8 | 8 | 0 | **trim**; replaced by ZN SIO0 + CAT702 x2 + znmcu |
| memorymux | 871.5 | 0 | 0 | keep (G-NET map changes) |
| mdec | 712.8 | 19 | 9 | measurement only (R18 at M0) |
| savestates | 658.3 | 0 | 0 | keep (reset sequencer) |
| memctrl | 275.1 | 0 | 0 | keep |
| timer | 268.6 | 0 | 0 | keep |
| own logic | 233.1 | | | |
| cheats | 137.0 | 4 | 0 | **trim** |
| sio | 81.1 | 0 | 0 | keep (SIO1) |
| irq | 78.3 | 0 | 0 | keep |
| memcard x2 | 124.4 | 8 | 0 | **trim** |
| statemanager | 4.1 | 0 | 0 | **trim** |
| exp2 | 2.1 | 0 | 0 | stub, left |
| **psx_top total** | **30,484.5** | **343** | **83** | |

### 1.2 Framework and shell (outside psx_top)

| Block | ALMs | M10K | DSP |
|---|---|---|---|
| ascal (HDMI scaler) | 2,236.0 | 43 | 19 |
| hps_io | 1,236.1 | 0 | 0 |
| audio_out | 1,057.4 | 0 | 8 |
| sys_top own logic | 951.0 | | |
| osd x2 | 968.6 | 9 | 0 |
| pll_hdmi_adj, pll_cfg_hdmi, pll_cfg | 1,237.2 | 0 | 0 |
| emu own logic | 511.0 | | |
| sdram | 333.4 | 0 | 0 |
| yc_out | 249.2 | 1 | 2 |
| video_freak | 222.2 | 0 | 0 |
| other sys and emu children | 968.6 | 10 | 0 |
| **outside psx_top** | **9,970.7** | **63** | **29** |

Framework share: about 9,970 ALMs (23.8% of the device), higher than the
unverified forum figure of about 17%.

### 1.3 Trim saving read from V0 (before refit)

| Trim set | ALMs | M10K | DSP |
|---|---|---|---|
| Console trims (cd_top, joypad, memcards, cheats, statemanager) | 4,576.5 | 91 | 6 |
| plus MDEC | 5,289.3 | 110 | 15 |

Projected V1 (console trims) from these: about 35,880 ALMs (85.6%), 315
M10K (57%), 106 DSP (95%). The refit (V1, V2, LEAN) replaces these
projections with measured numbers.

**DSP is the tightest resource**: 112 of 112 in V0. Quartus fills spare
DSP blocks with multipliers that could otherwise go to logic, so 100% is
partly packing, but the Zoom board (ZSG-2 interpolation and filters,
TMS57002 MAC) needs multipliers too. The FX-1B reference fit shows how many.

## 2. Reference builds (measurement only, no code taken)

### 2.1 FX-1B (XelaNotPu ZN1-TaitoFX1B_MiSTer 4711fa5, revision ZN1 = Zoom variant)

Build `builds/20261004_1750_fx1b` (their ZN1.qsf, SEED 3). Device totals:
41,378 ALMs (98.7%), 475 M10K (85.9%), 111 DSP (99.1%). Timing on my
toolchain: HDMI PLL setup -0.444 ns and core clock emu pll general[1] hold
-0.125 ns (their comment says hold fails at 99% density; reproduced).

| Block | ALMs | M10K | DSP |
|---|---|---|---|
| taito_zoom_top total | 7,146.5 | 156 | 4 |
| of which mn10200 | 3,944.5 | 0 | 1 |
| of which zsg2 | 1,388.9 | 13 | 1 |
| of which tms57002 + tms_delay_m10k | 1,318.5 | 68 | 2 |
| of which glue, work RAM (64 KB), cache, mailbox | 494.6 | 75 | 0 |
| zn_sio (SIO0 with CAT702 and znmcu) | 545.2 | 0 | 0 |
| zn1_io (inputs, EEPROM) | 110.0 | 2 | 0 |

The MN10200 is a literal port of MAME's C++ interpreter (file header) and
is larger than the PSX CPU core (3,507 ALMs in LEAN). The G-NET Zoom is my
own implementation (PLAN.md 3.1); an MN10200 in RTL designed as hardware,
by comparison with other 16-bit CPU cores on MiSTer, should take about 1,800
to 2,800 ALMs (estimate, not measured).

### 2.2 ZN2-Capcom (XelaNotPu ZN2-Capcom_MiSTer d16528f, revision ZN2)

Build `builds/20261004_1919_zn2` (their ZN2.qsf, SEED 12). Device totals:
39,402 ALMs (94.0%), 454 M10K (82.1%), 112 DSP (100%). Timing on my
toolchain: hold -0.151 ns on emu pll general[1].

| Block | ALMs | M10K | DSP | Against upstream V0 | For G-NET |
|---|---|---|---|---|---|
| gpu (2 MB VRAM, 480i) | 7,700.1 | 67 | 38 | +278 ALMs | needed (CXD8654Q has 2 MB) |
| memorymux (ZN map) | 1,058.6 | 1 | 0 | +187 ALMs | ZN decode needed; overlaps the G-NET glue decode estimate in part |
| cpu (with their data cache) | 3,728.5 | 168 | 6 | -115 ALMs, +80 M10K | the data cache is their addition; MAME's CXD8661R has none, so not budgeted (R1) |
| zn_sio + zn1_io | 693.5 | 2 | 0 | new | needed (ZN-2 I/O) |
| mdec | 696.3 | 19 | 9 | as V0 | off (R18) |
| capcom_qsound | 2,295.6 | 24 | 1 | new | not G-NET |

## 3. Trim builds

### 3.1 LEAN (the G-NET base configuration)

Revision GNET_F0_LEAN: console trims (CD, pads and memory cards, cheats,
savestate requests), MDEC off (R18: unused, docs/r18_mdec_spu.md), 41
console OSD options fixed to constants (GNET_OPT), MISTER_DISABLE_YC and
MISTER_DISABLE_ADAPTIVE. Build `builds/20261004_1639_lean` (source commit in
SOURCE_PUSHED; flow 41 min 47 s, rc 0, RBF md5
6581c0781777b380bf3895aad7ad24ae).

| Resource | V0 | LEAN | Freed | LEAN % | Free after LEAN |
|---|---|---|---|---|---|
| ALMs | 40,456 | 31,777 | 8,679 | 75.8 | 10,133 |
| M10K | 406 | 252 | 154 | 45.6 | 301 |
| DSP | 112 | 89 | 23 | 79.5 | 23 |

Where the space came from (V0 to LEAN, psx_top children): cd_top 3,258,
joypad 1,053, mdec 713, cheats 137, memcards 124 ALMs removed outright;
gpu 7,422 to 5,781 (-1,641 ALMs, -30 M10K: info overlay, crosshairs,
texture filter and render24 paths pruned by the fixed options, so no gpu
switch is needed); cpu 3,843 to 3,507 (-336, -12 M10K: turbo/cache options);
framework 9,971 to 8,894 outside psx_top (YC output gone, ascal -335).

Timing: every core clock meets setup (worst +0.804 ns, emu pll general[2])
and hold (worst +0.146 ns). The only failure is the HDMI PLL setup path in
the MiSTer framework, -0.209 ns, also present in unmodified V0 (-0.332 ns);
it is not caused by the trims.

Check of the "switches on = upstream" claim: revision PSX synthesised from
commit bcdec20 (all trim generics 1, no GNET macros; includes the GNET_OPT
macro, the fixed-PLL ifdef and the savestate strobe mask) gives Analysis &
Synthesis totals identical to unmodified V0: 42,404 registers, 2,535,460
block memory bits, 124 DSP, 145 pins (`builds/20261004_1932_psxsw`,
map.summary diff empty). Upstream builds are unchanged by the G-NET edits.

### 3.2 LEAN rebuild: fixed video PLL and savestate strobe mask

Build `builds/20261004_2011_lean` (commit bcdec20; RBF md5
b99b46cbd04d0b0fa808d5ae17a2ac28). Adds the fixed 53.693175 MHz video PLL
(rtl/gnet/pll_vid_fixed.v, replaces pll2 + pll_cfg) and HAS_SAVESTATES=0
masking of savestate write strobes for types 0 to 11 and all read strobes.

| Resource | LEAN (3.1) | LEAN rebuild | Saved | % of device |
|---|---|---|---|---|
| ALMs | 31,777 | 27,534 | 4,243 | 65.7 |
| M10K | 252 | 245 | 7 | 44.3 |
| DSP | 89 | 89 | 0 | 79.5 |

Where (psx_top children, ALMs): cpu 3,507 to 2,486; gte 4,630 to 3,916;
spu 5,123 to 4,345; dma 1,642 to 1,237; gpu 5,781 to 5,533; timer 268 to
137; memctrl 257 to 123; psx_top total 22,884 to 19,242 (-3,642); pll_cfg
gone (-615). Each module's saved-state registers reduced to their reset
constants as intended.

Timing: all clocks meet setup and hold, including the HDMI PLL path that
failed in V0 and in the first LEAN (worst setup +0.119 ns on pll_hdmi;
worst hold +0.213 ns).

### 3.3 F0 and F0_NOMDEC

Not built: superseded by LEAN, which contains every trim they would have
measured.

## 4. Additions

### 4.1 G-NET glue (paper estimates, not measured)

No FPGA implementation exists for any of these (as far as I found), so the
figures are estimates, sized against PSX blocks of similar complexity
measured in V0 (sio 81, irq 78, timer 269, memctrl 275, cheats 137 ALMs).
Function lists from MAME 0.288 taitogn.cpp, rf5c296.cpp, ataflash.cpp and
intelfsh.cpp.

| Block | Function | ALMs | M10K | DSP | Calibrated against |
|---|---|---|---|---|---|
| Control registers, MB3773 watchdog, 0x1fb70000 | control/control2/control3 latches, watchdog counter, Zoom reset | 60 to 120 | 0 | 0 | irq (78) |
| Intel flash command machine (shared by U30, U27, U56, U55, U29) | read array, read ID, read/clear status, word program, block erase, busy timing | 200 to 400 | 0 | 0 | timer (269) |
| Flash bank decode and 16-bit bridge to SDRAM/DDR3 | bank select from control bit 2 and JP1, read and write paths | 300 to 500 | 0 | 0 | memctrl (275) |
| RF5C296 register subset | ExCA index/data at 0x3e0/0x3e1, card reset, I/O and memory windows | 200 to 400 | 0 | 0 | cheats (137) plus register file |
| ATA task file and command engine with Taito Type 1 lock | IDENTIFY, READ SECTOR(S)/MULTIPLE, SET FEATURES, WRITE SECTOR(S) (needed: R25 shows card writes); 512-byte sector buffer; CIS and attribute registers; 5-byte unlock and lock status | 500 to 900 | 2 to 3 | 0 | joypad (1,053) as an upper bound for a protocol engine |
| Card sector fetch/write-back to DDR3 | sector DMA between card image and buffer | 200 to 400 | 0 to 1 | 0 | dma (1,646) is far larger; a single fixed-size burst engine |
| MiSTer side: card image load, flash persistence | ioctl to DDR3, save path for 8.5 MB flash | 200 to 400 | 0 | 0 | |
| **Total** | | **1,660 to 2,920** | **2 to 4** | **0** | |

### 4.2 ZN-2 layer (pending ZN2-Capcom reference fit)

Entities to read: zn_sio (SIO0 with CAT702 and znmcu), zn1_io, and the 2 MB
VRAM change inside gpu. Subtract capcom_qsound, jtag_la, qs_audcap,
altsource_probe, pause_overlay and crt_adjust, which G-NET does not need.

### 4.3 Taito Zoom (pending FX-1B reference fit)

Entity to read: taito_zoom_top (mn10200, zsg2, tms57002, tms_delay_m10k,
caches, DDR3 arbiter). G-NET differences: program from flash U27 instead of
ROM, 6 MB wave data instead of 4 MB, reset held by the main CPU (small).

## 5. Budget and verdict

### 5.1 Projection (ALMs)

| Item | Low | High | Source |
|---|---|---|---|
| LEAN base (with fixed PLL and savestate mask) | 27,534 | 27,534 | measured (3.2) |
| ZN-2 GPU (2 MB VRAM) over PSX GPU | 278 | 278 | measured ZN2 against V0 |
| ZN memory map in memorymux | 187 | 187 | measured ZN2 against V0 |
| ZN-2 I/O (SIO0, CAT702, znmcu, inputs, EEPROM) | 693 | 693 | measured ZN2 |
| Zoom without MN10200 | 3,202 | 3,202 | measured FX-1B (7,146.5 - 3,944.5) |
| Own MN10200 | 930 | 1,670 | estimate, docs/mn10200_design.md 5.9 (was 1,800 to 2,800 before the study) |
| Zoom G-NET changes (flash program, 6 MB wave, reset) | 50 | 200 | estimate |
| G-NET glue | 1,660 | 2,920 | estimate (4.1) |
| **Total** | **34,534** | **36,684** | |
| **% of 41,910** | **82.4** | **87.5** | |

With XelaNotPu's MN10200 size (3,945) the total is 37,549 to 38,959 ALMs
(89.6 to 93.0%).

M10K: 245 + 156 + 2 + 4 = 407 (73.6%). DSP: 89 + 4 = 93 (83.0%). Neither
is a constraint.

### 5.2 Verdict

**Gate passed: the G-NET system fits the 5CSEBA6.** Projected 34,534 to
36,684 ALMs (82.4 to 87.5%) with an own MN10200 as designed in
docs/mn10200_design.md, below the 90% margin over the whole range; even
with XelaNotPu's larger MN10200 it would be 89.6 to 93.0%. M10K about
74%, DSP about 83%. The measured base (LEAN rebuild) meets timing on every
clock, while every reference build at 94% or above failed hold by 0.11 to
0.15 ns, so staying under 90% matters.

Open, outside this budget: the true ZN-2 CPU rate (R1; a 50 MHz CPU domain
adds timing pressure, probe in tools/sta/cpu50_probe.tcl), and the G-NET
glue and Zoom figures, which are estimates until their RTL is fitted.

## 6. Measured blocks (stand-alone fits, 2026-10-05)

Stand-alone Quartus 17 fits on the compile PC (virtual pins, so "ALMs
needed" includes some virtual-I/O overhead; the MN10200 fit shows 217 ALMs
of it). Reports under builds/ (gitignored).

| Block | Branch | Build | ALMs | M10K | DSP | Note |
|---|---|---|---|---|---|---|
| G-NET glue (gnet_fc) | main | 20261005_1054_gluefit | 1,346 | 7 | 1 | paper estimate 1,180 to 1,790 |
| MN10200 | mn10200-rtl | 20261005_1047_mn102 | 2,302 (2,085 without virtual-pin overhead) | 3 | 0 | trimmed version refit queued (expected about 1,900) |
| TMS57002 | tms57002-rtl | 20261005_1240_tms57 | 1,002 | 68 | 3 | paper 710 to 1,240 |
| ZSG-2 | zsg2-rtl | 20261005_1148_zsg2 | 9,461 | 5 | 1 | register RAM fell into 16,448 flip-flops; fix in progress (paper 950 to 1,400) |
| CDC test top | r1-cdc | 20261005_1233_cdcfit | 374 | 4 | 0 | test top only; clk_a setup fails, being diagnosed |

Full-design references: B1 (LEAN + 2 MB VRAM + narrow GTE) 27,709 ALMs;
E6 (B1 settings plus GTE_NARROW_MUL = 3, CPU-side constraints for 50 MHz)
26,802 and 26,786 ALMs on seeds 1 and 2, GTE meeting 10 ns with +1.536
and +1.792 ns.

Update (2026-10-05): MN10200 refit after the area trims
(`builds/20261005_1405_mn102`): 1,969 ALMs (core 866.7, periph 850.1, own
logic 251.3 of which most is virtual-pin overhead), 3 M10K, 0 DSP, from
2,302. GNET_Z1 full design (`builds/20261005_1446_z1`, B1 + ZN-2 layer + G-NET
glue, no Zoom): 29,967 ALMs (72%), 252 RAM blocks, 84 DSP, one clk_1x hold
miss of -0.072 ns; first hardware test boots the BIOS (see
docs/zn2_layer_design.md on zn2-layer).

Update (2026-10-05): whole Zoom board (zoom-board, ZOOM_FIT, clk_1x,
`builds/20261005_1535_zoomfit`): 4,628 ALMs (MN10200 1,666, ZSG-2 1,250,
TMS57002 921, board logic about 790 including virtual-pin overhead),
148 RAM blocks, 5 DSP, timing met. With GNET_Z1 (29,967 ALMs) that is
about 34,600 ALMs (82.5%) before the R1 crossings (estimated 540 to 900),
inside the 90% margin.
