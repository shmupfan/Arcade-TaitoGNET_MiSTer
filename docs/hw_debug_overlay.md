# Hardware debug overlay (G-NET builds)

Status: 2026-10-05, branch hw-debug-overlay (from gnet-cpu50 e775367).
Simulated (NVC unit and end-to-end benches, Verilator lint of PSX.sv); not
yet through Quartus or on a MiSTer.

Purpose: see on the MiSTer what the core is doing when it misbehaves, in
particular the Shikigami warm boot loop (G-NET logo, loader reaches
COMPLETE, reset, about 25 s per loop). The prime suspect is the MB3773
watchdog (gnet_ctrl, then 5 s, 8 s since hw-debug-overlay 878ad18) firing while the game runs a long software delay
after the loader. The overlay shows live values and a snapshot taken at the
moment the watchdog expires, kept across the reset it causes.

## 1. Turning it on

OSD, G-NET menu: "Debug overlay" Off / On, status bit 101 (`O[101]`, next
to "Watchdog" on bit 100). Default Off. With Off the RGB the core sends to
the framework is the same value as without the overlay for every pixel (the
mixer passes `video_aspect`'s RGB unchanged; checked in simulation on every
video clock of two frames). Every G-NET build (macro GNET_ZN2, revisions
GNET_Z1 and GNET_Z1_CPU50) carries it.

The "Watchdog" option and the overlay are independent: with Watchdog Off
the MB3773 model still expires every period (8 s) without kicks, the overlay still
takes its snapshot and counts the expiry, but no reset follows.

## 2. What it shows

A black box near the top left of the active picture (16 dots and 16 lines
in from the first active pixel), 10 rows of white 5x7 text in 8x8 cells:
a two-letter label, then 8 hex digits in two groups of 4. At 512 and 640
dots per line each font pixel is two dots wide, so the box keeps its size.
The values are read once per frame, during vertical blanking, so a frame
never mixes two values of the same row. All numbers are hexadecimal.

```
PC 8003 F00C    live: CPU fetch PC
DA 8012 3456    live: last CPU data address
IO E801 1814    live: control reg | watchdog expiries | last 1F80xxxx address (low half)
MS 0000 0028    live: ms since the core reset was released
WD 0028 0028    live: ms since the last watchdog kick | largest such interval since power-on
RS 0101 0005    live: watchdog resets | other resets | ATA sector commands
XP 8001 2ABC    snapshot at the last watchdog expiry: PC
XD 8004 0000    snapshot: last data address
XI 0003 1044    snapshot: ms since the last kick | last 1F80xxxx address (low half)
XM 0000 0003    snapshot: ms since the core reset was released
```

(The text above is the frame the end-to-end bench decoded, section 5.)

In builds with the DDR3 arbiter (macro GNET_DDR3_ARB: revisions
GNET_Z1_DDR3 and GNET_Z1FULL) the box has an eleventh row:

```
DR 1010 01A3    live: DDR3 arbiter status (docs/ddr3_arbiter.md)
```

Without the arbiter the row is not built (zn_dbg_overlay generic DR_ROW =
0, PSX.sv ties the word to 0) and the box keeps its ten rows.

