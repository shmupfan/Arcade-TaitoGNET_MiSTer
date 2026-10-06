# G-NET DDR3 arbiter (rtl/gnet/gnet_ddr3_arb.sv)

The command-level arbiter that docs/ddr3_bandwidth.md (branch
ddr3-bandwidth, sections 4 and 5) says rotation and the Zoom wave memory
need: the core's own DDR3 arbiter pauses the GPU for every foreign access
(rtl/psx_top.vhd:896), and screen_rotate ignores BUSY
(sys/arcade_video.v:195, 303-315). This module sits in front of the emu
DDRAM port instead, so neither problem reaches the core. Standalone RTL
with a testbench; not yet wired into PSX.sv (section 4).

## 1. Function

On the port clock (clk_2x, 67.7376 MHz, PSX.sv:1430). Four clients,
highest priority first:

| Client | Interface | Traffic |
|---|---|---|
| R rotation | screen_rotate's DDRAM_* outputs on its own clock (CLK_VIDEO), into a dual-clock FIFO of 512 entries | 1-beat writes, at most one per 8 video clocks |
| Z Zoom | zoom_memarb's m_* port (branch zoom-board, rtl/zoom/zoom_memarb.sv): m_req and m_line held until ready, m_rvalid in order | 1-beat line reads, up to 8 in flight; line L is qword ZQBASE + L, ZQBASE = 0x31000000 / 8 (the flash area, U27 at +0x200000, waves at +0x400000, zoom_board.sv:39-40) |
| G glue | Avalon master (card sector engine, flash chips in DDR3) | reads of any length, writes and write bursts |
| C core | Avalon master: psx_mister's DDRAM side (GPU, SPU and savestates behind the core's pause arbiter, unchanged) | every remaining slot |

- A one-entry command register holds the command presented downstream; it
  takes a new client command when it is free or being accepted. An Avalon
  client sees BUSY low only in the cycle its command is taken, so the GPU's
  existing handshake (rtl/gpu.vhd:1638-1641) works unchanged.
- A write burst (burstcount > 1) locks the port to its client until the
  last beat.
- An owner FIFO (16 entries) records {client, length} for every read
  accepted downstream; DOUT_READY goes only to the owner of the head
  entry. The core therefore sees only its own beats, which keeps psx_top's
  broadcast DOUT_READY (rtl/psx_top.vhd:1609, 1761) correct.
- Nothing is acknowledged in reset.
- Status: rot_ovf (sticky: a rotation write found the FIFO full and was
  dropped), rot_hiwater (highest FIFO level), own_ovf (protocol error).

Expected size: about 300 ALMs and 2 M10K (the rotation FIFO, 512 x 69
bits); not fitted.

## 2. Testbench

`sim/ddr3arb/run.sh <seed> <cycles> <busy %> <lat base> <lat jitter> [stall]`
(Verilator). A DDRAM port model (random BUSY plus a 20-cycle BUSY run
every 3,000 cycles, read latency base + uniform jitter, in-order beats, a
memory of qwords) serves four clients in disjoint regions:

- C: GPU-like, one read in flight (1, 4, 80 or 128 beats) or a single
  write, reads back what it wrote;
- G: 64-beat reads and 4-beat write bursts, reads its bursts back;
- Z: up to 8 line reads in flight, requests already during reset;
- R: screen_rotate's pattern on a 53.693 MHz clock (320 pixels per
  3,413-clock line, one per 8 clocks, 960-byte stride).

It checks every read's data, the stability of the downstream command
while BUSY (Avalon), that nothing is acknowledged in reset, no owner FIFO
overflow, and at the end that every rotated pixel holds its last value.

| Run (seed, cycles, BUSY %, latency) | Core reads, latency mean / max | Zoom reads, latency mean / max | Rotation writes, FIFO high-water | Result |
|---|---|---|---|---|
| 2, 2 M, 10%, 14 to 22 | 25,739, 23.2 / 86 | 33,332, 63.9 / 209 | 148,675, 2 | pass |
| 3, 1 M, 40%, 40 to 80 | 8,274, 65.6 / 144 | 16,560, 92.6 / 262 | 74,333, 2 | pass |
| 4, 1 M, 5%, 4 to 6 | 15,332, 10.3 / 71 | 16,461, 59.7 / 194 | 74,333, 2 | pass |
| 6, 1 M, 25%, 20 to 50 | 10,253, 40.8 / 113 | 16,528, 74.2 / 233 | 74,333, 2 | pass |
| 5, 1 M, 10%, 14 to 22, BUSY held 120 us once | 12,591, 23.2 / 86 | 16,437, 64.1 / 207 | 74,333, 512 | pass: rot_ovf set, 79 pixels dropped as expected |

