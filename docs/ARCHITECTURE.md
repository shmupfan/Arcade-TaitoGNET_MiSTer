# Architecture of the Taito G-NET core

A map of the core for a developer or reviewer who wants to know where
things are before reading code. It covers the release revision,
GNET_Z1FULLR, as on the alpha 5 integration branch: the alpha 3 release
(RBF `Arcade-TaitoGNET_20261015.rbf`, md5 a4e2f4cd) plus the alpha 4
additions (issue #10 polygon watchdog, issue #11 scandoubler blanking,
issue #12 MRA DDR3 load, the fitter-only HDMI over-constraint F1 and the
area switches; docs/alpha5_integration.md). Fit figures are the alpha 3
release's unless a section says otherwise; alpha 5 has not been fitted yet.
Every statement points at the code (`file:line`, line numbers as of this
document's commit) or at a design document by section number. Where I have
not checked something, it says needs-review.

What this document does not repeat: the accuracy evidence and every known
difference from MAME and the board (docs/ACCURACY.md), the per-file record
of what I changed in PSX_MiSTer (PROVENANCE.md), and the archived
experiment revisions that design notes still name
(docs/experiment_revisions.md).

## 1. The core in one paragraph

The core is Robert Peip's PSX_MiSTer (base commit cd17b5a, PROVENANCE.md)
with the PlayStation console parts that G-NET does not have switched off by
build macros, and three things added: the ZN-2 board layer (2 MB VRAM, the
ZN-2 expansion bus, CAT702 security, I/O MCU, EEPROM, inputs), the G-NET
FC PCB glue (five Intel flash chips, the RF5C296 PC card controller, the
Taito ATA cards, the control registers and the MB3773 watchdog) and the
Taito Zoom sound board (MN10200 CPU, ZSG-2, TMS57002, mailbox, volume). The
CPU side of the PlayStation runs on its own 50/100 MHz clocks, separate
from the GPU and SPU (PSX.sv:139-171). A DDR3 arbiter shares the MiSTer
DDR3 port between the core, the Zoom board, a flash mirror and HDMI
rotation (PSX.sv:2701, rtl/gnet/gnet_ddr3_arb.sv). PSX.sv is the top level
(module `emu`) and holds the arcade shell: loader, inputs, OSD, video and
audio output.

## 2. Block diagram

Legend: `[U]` PSX_MiSTer upstream (some files modified behind generics,
PROVENANCE.md), `[G]` written for this core (rtl/gnet, rtl/zoom), `[F]`
MiSTer framework (sys/, unchanged). `<=X=>` is a clock crossing built from
rtl/gnet/cdc.

```
 MiSTer framework [F]: hps_io, scaler, video and audio out, DDR3 (f2h) and SDRAM pins
   |  ioctl, OSD status, joysticks, keys          DDRAM_* (clk_2x)      SDRAM pins
   v                                                   ^                    ^
 PSX.sv, module emu (G-NET top, mostly [G] inside `ifdef GNET_*)           |
   loader: ioctl 0, 2-7, 254 -> SDRAM ch3, DDR3 card, zn2 loader FIFO       |
   inputs, coin pulse, Dash, mahjong panel, RC wheel                        |
   reset_or, watchdog hold          SDRAM ch3: ch3_cdc <=X=> zn2_ch3_arb ---+ sdram.sv [U, modified]
   DDR3 arbiter gnet_ddr3_arb [G] ---------------------------------> DDRAM  | (clk_cpu2x / clk_cpu)
     R rotation FIFO <=X=> screen_rotate [F]  (clk_vid)                      |
     Z Zoom line port (gnet_ddr3_zport, clk_1x to clk_2x)                    |
     G gnet_ddr3_gmux: flash mirror (gnet_ddr3_mirror) <=X=> ch3 writes (clk_cpu) <-+
                       then the DDR3 flash copier (gnet_ddr3_flcopy, reads) -> ch3 downloads
     C core: psx_mister DDRAM side
   video: GPU out -> sync keeper -> CRT position -> [debug overlay, not in the release]
          -> pause dim -> gnet_sd_blank -> gnet_arcade_video (Fx) -> VGA;
          rot_gamma -> screen_rotate (HDMI rotation)
   audio: SPU + Zoom -> zoom_mix (SFX Level) -> gnet_volume -> AUDIO_L/R
   |
 psx_mister.vhd -> psx_top.vhd [U, modified]
   CPU group (clk_cpu 50 MHz, clk_cpu2x 100 MHz)    |  PS1 group (clk_1x 33.8688, clk_2x 67.7376 MHz)
     CPU, GTE, DMA, timers, IRQ, SIO0 bus, MDEC     |    GPU [U] (draws on clk_2x, video on clk_vid)
     memorymux, memctrl [U]          <=X=> cpu_split [G] <=X=>   SPU [U]
     |  zn_* expansion bus (memorymux ZN2_MAP)      |    savestates.vhd [U]: reset sequencer
     zn2_board [G] (clk_cpu, CLK_HZ 50,000,000)     |    psx_top DDR3 client mux [U]:
       gnet_fc: gnet_flash, gnet_rf5c296,           |      VRAM, SPU RAM, card image (memZN)
                gnet_ata, gnet_ctrl (MB3773)        |
       zn2_io: inputs, board regs, EEPROM, coins    |
       zn_sio0 + 2 x zn_cat702 + znmcu              |
       flash storage port -> SDRAM ch3 (PSX.sv)     |
       card storage port            <=X=> zn2_cdc <=X=>  zn2_cardmem [G] (clk_2x) -> DDR3 card
       Zoom host port               <=X=> zoom_cdc <=X=> zoom_board [G] (clk_1x / clk_2x)
                                                    |      MN10200, ZSG-2, TMS57002, M66220
                                                    |      mailbox, MB87078 volume, program
                                                    |      cache; wave and program reads ->
                                                    |      Z port of gnet_ddr3_arb