| Row | Digits | Meaning |
|---|---|---|
| PC | 8 | cpu.vhd `PC`: the fetch address, a few instructions ahead of execution; in a tight loop it walks the loop body |
| DA | 8 | address of the last load or store the CPU sent to memorymux (RAM, BIOS, I/O, expansion). Scratchpad accesses stay inside the CPU and do not show |
| IO | 2 + 2 + 4 | control register 0x1FB40000 as gnet_ctrl holds it (reset value 10h; the games alternate C8h/E8h, bit 5 is the watchdog clock); watchdog expiries since power-on (saturates at FF); low half of the last data address in 0x1F80xxxx (any segment: 1F801070 is I_STAT, 1F801044 SIO0 status, 1F801814 GPUSTAT) |
| MS | 8 | ms since the core reset was last released; the reset sequencer's zero fill (about 90 ms, CPU paused) is included |
| WD | 4 + 4 | ms since gnet_ctrl's watchdog counter was last reloaded (a kick, a core reset or an expiry) and the largest value since power-on. The watchdog fires when this reaches 8000 = 1F40h (the 8 s period; 5000 = 1388h in builds before 878ad18) |
| RS | 2 + 2 + 4 | resets caused by the watchdog, other resets (power-on, OSD reset, downloads), both since power-on and saturating at FF; READ SECTORS (20h) and WRITE SECTORS (30h) commands written to the card's command register while it takes commands (not busy, device selected; counted even when the card answers with an error, as while locked), wraps at FFFF |
| XP, XD | 8 | PC and last data address at the last expiry |
| XI | 4 + 4 | ms since the last kick at the expiry (about 1F40h when the watchdog expired normally, 1388h with the old 5 s period), last 0x1F80xxxx address at the expiry |
| XM | 8 | ms since the core reset was released, at the expiry |
| DR | 1 + 1 + 1 + 1 + 4 | GNET_DDR3_ARB builds only. Digit 1: rotation FIFO overflow (gnet_ddr3_rot_ovf, a screen_rotate write was dropped); digit 2: owner FIFO overflow (gnet_ddr3_own_ovf, protocol error); digit 3: flash mirror FIFO overflow (gnet_ddr3_mirror_ovf, a channel 3 flash write was not mirrored); each 0 or 1 and sticky until power-up; digit 4: 0; last four: the rotation FIFO high-water mark (gnet_ddr3_rot_hiwater, 0 to 200h of 512 entries). Normal: `DR 0000 000x` with a small high-water mark |

The snapshot rows read 0 until the first expiry and then keep the last
expiry until power-off (a new core load); no reset clears them.

A reset counts as a watchdog reset when an expiry came less than 100 ms
before it. The core reset is a short pulse train (one pulse per release,
repeated until the CPU pauses), so pulses closer than 2 ms count as one
reset.

## 3. Reading it for the boot loop

1. Let the loop run once or twice, then photograph the box. On a vertical
   CRT the text is drawn in raster orientation, so it runs along the
   monitor's long axis; rotate the photo.
2. RS first byte counting up by one per loop and IO second byte counting
   with it: the watchdog causes the loop. RS second byte counting instead:
   something else resets the core.
3. XI first half near 1F40h: the watchdog expired after 8 s without a
   kick (as the MB3773 model should). XP and XD say where the CPU was:
   compare XP with the loader and delay loop addresses from MAME
   (`tools/mame` traces) or the fullsys-sim run. XM says how long after
   reset release it happened.
4. WD second half (largest interval without a kick) close to 1F40h on a
   run that does not loop means the game is near the limit.
5. MS and WD first half growing together with no kick, while PC stays in
   one small range: the CPU is in a loop that does not touch the control
   register.
6. RS last four digits: whether the card is still being read (ATA sector
   commands taken).

## 4. How it is built

| Part | File | Clock |
|---|---|---|
| Fetch PC output `debug_pc` | rtl/cpu.vhd (one port, one assignment) | CPU |
| Taps: `wd_kick`, `ctrl_q` (gnet_ctrl), `dbg_sec_cmd` (gnet_ata), through gnet_fc and zn2_board as `dbg_wd_kick`, `dbg_ctrl`, `dbg_sec_cmd` | rtl/gnet/gnet_ctrl.sv, gnet_ata.sv, gnet_fc.sv, zn2_board.vhd | zn2_board's |
| Capture: counters, snapshot, word mux | rtl/gnet/zn_dbg_regs.vhd, psx_top generate `gzndbg` (ZN2_BOARD = 1) | clk_cpu (GNET_CPU50) or clk1x |
| Video side: handshake, word RAM, font ROM, text, mixer | rtl/gnet/zn_dbg_overlay.vhd, PSX.sv instance `dbg_ovl` between `video_aspect` and `gamma_corr` | clk_vid, stepped by CE_PIXEL |
| DR row: word `gnet_dbg_dr_word` from the four arbiter status wires, second handshake `u_hs_dr` (generate `g_dr`, DR_ROW = 1) | PSX.sv (GNET_DDR3_ARB), rtl/gnet/zn_dbg_overlay.vhd | clk_2x (source of the word) to clk_vid |
| Font | tools/gnet/dbg_font.py (generates the FONT constant) | |