- The rotation FIFO never held more than 2 entries without the forced
  stall, even with BUSY 40% of the time: at top priority it waits only on
  BUSY. The 512 entries are for stalls of the HPS port that this model
  does not have; the latency probe (branch ddr3-latency-probe) measures
  the real BUSY runs.
- Zoom latency stays within the bound of docs/ddr3_bandwidth.md 4.4,
  L + 193 clk_2x (a 128-beat core burst and a 64-beat glue burst can be
  ahead of it): 262 at L up to 80. That is 131 clk_1x, inside the ZSG-2's
  192 at INFL 8 for 48 key-ons at once and over the 96 of INFL 4, as the
  study predicted. INFL 8 is the setting for the DDR3 build.
- Two injected faults are caught: core DOUT_READY also given for glue
  beats (97,497 errors), rotation never selected (FIFO full, rot_ovf, every
  pixel wrong).
- One real bug found and fixed here: in reset the command register is
  held, but z_ready was combinational and acknowledged a Zoom request that
  was then lost. load is now gated by reset.

## 3. Limits

- Client G must not issue a read while it has a write burst in progress
  (Avalon forbids it anyway); the lock blocks every other client during
  the burst, so bursts should stay short.
- No starvation guard for the core: rotation, Zoom and glue together take
  at most about 10% of the slots in the worst frame
  (docs/ddr3_bandwidth.md 4.1). A glue client that streams continuously
  would starve the core; the sector engine reads one sector per command.
- The Zoom port is on clk_2x. If zoom_memarb runs on another clock it needs
  a crossing in front of this module.

## 4. Integration (branch ddr3-arb-int, from gnet-cpu50 048cf9e)

Macro GNET_DDR3_ARB (with GNET_ZN2 and GNET_CPU50), revision GNET_Z1_DDR3
(GNET_Z1_CPU50 plus the macro and the three files), pc_build target z1ddr3.
In PSX.sv:

- psx_mister's DDRAM_* go to the arbiter's C port (core_ddr_*); the emu
  DDRAM_* come from the arbiter; DDRAM_CLK stays clk_2x. The core's own
  pause arbiter is unchanged behind the C port: SPU, card image and the
  savestate reset fill still pause the GPU, as before. Rotation, Zoom and
  the flash mirror never do. The card moves to the G port with the sector
  engine (next task).
- The arbiter resets only at power-up (pll_locked): the core keeps reads
  in flight across its own resets, and the owner FIFO has to keep matching
  them.
- Rotation: screen_rotate (sys/arcade_video.v) takes the core's final video
  (video_gamma, ce_pix, clk_vid) and writes into the R port; FB_* come from
  screen_rotate when gnet_rot_en is 1, from the core's own FB mode
  otherwise. gnet_rot_en and gnet_rot_ccw are PSX.sv wires driven by the
  release shell (branch gnet-shell); tied to 0 here. Its video_rotated
  output goes to hps_io (as in the MiSTer template).