```

Where each box is instantiated:

| Block | Instance |
|---|---|
| CPU group PLL, emu PLL, fixed video PLL | PSX.sv:163, 173, 186 |
| psx_mister and its generics | PSX.sv:1818-1844 |
| CPU group clocks into the core (clk_cpu3x is clk_cpu2x) | PSX.sv:1853-1855 |
| Clock split layer | rtl/psx_top.vhd:2757 (`gsplit1`), cpu_split at 2917 |
| ZN-2 board on the CPU clock | rtl/psx_top.vhd:3227 (`gzn2c`), zn2_board 3322, zn2_cdc 3402, zn2_cardmem 3461 |
| Zoom board | rtl/psx_top.vhd:3492 (`gzoom`), zoom_cdc 3598, zoom_board 3624 |
| Debug overlay registers (ZN2_DBG = 1 only; the release sets 0) | rtl/psx_top.vhd:3718 |
| gnet_fc children | rtl/gnet/gnet_fc.sv:246, 253, 260, 266 |
| SDRAM channel 3 crossing and arbiter | PSX.sv:2363, 2381 |
| SDRAM controller | PSX.sv:2431 |
| Sync keeper, CRT position, volume | PSX.sv:2612, 2637, 2651 |
| DDR3 arbiter section | PSX.sv:2701 (screen_rotate 2744, zport 2789, mirror 2811, arbiter 2896) |
| DDR3 load: download detection, glue port mux, flash copier (GNET_DDR3_LOAD) | PSX.sv:797-838, 2852, 2876 |
| Debug overlay (not with GNET_NO_DBG), pause dim, scandoubler blanking, arcade_video, rotation gamma | PSX.sv:3113, 3147, 3174, 3186, 3212 |
| SPU and Zoom mix | PSX.sv:2271 |

Language rule: blocks that sit on psx_top's VHDL buses are VHDL (zn2_*,
zn_*, znmcu, cdc/, cpu_split/, zoom_cdc); the MiSTer shell side, the FC PCB
devices, the DDR3 arbiter and the Zoom board are SystemVerilog.

## 3. Clocks and crossings

### 3.1 Clocks

| Clock (PSX.sv name) | Frequency | Source | What runs on it |
|---|---|---|---|
| clk_cpu | 50.000 MHz | rtl/gnet/pll_cpu.v:47, from the 50 MHz crystal over the global network (PSX.sv:147-170) | CPU, DMA, timers, memorymux, MDEC (rtl/psx_top.vhd:1992), zn2_board and everything in it (rtl/psx_top.vhd:3325, 3334), SDRAM clk_base (PSX.sv:2450), zn2_ch3_arb |
| clk_cpu2x | 100.000 MHz | rtl/gnet/pll_cpu.v:50 | GTE, CPU and MDEC 2x ports, SDRAM controller clock (PSX.sv:2449); also passed as clk_cpu3x (PSX.sv:1855) |
| clk_1x | 33.8688 MHz | emu PLL, rtl/pll/pll_0002.v:28 | SPU, savestates engine, hps_io and every download (PSX.sv:677), Zoom ZSG-2, TMS57002 and output side, Zoom host side (rtl/psx_top.vhd:3628-3632), audio mix and volume |
| clk_2x | 67.7376 MHz | rtl/pll/pll_0002.v:31 | GPU drawing, DDR3 port (DDRAM_CLK, PSX.sv:2594), gnet_ddr3_arb, zn2_cardmem, Zoom MN10200 side (CLK_H 4, rtl/zoom/zoom_board.sv:27-46) |
| clk_3x | 101.6064 MHz | rtl/pll/pll_0002.v:34 | Nothing in the release fit: the SDRAM and the CPU group's 3x ports take clk_cpu2x, and the release timing report lists no clk_3x clock |
| clk_vid (CLK_VIDEO) | 53.693175 MHz | rtl/gnet/pll_vid_fixed.v:47 (fixed, GNET_LEAN, PSX.sv:183-195) | GPU video timing, sync keeper, CRT position, overlay, arcade_video, screen_rotate (PSX.sv:2598) |
| HDMI, audio, HPS | framework | sys/ | unchanged |

clk_1x and clk_2x come from one PLL with aligned edges, so paths between
them are synchronous (docs/ddr3_arbiter.md 4, last item; the Zoom board's
CLK_H 4 split relies on it, rtl/zoom/zoom_board.sv:31-38). clk_cpu and
clk_cpu2x are one PLL as well (GNET_CPU50_B1.sdc:1-5). The two pairs are
unrelated to each other and to clk_vid.

Why 50 MHz: the CXD8661R's clock is undocumented. The R3051 and CW33000
conventions and post-0.288 MAME's GPU clock point to a 50 MHz core; I rate
that inference medium confidence, and a frequency counter on the board
would settle it (docs/ACCURACY.md 2.4, first row; design in
docs/r1_cpu_domain_design.md, "Plan for exactly 50.000 MHz"). Root counters
and SIO0 still count at 33.8688 MHz equivalents through a phase accumulator,
10,584 / 15,625 per clk_cpu cycle (rtl/gnet/cdc/tick_accum.vhd header).

### 3.2 Crossings in the release

Every crossing I added between unrelated clocks either uses the blocks in
rtl/gnet/cdc (cdc_sync, cdc_pulse, cdc_bus_sync, cdc_fifo, cdc_handshake,
tick_accum) or follows their register naming, cdc_tx_* at the source and
cdc_rx_* at the destination (the two DDR3 FIFOs, docs/ddr3_arbiter.md 4).
rtl/gnet/cdc/cdc.sdc bounds every cdc_tx_* to cdc_rx_* path;
GNET_CPU50_B1.sdc sources it and on purpose sets no clock group between the
CPU group and the PS1 group, so a crossing without a synchroniser shows up
as a failing path (GNET_CPU50_B1.sdc:14-19). The GPU's own crossing into
clk_vid is upstream's. The last three rows below are timing exceptions,
not synchronisers.

| Crossing | Clocks | Built with | Where |
|---|---|---|---|
| CPU to GPU: GP0, GP1, DMA words and reads (C1 to C4) | clk_cpu, clk_1x | command FIFO, handshake for read answers | rtl/gnet/cpu_split/cpu_gpu_bridge.vhd |
| CPU to SPU: register and DMA traffic (C8 to C11) | clk_cpu, clk_1x | as the GPU | rtl/gnet/cpu_split/cpu_spu_bridge.vhd |
| Interrupts, dot clock, ce, pause and idle levels (C5 to C7, C12 to C16) | clk_cpu, clk_1x/clk_2x | cdc_pulse, two-register synchronisers | rtl/gnet/cpu_split/cpu_split.vhd |
| Reset pulses and the RAM zero fill (C17) | clk_1x engine, clk_cpu filler | cdc_pulse, toggle handshake | rtl/gnet/cpu_split/cpu_reset_fill.vhd; section 5.3 |
| Board inputs, loader words, watchdog pulse, coin outputs | clk_1x, clk_cpu | cdc_sync, cdc_fifo 16 x 29, cdc_pulse | rtl/gnet/zn2_cdc.vhd |
| PC card storage port (C18) | clk_cpu, clk_2x | cdc_handshake | rtl/gnet/zn2_cdc.vhd |
| Zoom host port and control bit 4 | clk_cpu, clk_1x | handshake | rtl/gnet/zoom_cdc.vhd |
| SDRAM channel 3 downloads | clk_1x to clk_cpu | cdc_handshake `ch3_cdc` | PSX.sv:2363 |
| Flash mirror writes | clk_cpu to clk_2x | 32-entry dual-clock FIFO | rtl/gnet/gnet_ddr3_mirror.sv, PSX.sv:2811 |
| Rotation writes | clk_vid to clk_2x | 512-entry dual-clock FIFO (RAW 9) | rtl/gnet/gnet_ddr3_arb.sv:45 |
| Debug overlay | clk_vid to clk_cpu and clk_2x | cdc_handshake u_hs, u_hs_dr | rtl/gnet/zn_dbg_overlay.vhd; GNET_CPU50_B1.sdc:21-55 |
| EEPROM write toggle | clk_cpu to clk_1x | cdc_sync | PSX.sv:1138 |
| Static OSD and EXE configuration into the CPU group | clk_1x to CPU clocks | false path by register name (quasi-static, core held in reset when they change) | GNET_CPU50_B1.sdc:62-74 |
| EARLY_READY read word | clk_cpu2x to clk_cpu | multicycle 2 | GNET_CPU50_B1.sdc:76-83 |
| clk_vid against the emu PLL | | false paths, as upstream PSX.sdc does for pll2 | GNET_LEAN.sdc |

Crossing numbers C1 to C20 are those of docs/r1_cpu_domain_design.md
("Plan for exactly 50.000 MHz" P2, "Crossings as built" and "ZN-2 layer in
the CPU group", Crossings).

### 3.3 Timing of the release fit

From the release build's reports (Quartus 17.0.2 Lite, 5CSEBA6U23I7,
fitter seed 8; the reports are not committed): 36,441 of 41,910 ALMs (87%),
462 of 553 RAM blocks, 102 of 112 DSP blocks, 5 of 6 PLLs. Worst setup
slack in the timing summary: HDMI clock +0.017 ns, clk_cpu2x +0.290,
clk_2x +0.691, clk_cpu +0.765, clk_1x +1.764, clk_vid +2.291. The hold
check of clk_1x and clk_2x in all four corners (tools/sta/clk1x_hold.tcl)
gives a worst of +0.084 and +0.085 ns (fast -40C model). Seed 8 is the
last of seven seeds in the qsf's history; each earlier one missed timing
or failed to route on the logic of its day (GNET_Z1FULLR.qsf:160-171), so
margins are thin and any netlist change can need a new seed.

Alpha 4 adds two things aimed at that margin, neither of which changes what
a game sees. F1 (GNET_HDMI_FITOC.sdc, read at GNET_Z1FULLR.qsf:204) gives
quartus_fit, and only quartus_fit, 0.25 ns more setup uncertainty on HDMI
to HDMI paths, so placement keeps margin in the framework scaler where the
HDMI failures are; sign-off STA times the real clock (docs/hdmi_timing.md
4). The area switches (section 6.1) free about 330 to 400 ALMs and 67 M10K
(docs/area.md 2). The alpha 5 sources have not been fitted; the build
request is a four-seed sweep (docs/alpha5_integration.md).

## 4. Memory map

### 4.1 Main CPU address map

PS1 registers (0x1F801000-0x1F802FFF) are upstream's. The ZN-2 and FC PCB
additions, from MAME 0.288 zn.cpp and taitogn.cpp, are tabulated with their
traces in docs/zn2_layer_design.md 5.1. In the core, memorymux sends the
expansion regions to its zn_* port (generic ZN2_MAP, rtl/psx_top.vhd:2140)
and zn2_board decodes them (rtl/gnet/zn2_board.vhd:265-283):

| Range | Device | Block |
|---|---|---|
| 0x1F000000-0x1F7FFFFF | flash bank window | gnet_fc, gnet_flash |
| 0x1FA00000-0x1FAF07FF (except 0x1FA30000), 0x1FB20000 | inputs, board configuration (69h), security select, coins and lockouts, EEPROM, fixed reads | zn2_io |
| 0x1FA30000 | control3 | gnet_fc |
| 0x1FB00000-0x1FB0FFFF | RF5C296 and ATA task file | gnet_fc (gnet_rf5c296, gnet_ata) |
| 0x1FB40000, 0x1FB60000, 0x1FB70000 | control (watchdog bit 5, Zoom reset bit 4, flash bank bit 2), control2, 0x1FB70000 | gnet_fc, gnet_ctrl |
| 0x1FB80000-0x1FBE01FF | Zoom volume port, Zoom registers, M66220 mailbox | zoom_cdc to zoom_board (rtl/gnet/zn2_board.vhd:36-39, 275-283) |

SIO0 carries the two CAT702 chips and the I/O MCU (zn_sio0, zn_cat702,
znmcu; docs/zn2_layer_design.md 6 and 7).

### 4.2 SDRAM (32 MB)

| SDRAM byte address | Content | Written by | Read by |
|---|---|---|---|
| 0x0000000-0x03FFFFF | main RAM, 4 MB of an 8 MB region | CPU, DMA (channels 1, 2) | CPU, DMA |
| 0x0800000-0x087FFFF | BIOS m534002c-60.ic353 (512 KB) | ioctl index 0 (PSX.sv:1252, BIOS_START 1172) | CPU |
| 0x1000000-0x11FFFFF | U30 sub-BIOS flash, 2 MB | ioctl 3, then gnet_flash | CPU through gnet_flash |
| 0x1200000-0x127FFFF | U27 Zoom program flash, 512 KB | ioctl 3, then gnet_flash | CPU (Zoom reads its DDR3 copy) |
| 0x1400000, 0x1600000, 0x1800000 (2 MB each) | U56, U55, U29 wave flashes | ioctl 3, then gnet_flash | CPU (Zoom reads its DDR3 copy) |

Sources: docs/zn2_layer_design.md 13.4; flash layout
rtl/gnet/zn2_board.vhd:31-33; flash download address PSX.sv:1251. The
flash area is reached through SDRAM channel 3, which upstream uses for
downloads and cheats (cheats are off in G-NET builds); zn2_ch3_arb shares
it between the download handshake and zn2_board's flash port, one request
at a time (PSX.sv:2351-2406).

### 4.3 DDR3

The core's DDR3 window is HPS physical 0x30000000 upward: psx_mister drives
DDRAM_ADDR = 0011 followed by the core's byte address bits 27 to 3
(rtl/psx_mister.vhd:392-394), so core byte b is physical 0x30000000 + b.
Physical addresses below are what Main_MiSTer and the scaler see.

| Physical | Core byte | Content | Client | Source |
|---|---|---|---|---|
| 0x24000000, 3 x 8 MB | outside the window | HDMI rotation buffers | screen_rotate through the arbiter's R port | sys/arcade_video.v:204 |
| 0x30000000-0x301FFFFF | 0x0000000 | VRAM, 2 MB (1024 x 1024) | GPU, through psx_top's DDR3 client mux | docs/zn2_layer_design.md 13.4 |
| 0x30300000-0x3037FFFF | 0x0300000 | SPU RAM, 512 KB (SPUSDRAM is 0 in GNET_LEAN builds, PSX.sv:1921) | SPU | rtl/psx_top.vhd:1230 |
| 0x31000000-0x319FFFFF | 0x1000000 | copy of the flash area: U30 at +0, U27 at +0x200000, waves at +0x400000 | written by gnet_ddr3_mirror (G port) from every channel 3 write into SDRAM 0x1000000-0x19FFFFF; read by the Zoom board (Z port) | rtl/gnet/gnet_ddr3_arb.sv:47-52; docs/ddr3_arbiter.md 4 |
| 0x34000000 upward, up to 64 MB | 0x4000000 | PC card image (40,960,000 bytes in docs/zn2_layer_design.md 13.4; the MRA format allows up to 64 MB) | zn2_cardmem: written by ioctl index 5, read and written by gnet_ata | rtl/gnet/zn2_cardmem.vhd:22, 49 |
| 0x3E000000 + n x 4 MB, n = 0 to 3 | 0xE000000 | upstream savestate slot headers | read once by the reset sequencer; nothing writes them in G-NET builds (savestates off) | rtl/psx_top.vhd:2547, rtl/savestates.vhd:111, 568-600 |

PSX_MiSTer's memory card areas (core bytes 0x100000 and 0x200000) would
overlap 2 MB VRAM, but they are removed with the pads (GNET_NO_PADS,
docs/zn2_layer_design.md 13.4).

Card writes the games make stay in DDR3 until the core is reloaded; there
is no save path yet (docs/ACCURACY.md 6.4, R25).

### 4.4 Issue #12: loading straight into DDR3 (in the release from alpha 4)

The development line after alpha 3 loads the two large ROMs with the MRA
`address=` attribute instead of the word-by-word ioctl handshake, which
took about 35 s for Ray Crisis. Main_MiSTer then copies the ROM into
physical memory itself (docs/i12_ddr3_load.md 3). GNET_Z1FULLR sets
GNET_DDR3_LOAD from alpha 4 (GNET_Z1FULLR.qsf:211):

| ioctl index | MRA attribute | Lands at | Core support |
|---|---|---|---|
| 5 (card image) | `address="0x34000000"` | the card area above, where zn2_cardmem already reads it | none needed: works with the alpha 3 RBF (docs/i12_ddr3_load.md 4.2) |
| 3 (flash area) | `address="0x31000000"` | the flash mirror's place | macro GNET_DDR3_LOAD: rtl/gnet/gnet_ddr3_flcopy.sv copies it to SDRAM 0x1000000 after the download, with the core held in reset and Main held by ioctl_wait (docs/i12_ddr3_load.md 4.3) |

An MRA with the index 3 address needs the GNET_DDR3_LOAD RBF; one with only
the index 5 address works on every RBF; old MRAs work on both
(docs/i12_ddr3_load.md 9). The load time on hardware is not yet measured
(docs/i12_ddr3_load.md 8 and 12). On the first hardware test of the alpha 4
RBF the core boots with old MRAs, but a full DDR3 load (flash and card)
ends in ERROR C094; that is under investigation on branch i12-ddr3load and
not fixed in alpha 5.

How the core sees it (PSX.sv:797-838): Main starts an address load with the
length in ioctl_addr and sends no ioctl_wr, so an index 3 download that
starts with ioctl_addr not 0 is a DDR3 load. When it ends, gnet_ddr3_flcopy
(PSX.sv:2876) reads the area through the arbiter's glue port, behind the
flash mirror in gnet_ddr3_gmux (PSX.sv:2852), and writes it to SDRAM over
the same download path as a normal flash load (PSX.sv:1231-1244), holding
the core in reset and ioctl_wait high until the last word.

## 5. Boot and load sequence

### 5.1 What the MRA sends

Main_MiSTer sends the ROMs in the MRA's order; for the release MRAs that is
index 0, 2, 3, 4, 5, 7, with the NVRAM (6) and the DIP switches (254) from
Main's own files and the MRA's switches. The format is in the public
README, "MRA format".

| Index | Content | Path in the core |
|---|---|---|
| 0 | BIOS, 512 KB | ramdownload to SDRAM 0x800000 over channel 3 (PSX.sv:1229-1262) |
| 2 | CAT702 keys tt10, tt16 (16 bytes) | loader FIFO to zn2_board (PSX.sv:888-897), crossing in zn2_cdc |
| 3 | flash area, 10 MB | ramdownload to SDRAM 0x1000000 (PSX.sv:1251), mirrored to DDR3 0x31000000; with `address="0x31000000"` Main writes DDR3 itself and gnet_ddr3_flcopy copies it to SDRAM (section 4.4) |
| 4 | card IDENTIFY, CIS, key and card type (1 KB) | loader FIFO; also marks the card present (PSX.sv:898) |
| 5 | card image | zn2_cardmem, four words per DDR3 qword at 0x34000000 + offset (PSX.sv:899-908) |
| 6 | EEPROM, 2 KB | loader FIFO; saved back by an upload when the OSD opens after a write (PSX.sv:1128-1149) |
| 7 | game configuration byte: vertical, no Zoom, control type, Dash | PSX.sv:914-919 (meaning at 564-576) |
| 254 | DIP switch S551 and JP1 | PSX.sv:904 |

Back-pressure: Main waits for the core's acknowledge on every word, and the
core holds ioctl_wait while an SDRAM write, the card line write or the
loader FIFO is busy (PSX.sv:1256-1271).

### 5.2 Reset while loading

Every G-NET download, the BIOS download, the OSD reset, a watchdog expiry
(stretched to 255 clk_1x cycles) and the CPU PLL's lock all feed reset_or
(PSX.sv:317-341), which is registered into `reset` (PSX.sv:1597) and
reaches psx_top as reset_in (rtl/psx_top.vhd:974). The core is held in
reset during every G-NET download and released between them
(docs/fullsys_sim.md 5.3, a full-system simulation of the download path).

### 5.3 The reset sequencer (savestates.vhd)

PSX_MiSTer resets the machine through its savestate engine, and G-NET keeps
that. When reset_in falls, rtl/savestates.vhd:344 enters reset mode: it
pauses the core, reads the four slot headers (568-600), then walks the
savestate types from 12 upward with zero data, holding reset_out (240)
until the walk ends (651). With the CPU on its own clock (CPU_FILL_EXT = 1,
set from CPU_CLK_SPLIT at rtl/psx_top.vhd:2550), type 12 (scratchpad) and
type 16 (main RAM) are filled by rtl/gnet/cpu_split/cpu_reset_fill.vhd on
clk_cpu through a toggle handshake (savestates.vhd:620-635); the engine
still clears SPU RAM and VRAM. cpu_reset_fill then releases the CPU group's
reset after the savestate reset pulse, never in the same cycle
(docs/r1_cpu_domain_design.md, "Crossings as built", C17). zn2_board takes
the CPU group's reset; zn2_cardmem and the Zoom board take the engine's
reset_intern_p (docs/r1_cpu_domain_design.md, "ZN-2 layer in the CPU
group", Reset order).

### 5.4 From reset to the game

The CPU starts in the BIOS. The BIOS runs the CAT702 security exchange over
SIO0, decrypts the sub-BIOS from flash U30 and runs it
(docs/ACCURACY.md 5.2). The card is unlocked at every boot, cold or warm
(docs/m0_findings.md 3), and the game is loaded from it.

Quick start MRAs (the main ones) load the flash area as it is after the
first-boot copy, rebuilt offline from the card by tools/build_flash.py and
byte-identical to MAME's NVRAM (docs/ACCURACY.md 6.2). First boot MRAs
load only flash.u30 and 8 MB of FFh; the BIOS then erases and programs the
other four chips from the card, word by word, through gnet_flash (about
137.7 s of copy in MAME's timing, docs/m0_findings.md 3). Every program and
erase goes to SDRAM through channel 3 and from there to the DDR3 mirror. The
release uses gnet_flash PRESET 1, MAME 0.288's timing (instant program,
1.0 s block erase on the 2 MB chips; rtl/gnet/gnet_flash.sv:40-52). The flash is not saved, so a first
boot MRA repeats the copy at every load (docs/ACCURACY.md 6.3).

The Zoom board stays in reset while control register bit 4 is 1; when the
game clears it, the MN10200 runs the U27 program from the DDR3 copy through
its program cache (rtl/zoom/zoom_board.sv:48-56). Sets without a Zoom board
keep it in reset through bit 1 of the configuration byte, as MAME's
`init_nozoom` (docs/ACCURACY.md 7.7).

The watchdog (gnet_ctrl, MB3773 model, 8 s, PSX.sv:316) resets the whole
core when the game stops kicking it, unless the OSD Watchdog item is Off;
it is masked while paused and for 8.5 s after (PSX.sv:1613-1623).

## 6. Build switches of the release

### 6.1 Macros (GNET_Z1FULLR.qsf)

The revision sets 29 VERILOG_MACROs. All GNET_ macros are read in PSX.sv;
the RTL files only mention them in comments. With none of them defined,
revision PSX builds upstream PSX_MiSTer (PSX.sv:35-41; last checked on
2026-10-04, docs/f0_budget.md 3.1, before most edits, so needs-review).

| Macro (qsf line) | Read at (PSX.sv) | Effect |
|---|---|---|
| MISTER_FB (54), MISTER_DOWNSCALE_NN (57), MISTER_DISABLE_ALSA (66), MISTER_DISABLE_YC (80), MISTER_DISABLE_ADAPTIVE (81) | sys/ | framework options: frame buffer, no bilinear downscale, no ALSA, no YC output, no adaptive scanlines |
| GNET_NO_CD, GNET_NO_PADS, GNET_NO_SAVESTATES, GNET_NO_CHEATS (75-78) | 1652-1671 | psx_top HAS_CD, HAS_PADS, HAS_SAVESTATES, HAS_CHEATS = 0: console blocks G-NET does not have |
| GNET_LEAN (79) | 183, 1644-1648 | fixed 53.693175 MHz video PLL; console-only OSD options become constants through `GNET_OPT(live, fixed)` |
| GNET_VRAM_2MB (87) | 1696 | VRAM_Y_BITS 10: the CXD8654Q's 1024 x 1024 VRAM |
| GNET_GTE_NARROW_MUL=3 (88) | 1701 | GTE at 100 MHz with the same results and step counts (rtl/gte.vhd); 1 and 2 are earlier experiments |
| GNET_ZN2 (91) | 1737 and others | ZN2_BOARD 1 (zn2_board, loader, arcade inputs) and RECT_FLIP 1 (textured rectangle flip, issue #6) |
| GNET_CLK_RATIO2 (104) | 1751 | CLK_FAST_RATIO 2: the SDRAM and request strobes run 2:1 to the CPU; only valid with GNET_CPU50 (PSX.sv:1744-1750 says nothing rejects the other pairing) |
| GNET_CPU50 (105) | 139, 1786 and others | the CPU group on pll_cpu (CPU_CLK_SPLIT 1), SDRAM on clk_cpu2x |
| GNET_SHELL (113) | 361 and others | the arcade OSD, rotation, CRT position, volume, pause options, coin pulse, Dash, EEPROM save |
| GNET_DDR3_ARB (125) | 81, 1711 and others | gnet_ddr3_arb in front of DDRAM; ZOOM_INFL 8 |
| GNET_ROT_DDR (130) | 600 | shows the Orientation and Rotate Direction items (screen_rotate is connected) |
| GNET_ZOOM (134) | 1706 and others | ZOOM_BOARD 1: the Taito Zoom board and the SPU and Zoom mix |
| GNET_READ_OVERLAP (158) | 1765 | memorymux ZN2_READ_OVERLAP: an expansion read issues its request as its delay starts |
| GNET_EARLY_READY (179) | 1758 | sdram.sv EARLY_READY: a 2:1 RAM read ready one fast edge earlier (issue #5) |
| GNET_RAM_READ_NOWAIT (180) | 1779 | memorymux RAM_READ_NOWAIT at 2:1 (issue #5) |
| GNET_TEX_FETCH_QW=4 (192) | 1722 | GPU texture cache fill of 4 qwords per miss |
| GNET_TEX_FETCH_ROWS=2 (193) | 1727 | the next texture row fetched with it |
| GNET_GPU_READ_INFL=2 (194) | 1717 | two VRAM reads in flight |
| GNET_TEX_MISS_DELAY=13 (200) | 1732 | 13 clk_2x of wait after each texture fill, calibrated to the board's slowdown (docs/gpu_read_infl.md 10) |
| GNET_DDR3_LOAD (211) | 797, 1177, 1231, 2842, 2918 | the MRA DDR3 load path for the flash area (section 4.4, issue #12); needs GNET_DDR3_ARB |
| GNET_NO_DBG (221) | 401, 416, 1691, 3097 | no debug overlay, no capture block (psx_top ZN2_DBG 0), no Debug overlay OSD item (docs/area.md 3.1) |
| GNET_NO_DCACHE (222) | 1680 | with GNET_LEAN: cpu HAS_DCACHE 0, the turbo data cache is not built (TURBO_CACHE is tied to 0, so its data was never used; docs/area.md 3.3) |

The qsf also fixes the fitter seed (SEED 8, line 171, with the history of
each seed in the comments above it), places the HDMI PLL output on
counter C0 (line 176, issue #8: Main_MiSTer reprograms only C0) and reads
GNET_HDMI_FITOC.sdc (line 204, F1, section 3.3).

### 6.2 Generics

I added 26 generics to psx_top, each defaulting to upstream behaviour or to
a value that only matters with ZN2_BOARD or ZOOM_BOARD set
(rtl/psx_top.vhd:54-104, one comment each). PSX.sv sets them from the macro
table (PSX.sv:1818-1844). Values in the release:

| Generic | Release | Default in psx_top |
|---|---|---|
| HAS_CD, HAS_PADS, HAS_SAVESTATES, HAS_CHEATS | 0 | 1 |
| HAS_MDEC | 1 (always, issue #1) | 1 |
| HAS_DCACHE | 0 (GNET_NO_DCACHE with GNET_LEAN) | 1 |
| VRAM_Y_BITS | 10 | 9 |
| RECT_FLIP | 1 | 0 |
| GTE_NARROW_MUL | 3 | 0 |
| GPU_READ_INFL, TEX_FETCH_QW, TEX_FETCH_ROWS | 2, 4, 2 | 1, 1, 1 |
| TEX_MISS_DELAY | 13 | 0 |
| CLK_FAST_RATIO | 2 | 3 |
| CPU_CLK_SPLIT | 1 | 0 |
| ZN2_BOARD, ZOOM_BOARD | 1, 1 | 0, 0 |
| ZN2_WD_TIMEOUT_S | 8 | 8 |
| ZN2_DBG | 0 (GNET_NO_DBG) | 1 |
| ZOOM_INFL | 8 | 4 |
| ZN2_READ_OVERLAP, RAM_READ_NOWAIT | 1, 1 | 0, 0 |
| RAM_LOAD_WINDOW | 7 | 7 |
| ZN2_FLASH_PRESET, ZN2_PS1_SIO, ZN2_SPU_STATUS | 1, 0, 0 (PSX.sv never sets them) | same |

The last three keep alternative readings of open research items as
one-line switches; only simulations use the other values
(rtl/gnet/zn2_board.vhd:56-60).

Derived inside psx_top, not set from PSX.sv: mdec IDCT_REG_STAGE =
CPU_CLK_SPLIT (rtl/psx_top.vhd:1993), spu MLAB_WR_NEGEDGE = ZN2_BOARD
(2039), memorymux ZN2_MAP = ZN2_BOARD (2140), cpu B2B_RAM_COMP = 1 -
RAM_READ_NOWAIT and HAS_DCACHE (2313-2314), savestates CPU_FILL_EXT =
CPU_CLK_SPLIT (2550).

Zoom board instance (rtl/psx_top.vhd:3624-3625): CLK_H 4, PACE_CAP 1024,
ZSG_INFL 8, TIMER_EXACT 0, DEBUG 0; the other parameters keep their
defaults, among them READB_SHIFT 3 (MAME 61c7940's ZSG-2 register 0xB
read), MAME_GAIN 0 (MB87078 volume law), RST_LEVEL 0 and TMS_MAME 0 (the
TMS57002 User's Guide) (rtl/zoom/zoom_board.sv:57-78).

### 6.3 What is built but optional

The debug overlay (zn_dbg_regs, zn_dbg_overlay) was in the alpha 3
release, Off by default on the OSD (status bit 101), at about 316 ALMs and
one M10K, with its mux in the RGB path (rtl/gnet/zn_dbg_overlay.vhd:19-25;
docs/hw_debug_overlay.md). From alpha 4 the release leaves it out
(GNET_NO_DBG, section 6.1); a debug build drops that macro.

The scandoubler blanking block (rtl/gnet/gnet_sd_blank.sv, PSX.sv:3174) is
built in every shell build and acts only while the scandoubler is on (OSD
Scandoubler Fx not None, or the forced scandoubler): it gives the lines the
GPU does not draw an hblank pulse, so the framework scandoubler keeps its
line count and vsync (issue #11, docs/i11_scandoubler.md). With the
scandoubler off its outputs equal its inputs on every clock.

## 7. Where the evidence for each part comes from

Ranks are those of docs/ACCURACY.md 1: board measurements, die-level
models, manufacturer documents, boards observed (photos, footage), MAME
0.288, other emulators. The per-chip table is docs/evidence_sources.md;
each RTL file names its own sources in its header (`Evidence:` line).

| Part | Main sources | Checked against | Design notes |
|---|---|---|---|
| CPU, GTE, GPU, SPU, DMA, timers | PSX_MiSTer (upstream); psx-spx; JaCzekanski's ps1-tests for the GPU | MAME 0.288 GPU command replay and ps1-tests images (docs/ACCURACY.md 3.2) | docs/m1_gpu_zn2.md |
| CPU clock and memory timing | IDT R3051 and LSI CW33000 manuals; PCB footage of Ray Crisis and Shikigami no Shiro; MAME 0.288 psx.cpp | full-system simulation, footage timing (docs/ACCURACY.md 2.3, 2.4) | docs/r1_cpu_domain_design.md, docs/r1_speed_study.md, docs/cpu_rate_probe.md |
| ZN-2 map, CAT702, I/O MCU, EEPROM, inputs | MAME 0.288 zn.cpp, taitogn.cpp, cat702.cpp, znmcu.cpp, at28c16.cpp, sio.cpp; AT28C16 datasheet | replays of every SIO0, CAT702 and zn2_io access of six games (docs/zn2_layer_design.md 16) | docs/zn2_layer_design.md |
| Flash chips | Intel 28F160S3, 28F160S5, 28F400B5 datasheets; MAME intelfsh.cpp where they are silent (rtl/gnet/gnet_flash.sv:16-19) | glue replay, flash images word-identical to MAME's NVRAM (docs/m2_glue_findings.md) | docs/gnet_glue_design.md |
| PC card controller and cards | Ricoh RF5C296 manual; CF+ and CompactFlash spec 1.4; MAME rf5c296.cpp, ataflash.cpp, atahle.cpp (the Taito locks exist only in MAME) | glue replay; sim/gnet_ata Type 2 and CompactFlash bench | docs/gnet_glue_design.md, docs/m2_glue_findings.md |
| Watchdog | Fujitsu MB3773 datasheet; MAME mb3773.cpp; board photos (part markings) | MAME traces of the longest kick gap per game | docs/ACCURACY.md 6.5 |
| MN10200 | Panasonic MN102L and MN102H60G manuals; MAME mn10200.cpp where they are silent | lockstep against MAME's debugger trace, 270.4 million instructions (docs/mn10200_rtl.md 4) | docs/mn10200_design.md, docs/mn10200_rtl.md |
| ZSG-2 | MAME 0.288 zsg2.cpp (no datasheet exists) and MAME commit 61c7940 for register 0xB | replay, 23.4 million samples (docs/zsg2_rtl.md 4) | docs/zoom_zsg2_tms57002_design.md, docs/zsg2_rtl.md |
| TMS57002 | TI TMS57002 User's Guide; MAME tms57002 only where the guide is silent | replay with MAME's parameter set (docs/tms57002_rtl.md 4) | docs/tms57002_rtl.md |
| Zoom board glue, mailbox, volume | MAME taito_zm.cpp and taitogn.cpp; M66220 and MB87078 data sheets | board lockstep against MAME (docs/zoom_board_design.md 10) | docs/zoom_board_design.md |
| Board facts (parts, jumpers, clocks, slowdown, sound balance) | board photos, PCB footage and one cabinet recording | | docs/board_evidence.md, docs/ACCURACY.md 2.1, 6.1 |

The MAME 0.288 sources I read are unmodified copies in my development tree
(reference/mame0288, reference/mame_61c7940); the public repository links
each one at the exact version with its md5 instead (docs/mame_sources.md).

## 8. File map: where to start reading

| To understand | Start with |
|---|---|
| What the release builds | GNET_Z1FULLR.qsf, then PSX.sv's macro table (PSX.sv:1639-1790) |
| The arcade shell and loader | PSX.sv:357-408 (OSD), 769-1162 (loader and inputs), docs/m4_shell.md |
| The core's generics and the G-NET wiring | rtl/psx_top.vhd:51-104, then 3227-3670 |
| The clock split | rtl/gnet/cpu_split/cpu_split.vhd header, docs/r1_cpu_domain_design.md "Steps 4 and 5" |
| The ZN-2 board | rtl/gnet/zn2_board.vhd header, docs/zn2_layer_design.md |
| The FC PCB glue | rtl/gnet/gnet_fc.sv, then gnet_flash.sv, gnet_rf5c296.sv, gnet_ata.sv, gnet_ctrl.sv |
| The Zoom board | rtl/zoom/zoom_board.sv header, docs/zoom_board_design.md |
| DDR3 sharing | rtl/gnet/gnet_ddr3_arb.sv header, docs/ddr3_arbiter.md |
| Loading through DDR3 (issue #12) | rtl/gnet/gnet_ddr3_flcopy.sv header, docs/i12_ddr3_load.md |
| Timing closure and area | docs/hdmi_timing.md (F1), docs/area.md |
| What I changed upstream and why | PROVENANCE.md |

## 9. Building, simulating, checking

### 9.1 Building

Quartus 17.0.2 Lite (GNET_Z1FULLR.qsf:16), project PSX.qpf, revision
GNET_Z1FULLR, for example
`quartus_sh --flow compile PSX -c GNET_Z1FULLR`. The framework's pre-flow
script writes build_id.v with the build date (sys/sys.tcl:216), and the
date is part of the netlist through the OSD version string (PSX.sv:407). A
rebuild of the release sources at seed 8 with the release's date gave the
release RBF's md5 (a4e2f4cd) on 2026-10-20, so the flow is deterministic.
I release only from a fit that meets timing on every clock (README,
"Building"). Revisions PSX and PSX_DualSDRAM are upstream's; GNET_Z1FULLO
is alpha 1.

### 9.2 Simulation

The benches are in sim/, one folder per block, each with its run or build
script; NVC 1.23 for VHDL and Verilator 5 for SystemVerilog (README,
"Building"). The ones a reviewer is most likely to want:

| Block | Bench |
|---|---|
| Clock crossing blocks, with negative controls | sim/cdc/run.sh |
| CPU group split (psx_top elaborated with the split) | sim/cpu50/run.sh |
| ZN-2 board crossings | sim/zn2cpu50/run.sh |
| CAT702, SIO0, zn2_io, memorymux | sim/zn2/run_*.sh |
| FC PCB glue (MAME replay and directed tests) | sim/gnet/ |
| Card types | sim/gnet_ata/tb_ata_t2.sv |
| DDR3 arbiter, Zoom port, flash mirror | sim/ddr3arb/run.sh |
| MN10200, ZSG-2, TMS57002 against MAME | sim/mn10200/, sim/zsg2/, sim/tms57002/ |
| Zoom board and its integration | sim/zoomboard/, sim/zoomlink/, sim/zoomddr3/ |
| GPU replay and ps1-tests | sim/m1/, tools/gpu_stream.py, tools/ps1test_stream.py |
| GPU texture prefetch | sim/gpuinfl/ |
| MDEC on the CPU clocks, against the base commit | sim/mdec/run.sh |
| Shell blocks (volume, coin pulse, CRT position, dot clock, pause, Dash, arcade_video) | sim/shell/run_*.sh |

Replays against MAME need MAME 0.288 and your own ROM files; the trace
scripts are in tools/mame/. Game-derived data from these runs (traces,
frames, NVRAM, card images) stays in gitignored folders.

Static checks in this tree:

- `python3 tools/lint_psx.py GNET_Z1FULLR`: Verilator lint of PSX.sv with
  the revision's macros, VHDL entities stood in by their port lists.
- `python3 tools/upstream_marks.py --all`: every change in an upstream file
  is marked `G-NET:` or covered by its header notice (PROVENANCE.md).
- `python3 tools/comment_only_check.py --base <commit> --qsf
  GNET_Z1FULLR.qsf`: proves that an edit changed comments only.

### 9.3 Regression net

The regression net checks that a refactor or a timing change leaves the
release's behaviour as it was. It is written (docs/regression.md, with
tools/regress/ and sim/regress/) but not yet merged into this tree or
published; this section describes it as written. One runner,
`tools/regress/regress.sh <tier0|tier1|tier2|tier3|all> [--dry-run]`, four
tiers:

| Tier | Proves | Time (measured) |
|---|---|---|
| 0 | every file the revision compiles analyses in GHDL and Verilator, PSX.sv's connections match the VHDL entities, tools compile, shell scripts pass shellcheck; no finding the baseline lacks | about 10 s |
| 1 | 46 module bench runs pass, including the memory latency rows against their goldens, the MDEC word for word and cycle for cycle against the base commit, and every negative control still failing | about 13 minutes |
| 2 | five shooter warm boots (and the CompactFlash sets) produce the golden frames, GPU command stream and Zoom mailbox writes, identical or the same content shifted in time | about 3.2 h per game; about 10 h for 7 games with 3 jobs |
| 3 | a Quartus build fits within resource thresholds, meets timing on every clock and corner, and has the HDMI PLL counter where Main_MiSTer expects it | under 1 s (reads the reports) |

Tier 2's verdict is IDENTICAL, TIMING (same content, shifted) or CONTENT
(something new on screen, in the GPU stream or in the Zoom mailbox), with
the first differing time.

## 10. Open items that affect this map

- Revision PSX has not been re-checked against unmodified PSX_MiSTer since
  2026-10-04 (section 6.1).
- gpu.vhd tests `fifoOut_Dout(85)` where it should test F_SRC; the release
  cannot reach it, because GNET_LEAN ties the 480p interlace hack off
  (PROVENANCE.md).
- zn2_io's Zoom mailbox stub, which the release never reaches (the Zoom
  port takes those addresses, rtl/gnet/zn2_board.vhd:36-39), is not built
  with ZOOM = 1 from alpha 4 (ZOOM_STUB, docs/area.md 3.2; 2 M10K).
- The issue #10 polygon watchdog change in gpu_poly.vhd applies to every
  build, revision PSX included; it is not behind a generic yet
  (PROVENANCE.md).
- A full DDR3 load (flash and card addresses) gives ERROR C094 on hardware
  with the alpha 4 RBF; under investigation on branch i12-ddr3load
  (section 4.4).
- What the board's watchdog period, CPU clock, card latency and SPU
  against Zoom balance really are: docs/ACCURACY.md 9 lists the evidence
  that would settle each.