- No reset input on the capture registers. They start from their
  power-up values (FPGA configuration) and only observe the core reset
  (`reset_intern`), which the watchdog drives.
- Crossings, rtl/gnet/cdc naming: the OSD bit is registered on clk_1x into
  `cdc_tx_en` and passes a `cdc_sync` into clk_vid. The words come over one
  `cdc_handshake` (source clk_vid, destination the capture clock): the
  video side sends a word index (held in `cdc_tx_req`), the capture side
  answers with the word from the mux (registered in `cdc_tx_rsp`). The
  video side asks for words 0 to 9 in turn during vertical blanking and
  stores them in a 16 x 32 RAM on clk_vid; ten round trips take about 2 us.
- DR row crossing: a second `cdc_handshake` (`u_hs_dr`, source clk_vid,
  destination clk_2x, request width 1) fetches the DR word in vertical
  blanking, in parallel with the ten-word fetch. Its answer stays in the
  handshake's capture register and is selected for row 10 after the word
  RAM's read register, so the RAM keeps one write port. clk_vid against
  clk_2x is false-pathed by GNET_LEAN.sdc (as clk_1x in GNET_Z1 above);
  GNET_CPU50_B1.sdc names the path (`emu:emu|zn_dbg_overlay:dbg_ovl|*u_hs_dr`,
  cdc_tx_* to cdc_rx_*) with the same 8 ns bound for the fit report, which
  the false path overrides. The handshake holds its data stable for at
  least two destination clocks before capture.
- Pixel timing: the counters, the RAM read, the font ROM and the mixer
  advance on CE_PIXEL only. No clock, PLL or pixel enable is added or
  changed. The text appears 3 dots to the right of its nominal position
  (pipeline), the same on every line.
- SDC: GNET_CPU50_B1.sdc no longer false-paths clk_vid against the two CPU
  clocks. The overlay's handshake is the only path between them; its
  `cdc_tx_*` to `cdc_rx_*` registers get the 8 ns bound of cdc.sdc and a
  named copy with the full `emu:emu|zn_dbg_overlay:dbg_ovl|cdc_handshake:u_hs`
  paths. A false path would override that bound. In GNET_Z1 (no CPU50)
  the crossing is clk_1x to clk_vid, which GNET_LEAN.sdc false-paths like
  every other clk_1x to clk_vid path; the handshake holds its data stable
  for at least two destination clocks before capture.
- GNET_Z1.qsf gains rtl/gnet/cdc/cdc.qip (cdc_handshake and cdc_sync were
  only used with GNET_CPU50 before); both Z1 revisions list the two new
  VHDL files.

## 5. Verification (2026-10-05)