- With the release shell (GNET_SHELL, branch gnet-full, revision
  GNET_Z1FULL = GNET_Z1SHELL plus GNET_DDR3_ARB and GNET_ROT_DDR, pc_build
  target z1full): the shell declares and drives gnet_rot_en (vertical set,
  Orientation Vertical, not direct_video) and gnet_rot_ccw (Rotate
  Direction); this block's declaration and tie-offs are under
  `ifndef GNET_SHELL. screen_rotate takes the gamma-corrected video before
  any scandoubler, with the core's dot enable, on clk_vid: a second
  gamma_corr (rot_gamma, PSX.sv VIDEO section, same gamma table read from
  gamma_bus) on the debug overlay's output, as the non-shell wiring and
  XelaNotPu's ZN2 core do. Until gnet-full 2c8476d it took arcade_video's
  outputs (the MiSTer template's way: after gamma and the scandoubler Fx).
  sim/rotfx (arcade_video -> screen_rotate -> this arbiter -> DDRAM model
  with GPU-like core traffic, G-NET's 240-line raster, clk_vid 53.69 MHz,
  clk_2x 67.74 MHz) measured both:

  | Feed, 640 dots | Fx none | Scanlines | HQ2x |
  |---|---|---|---|
  | arcade_video, BUSY 10%, latency 14+8 | high-water 4 of 512 | 9 | 22 |
  | arcade_video, BUSY 40%, latency 40+40 | 5 | 12 | overflow (99 pixels wrong) |
  | arcade_video, BUSY held 20 us / 40 us | 101 / 369 | 323 / overflow | overflow / overflow |
  | pre-scandoubler (now), any Fx, same loads | 4; 5 (BUSY 40%), 7 (BUSY 60%), 102 / 371 (held 20 / 40 us), never an overflow | same | same |

  At 320 and 512 dots the arcade_video feed reached 9 and 16 at BUSY 10%.
  Write rates at 640 dots: 9.2 M/s native, 18.4 with scanlines, 36.8 with
  HQ2x (one write per clk_vid within a line). The image check (one frame
  of screen_rotate's input against the source raster; video_mixer through
  the Verilator copy sim/rotfx/video_mixer_sim.sv, whose generate-scoped
  R_in/G_in/B_in Verilator would otherwise make implicit and black):
  pre-scandoubler feed exact at every width and Fx; arcade_video feed exact
  for Fx none and scanlines (each line twice), but 12% to 20% of the
  doubled lines carry 2 (scanlines) or 4 (HQ2x) extra pixels after the
  line, and at 320 and 512 dots the doubled stream starts with a black
  line. With the pre-scandoubler feed the rotated (HDMI) picture has no Fx;
  the Fx still apply to the unrotated output and the scaler's filters to
  the rotated one.
- Zoom: rtl/gnet/gnet_ddr3_zport.sv joins zoom_board's m_* port (clk_1x,
  PSX.sv wires zoom_m_req, zoom_m_line, zoom_m_ready, zoom_m_rvalid,
  zoom_m_rdata, and zoom_rst, the Zoom-side reset) to the Z port. Requests
  are taken only on clk_2x cycles that end on a clk_1x edge, so z_ready is
  seen as m_ready by zoom_memarb; m_line is taken on the accepting edge
  only. Answers wait in an 8-entry queue and leave as one-clk_1x pulses.
  After a Zoom reset, the answers the arbiter still owes for earlier
  requests are counted and dropped, and no pulse is shown during the reset.
  The Zoom wires are tied off in builds without the Zoom board; with
  GNET_ZOOM (branch gnet-full, revision GNET_Z1FULL) psx_top's zoom_board
  drives zoom_m_req, zoom_m_line and zoom_rst and this port answers from
  the flash mirror (GNET_ZOOM_SDRAM is ignored, ZSG-2 INFL 8).
- Flash mirror: rtl/gnet/gnet_ddr3_mirror.sv copies every channel 3 write
  into 0x1000000-0x19FFFFF (the MRA flash download and the glue's flash
  programming, both through zn2_ch3_arb on clk_cpu) to DDR3 at the same
  offset in the core's window (byte 0x31000000 up), through a 32-entry
  dual-clock FIFO onto the G port. The main CPU's flash reads stay on SDRAM.
  zn2_ch3_arb has a new input, stall (default '0'): it starts no request
  while the mirror FIFO is nearly full, so no write is lost. The 32-bit word
  keeps sdram.sv's byte order (din[15:0] at the lower address, byte enable
  0 for the lowest byte), so DDR3 holds the same bytes as SDRAM.
- Status wires (clk_2x): gnet_ddr3_rot_ovf, gnet_ddr3_rot_hiwater (of
  512), gnet_ddr3_own_ovf, gnet_ddr3_mirror_ovf; the overflow flags are
  sticky until power-up. Shown in the debug overlay's DR row in every
  GNET_DDR3_ARB build (docs/hw_debug_overlay.md 2).
- GNET_Z1_DDR3.qsf lists rtl/gnet/zn_dbg_regs.vhd and zn_dbg_overlay.vhd
  since the merge with the release shell: PSX.sv instantiates the debug
  overlay in every GNET_ZN2 build.
- Clock crossings follow rtl/gnet/cdc/cdc.sdc's names: Gray pointers and
  sticky flags start at cdc_tx_* and end at cdc_rx_s1*, so the 14 ns bound
  there applies (clk_cpu to clk_2x for the mirror). Each pointer moves at
  most once per source period (20 ns at clk_cpu, 14.76 ns at clk_2x), above
  that bound. clk_vid to clk_2x (rotation FIFO) is already false-pathed in
  GNET_LEAN.sdc. Both FIFO RAMs are forced to M10K. clk_1x to clk_2x (Zoom)
  is synchronous (one PLL).

## 5. Checks on the integration branch

- `sim/ddr3arb/run.sh zport <seed> <clk_1x cycles>`: clk_1x Zoom side
  against a clk_2x arbiter model; m_line changing while a request waits;
  Zoom resets in the middle of traffic. Four seeds, 400,000 clk_1x cycles,
  about 108,000 requests and 17 to 28 resets each: all answers in order,
  right data, none across a reset. With the drop logic disabled: 2,773
  errors.
- `sim/ddr3arb/run.sh mirror <seed> <ns> <busy %> [nostall]`: clk_cpu
  (50 MHz) to clk_2x, unrelated, 20 ms each, BUSY 5%, 30% and 70% plus
  300-cycle BUSY runs: about 227,000 writes inside the area each arrive
  once, in order, with the right qword, half and enables; about 97,000
  outside it are ignored; the stall held the source in about 25,000 cycles
  and nothing overflowed. Ignoring stall sets ovf.
- `sim/ddr3arb/run.sh arb ...` as in section 2, still passing.
- `tools/lint_psx.py GNET_Z1_DDR3`: Verilator lint of PSX.sv with the
  revision's macros, VHDL entities and IP stubbed from their port lists:
  no errors or warnings (also for GNET_Z1_CPU50). Two planted mistakes in
  the new block (a misspelt signal and a wrong pin name) were reported.

## 7. Card sector engine (branch ddr3-card)

rtl/gnet/gnet_card_sector.sv replaces zn2_cardmem when GNET_DDR3_ARB is
set: psx_top's new generic CARD_EXT = 1 (passed through psx_mister) drops
zn2_cardmem and brings the card storage port (clk2x side of zn2_cdc) out on
zn_cm_*; the card loader (zn_card_dl_*, already in PSX.sv) goes to the
engine directly. With CARD_EXT = 0 nothing changes.

- Same interfaces as zn2_cardmem: loader words in ascending order, four per
  64-bit write, dl_busy holding ioctl_wait; the storage port's handshake
  (request held until cm_ack, cm_ack two clk2x cycles, the next request
  taken after the request has dropped). Card byte b is DDR3 byte
  0x34000000 + b (zn2_cardmem's BASE).
- A 512-byte buffer (64 qwords, one M10K) holds one sector. A read miss
  fetches the whole sector as one 64-beat burst; gnet_ata reads the 256
  words of a sector in order, so a sector costs one burst instead of 64
  single reads through the core's pause arbiter, and no GPU pause.
- Writes are one-beat DDR3 writes with the word's byte enables; a write to
  the buffered sector also updates the buffer. A loader write to the
  buffered sector drops the buffer.
- Beats owed for a burst are absorbed if the engine is reset meanwhile
  (it resets only at power-up, as the arbiter).
- rtl/gnet/gnet_ddr3_gmux.sv shares the glue port between the flash mirror
  (first) and the card engine.

Bench: `sim/ddr3arb/run.sh card <seed> <ops> <busy %>`: a gnet_ata-like
client (256-word sector reads in order, word writes into buffered and other
sectors with read-back, loader phases over buffered sectors) against the
port model. Seeds 1 to 4, BUSY 0% to 60%: every word read matches the card
shadow (about 270,000 words per 2,000 operations), one 64-beat burst per
sector read that misses, DDR3 equal to the shadow at the end. With the
buffer update on a write hit removed: 175 errors.
`tools/lint_psx.py GNET_Z1_DDR3` stays clean; psx_top and psx_mister
analyse in NVC with the zn2 system build (sim/zn2/system/build.sh ... 1).

## 8. On gnet-full-next

The card sector engine has its own macro there, GNET_CARD_EXT (with
GNET_DDR3_ARB): it sets psx_top CARD_EXT = 1, brings the card storage port
out and puts gnet_card_sector behind the flash mirror on the glue port.
Without it the glue port carries the flash mirror alone, as in GNET_Z1FULL.
Revision GNET_Z1FULL2 = GNET_Z1FULL + GNET_CARD_EXT (+ the GPU read latency
macros of docs/gpu_read_infl.md 9, commented until the probe gives L),
pc_build target z1full2.

## 9. Zoom request skid register (clk_2x timing)

GNET_Z1FULL's fit missed setup on clk_2x by 0.020 ns
(builds/z1full_clk2x, tools/sta/clk2x_worst.tcl): every failing path ran
from zsg2_fetch's mem_req (clk_1x) through zoom_memarb, gnet_ddr3_zport's
combinational z_req, the arbiter's priority select and c_busy into the GPU
(VRAMIdle, the request size and wrap adders) to gpu reqVRAMwrap, 13.7 ns of
a 14.762 ns window; zoom_pcache's f_rq took the same route (+0.439 ns).
GNET_Z1FULL2 met it with +0.139 ns, so the path is real and its result
depends on placement. gnet_ddr3_zport now takes a Zoom request into a
one-entry register at the clk_1x edge whenever the register is free
(m_ready from registered state only) and offers the register to the
arbiter: the Zoom request no longer reaches the arbiter, the core's BUSY or
the GPU in the same cycle. One clk_2x more latency per line.

Checks: sim/ddr3arb zport bench, 4 seeds of 400,000 clk_1x cycles, about
115,000 requests and 14 to 19 Zoom resets each, 0 errors (the bench now
checks the Zoom side's own order and that m_ready is only high in cycles
ending on a clk_1x edge). sim/zoomddr3 tb_zd3 on the i5canary replay (Ray
Crisis, flash at sim/flash/raycris): 0 errors; aud.bin and mbx.log
identical to the run before the change; 219,659 instructions in both, two
stretches of 3 records differ (PCs 0834a4 to 0834a9) and reconverge.