| Check | Result |
|---|---|
| `sim/dbg/run.sh regs`: zn_dbg_regs unit bench, NVC 1.23, clocks scaled to 33,868 and 50,000 Hz | 59 of 59 checks at each rate: ms tick exact over 3 s from power-up, data and I/O address capture in KUSEG, KSEG0 and KSEG1 (0x1FA00000 not taken as I/O), control value, kicks and the no-kick counter, the largest interval, sector commands, the snapshot at an expiry, kept across the watchdog reset and a later reset, watchdog against other reset counting (burst of pulses counted once, expiry without reset, reset 150 ms after an expiry counted as other), unused words 0 |
| `sim/dbg/run.sh overlay`: zn_dbg_regs at 50 MHz, the overlay at 53.693175 MHz, OSD bit at 33.8688 MHz, metastability model on (9 ns) | option off: 1,542,657 clk_vid edges, rgb_out = rgb_in on every one; option on: 0 changed dots outside the box or in blanking; the captured frame decoded by `sim/dbg/check_frame.py` (glyph match, layout, values): 10 rows, the 8 static rows exact, MS and WD consistent. Same at 640 dots with doubling and with the model off |
| `sim/dbg/run.sh neg` | mutant "mixer ignores the option": 134,400 differing edges, bench fails; mutant "next request in the done cycle": decode fails |
| `sim/dbg/run.sh overlay`, DR row (branch gnet-full): `-gDR=1`, dr_word on an asynchronous 67.7376 MHz clk_dr, changing from 0 to 101001A3h in frame 1, at 320 dots and at 640 dots with doubling, metastability model on | option off: rgb_out = rgb_in on every clk_vid edge; 0 changed dots outside the 11-row box; decoded 11 rows, `DR 1010 01A3` exact; the three 10-row runs unchanged (8,400 and 16,800 changed dots as before). `run.sh neg` mutant "DR row shows the word RAM": decode fails |
| `tools/lint_psx.py` on GNET_Z1FULL, GNET_Z1SHELL, GNET_Z1_DDR3, GNET_Z1_CPU50 (branch gnet-full) | no warnings or errors in PSX.sv |
| `sim/gnet/build_directed.sh` (Verilator, gnet_fc with the taps) | 75 of 75 (the 67 existing checks plus 8 on the taps: kick only on a CK falling edge, control value, 3 sector commands counted from READ, READ, WRITE with ECh and C4h not counted, no kick while the watchdog runs out) |
| `sim/dbg/lint_psx.sh cpu50` and `z1`: Verilator lint of PSX.sv with the revision macros, VHDL entities as port stubs (sim/dbg/vhdl_stub.py), PLLs and Intel primitives as stubs | no errors (PROCASSWIRE, an upstream style of PSX.sv, disabled); no warning on the new lines |
| `sim/zn2/system/run.sh` with SPLIT=0 and SPLIT=1, 4 ms | psx_top with ZN2_BOARD = 1 analyses, elaborates (zn_dbg_regs bound) and runs |

A frame of the full system with the overlay on was not rendered: the
fullsys-sim harness (branch fullsys-sim) converts psx_top only, not PSX.sv,
and the NVC system bench has no PSX.sv either. The end-to-end bench above
is the frame evidence.

## 6. Cost (estimate, not fitted)

| Part | ALMs | RAM |
|---|---|---|
| zn_dbg_regs: about 320 registers, ms accumulator, five counters, the 10-way 32-bit word mux | 160 to 230 | |
| zn_dbg_overlay: handshake (about 80 registers), raster counters and compares, pipeline, text mux, 24-bit mixer | 120 to 200 | word RAM 16 x 32 (MLAB or 1 M10K), font 256 x 8 (1 M10K or about 40 ALMs of logic) |
| taps in gnet_ctrl and gnet_ata | under 5 | |
| Total | about 300 to 450 | 0 to 2 M10K |

## 7. Not verified

- Quartus 17: synthesis, RAM and ROM inference, the mixed-language
  instance from PSX.sv, the SDC collections (the named paths should match
  the fit report's `emu:emu|zn_dbg_overlay:dbg_ovl|...` names).
- With the clk_vid false paths removed from GNET_CPU50_B1.sdc, any other
  path between clk_vid and the CPU clocks would now be timed and fail. The
  SDC's own note says there is none; the first fit's clock transfer table
  confirms or refutes it.
- Placement on a real 15 kHz picture: the box starts 16 dots and 16 lines
  inside the active area as PSX.sv's `video_aspect` blanking defines it.
  On a CRT with heavy overscan it may sit partly outside the visible area.
- Text orientation: drawn in raster orientation, so on a rotated monitor
  it reads sideways.
