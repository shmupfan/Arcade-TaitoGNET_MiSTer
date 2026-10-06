# Taito Zoom board integration (M3)

Status: RTL written and verified in simulation against MAME (2026-10-05),
not fitted. Branch zoom-board: main plus mn10200-rtl, zsg2-rtl and
tms57002-rtl. Integrated into the full core on branch zoom-into-z1
(revision GNET_Z1_ZOOM, section 14), not fitted. This covers everything that connects the MN10200, the ZSG-2
and the TMS57002 to each other and to the G-NET system. Chip designs:
docs/mn10200_design.md, docs/mn10200_rtl.md,
docs/zoom_zsg2_tms57002_design.md (the design study), docs/zsg2_rtl.md,
docs/tms57002_rtl.md.

## Summary

- **RTL** (rtl/zoom/zoom_*.sv, 11 modules, about 1,200 lines): the
  MN10200 bus decoder, a 32 KB program cache over U27, 32 KB work RAM, the
  M66220FP mailbox, the main-CPU ports with an MB87078 volume model (MAME's
  linear law as an option), one virtual time base for the three chips, the
  wave and program memory arbiter, a 64-bit line to 32-bit SDRAM adapter,
  the output stage and the SPU mix. zoom_board.sv ties them to the MN10200,
  ZSG-2 and TMS57002 RTL of their branches, all merged here.
- **Verified against MAME** (61c7940 build) by a board-level lockstep
  testbench running the real firmware from tools/build_flash.py images,
  driven only by the main CPU's accesses as MAME made them: 90.6 M
  (raycris, 30 s of Zoom time) and 103.5 M (psyvaria, 34 s) MN10200
  instructions equal, every ZSG-2, mailbox and TMS57002 access equal
  including 129,788 ZSG-2 and 184 mailbox reads answered by the board, every
  ZSG-2 access at MAME's sample position, and 2.1 M ZSG-2 output samples
  equal. No divergence (10.3).
- **TMS57002 in the board** (MAME parameter set): SO1 bit-exact against
  MAME, one sample later as planned, for the first 11.4 s of psyvaria and
  6.5 s of raycris. After that it differs because 5 to 6% of the
  coefficient updates take effect one sample later than in MAME. In those
  updates the board's landing point is already past the coefficient read,
  and the board's landing point is never later than the physical one, so
  the board is right by the User's Guide timing; MAME lands them early
  because its TMS57002 lags the MN10200 inside each 60 kHz timeslice
  (10.5).
- **Decisions**: the board clock is a parameter, `CLK_H`: everything on
  clk_1x with clk_2x read ports for next-clock RAM answers (`CLK_H = 2`),
  or the split default (`CLK_H = 4`): the MN10200 side on clk_2x, the
  ZSG-2 and TMS57002 on clk_1x, synchronous crossings (4.1, 6.1); program cache 32 KB
  direct mapped, chosen from measured miss rates (4.3); wave data and U27 in the flash area of SDRAM
  now behind one line port, DDR3 later (5); sample boundaries counted in
  MN10200 machine cycles with an access lookahead (6.2); MB87078 law by
  default (3.3); ZSG-2 and TMS57002 reset at the release of control bit 4
  as MAME (9).
- **Real time**: in the split board (MN10200 retimed with `PIPE`, pacer
  cap 1,024, the MN10200 gated on the TMS57002 slot feeder) the pacer
  holds exactly 6.2500 MHz through attract and play and the output repeats
  no sample (6.4). At `CLK_H` 2 it falls 0.14 to 0.26% behind in play, and
  no pacer cap fixes it.
- **Timing**: the retimed MN10200 alone fits at 67.7 MHz (+1.723 ns), and
  the split board fits with clk_2x at +2.065 ns and clk_1x at +5.292 ns
  (6.5).
- **Open**: the PCB questions of 12; exact TMS57002 landing (I5) next.
- **Budget**: measured 4,628 ALMs at `CLK_H` 2 and 4,771 for the split
  board (11.3, 6.5), 147 to 148 RAM blocks, 5 DSP; the F0 projection's low
  case becomes about 35,000 ALMs (83.5%, 11.3).

## 1. Sources

| Rank (evidence_sources.md) | Source | Settles |
|---|---|---|
| 3 | Mitsubishi M66220SP/FP data sheet, 1990 Digital ASSP pp.3-3 to 3-8 (`mister-arcade-survey/datasheets/m66220/`) | The mailbox is a 256 x 8 dual-port RAM with an address-collision arbiter and Not Ready outputs; no flags or interrupts |
| 3 | Fujitsu MB87078 data sheet, Edition 2.0A (`datasheets/mb87078/`) | Volume control word and gain law, reset value (pp.3, 4, 6) |
| n/a | MAME 0.288 traces of the six priority games (sim/oracle, M0) and my new board trace (tools/zoom/zoom_oracle.lua) | When the main CPU touches U27, the Zoom ports and the reset bit |
| 5 | MAME 0.288 taito_zm.cpp, taitogn.cpp, zsg2.cpp, tms57002.cpp, mn10200.cpp (docs/mame_sources.md); the 61c7940 build (`gnet_61c7940`, docs/zsg2_rtl.md) | Board wiring as MAME models it; the oracle |

## 2. MN10200 memory map

From taito_zm.cpp:114-125; decoder rtl/zoom/zoom_bus.sv:60-64.

| Range | Device | Board implementation |
|---|---|---|
| 0x080000-0x0FFFFF | U27 program flash (E28F400B, 512 KB), read only | Program cache over the U27 image in the flash area (4) |
| 0x400000-0x41FFFF | Work RAM (MAME 128 KB; the PCB has one LH52B256, 32 KB, PLAN.md R7) | 32 KB in M10K, mirrored; a sticky flag marks any access above 32 KB (zoom_bus.sv:92) |
| 0x800000-0x8007FF | ZSG-2, 16-bit | zsg2.sv, with the sample lookahead (6.2) |
| 0xC00000 | TMS57002 data port, 8-bit (lane 0) | Byte write to the TMS57002 host port; reads return 0 and set a flag (the firmware never reads, design study 2.3) |
| 0xE00000-0xE000FF | M66220FP mailbox, byte addressed | Port B of zoom_mbox.sv (3.2) |
| Port 1 bits 0, 1 (0xFE64) | TMS57002 PLOAD, CLOAD | p1_out to the TMS57002 pins; port 1 input returns the last written value (MAME tms_ctrl_r, taito_zm.cpp:99-112; zoom_board.sv:145) |
| IRQ0 pin | Doorbell from the main CPU | Falling pulse of 2 clocks (zoom_board.sv:120) |
| IRQ1 pin | TMS57002 EMPTY (MAME inverts the line, so the pin is high when empty, taito_zm.cpp:198) | tms57002 `empty` |
| Anything else | Unmapped | Reads 0, writes ignored, sticky flag |

## 3. Main-CPU side

### 3.1 Ports

From taitogn.cpp:483-487; rtl/zoom/zoom_host.sv. Addresses are offsets from
0x1F000000 on the zn bus conventions of gnet_fc and zn2_io (32-bit data,
byte enables, request pulse, acknowledge pulse with data).

| Address | MAME | Board |
|---|---|---|
| 0x1FB80000 lanes 0-1 | reg_data_w (taito_zm.cpp:151-172) | MB87078 data word (3.3) |
| 0x1FB80002 lanes 2-3 | reg_address_w (taito_zm.cpp:174-177) | MB87078 control word (3.3) |
| 0x1FBA0000 | sound_irq_w: IRQ0 assert then clear | Toggle, synchronised into the Zoom clock, IRQ0 pulse |
| 0x1FBC0000 | sound_irq_r: returns 0 | Reads 0 |
| 0x1FBE0000-0x1FBE01FF | shared RAM, umask32 0x00FF00FF | Mailbox port A: lane 0 of word k is byte 2k, lane 2 is byte 2k + 1 (the same layout as the zn2_io stub on zn2-layer) |

zoom_board replaces zn2_io's silent Zoom stub (zn2_layer_design.md 12 on
zn2-layer): the integration routes these addresses to `h_*` and uses
`h_hit`.

### 3.2 Mailbox (M66220FP)

The data sheet describes a plain dual-port 256 x 8 RAM whose only extra is a
collision arbiter: when both ports select the same address, the later port
gets Not Ready and its write is blocked (pp.3-4, 3-5, Table 3). There are no
flag registers and no interrupt. MAME models a shared 256-byte RAM
(taito_zm.cpp:88-96). The board uses a true dual-port RAM with one port per
side and one clock per side (zoom_mbox.sv), written in Quartus 17's
dual-clock true dual-port template (one RAM per byte lane, write-through on
the writing port); my first version did not infer (Error 276001). The arbiter is not modelled:
MAME has none, and a same-address collision within one clock is the only
case it would change.

### 3.3 Volume port: MB87078

R12 reading (design study 2.4) as RTL (zoom_host.sv:93-125):

- The address write is the DSEL-high word: D1:D0 channel, D2 EN, D3 C0,
  D4 C32. The data write is the DSEL-low word GD5:GD0 and loads the selected
  channel's 9-bit latch with EN, C0, C32 (data sheet pp.4 and 6, Figure 2).
- Gain (p.4 table): EN = 0 mute; C32 = 1 -32 dB; C0 = 1 0 dB; otherwise
  -(63 - GD) x 0.5 dB. Reset: all channels 0 dB.
- Channel 0 is taken as left and 1 as right (needs-review, Z10).
- `MAME_GAIN = 1` selects MAME's law instead: register 4 sets the left gain
  and 5 the right gain to (data & 0x3F) / 63; the register number resets at
  the Zoom reset (taito_zm.cpp:73-79).

The games write 0x0404 / 0x3F3F and 0x0505 / 0x3F3F (0 dB), 0x3636 in
xiistag and 0x3030 in nightrai and shikigam (design study 2.4).

### 3.4 Reset bit and U27 while the MN10200 runs

Control bit 4 (gnet_fc `zoom_reset`) holds the MN10200 in reset; its
falling edge resets the whole Zoom device in MAME (taitogn.cpp:519-533),
which restarts the MN10200, the ZSG-2 and the TMS57002 and also puts U27
and the wave flashes into read array mode (gnet_flash already does that on
`zoom_release`, m2_glue_findings.md 2.1).

Does the main CPU touch U27 while the MN10200 runs? I checked the oracle
runs (sim/oracle, ctrl.log and flash.log, MAME 0.288): in all six games
(raycris warm 120 s, the other five cold 300 s) the Zoom is released at
0.0772 s, held again at 0.1256 s, and released for the game at 16.15 s
(raycris warm) or 131.0 to 155.9 s (cold runs). The 44 U27 command writes
of each cold run (the first-boot copy) all fall in the hold, and so do the
main CPU's U27 verify reads (flashrd.log, raycris 24 to 28 s). None happens
while the MN10200 runs. So the program cache is invalidated at each reset
assert and swept during the hold (zoom_board.sv:172). A `prog_inval` input
lets the glue force a sweep if a U27 write ever happens while the Zoom
runs; gnet_fc does not drive it yet (I2 in 12).

## 4. MN10200 bus timing

### 4.1 The requirement

The MN10200 core keeps real time at 33.8688 MHz only if the program and the
work RAM answer in the clock after the request (docs/mn10200_rtl.md 4.2 and
7 item 2: one wait clock per access drops the machine-cycle rate from
6.2457 to 5.91 MHz). Its bus registers the address at a clock edge and
takes `bus_ack` with the data at the next edge.

An M10K with its address port fed by that register would answer one clock
late. I use the PSX core's own scheme instead: the RAMs are clocked by
clk_2x, phase aligned with clk_1x, and the clk_2x edge in the middle of a
clk_1x cycle samples the address the core registered at the clk_1x edge;
the data is valid before the next clk_1x edge (the CPU scratchpad does
exactly this, docs/r1_cpu_domain_design.md table 1.3, cpu.vhd:2039-2055).
Each RAM output carries the index it was read at, and an answer counts only
if it belongs to the current address (zoom_pcache.sv:84-86,
zoom_wram.sv:31-39), so a stale output never acknowledges. Program cache
hits and all work RAM accesses therefore complete in the next clock with a
combinational acknowledge (zoom_bus.sv:68); everything else uses a
registered acknowledge. The timing risk is the half-cycle path from the
M10K output through the tag compare into the core (14.76 ns); the fit
project (11) checks it. This is the `CLK_H` 2 arrangement; at `CLK_H` 3 or
4 the RAMs run on the board clock and answer one clock later, through the
same index check (6.1).

### 4.2 Work RAM

32 KB (the PCB's LH52B256, R7) as 16K x 16 with byte lanes, mirrored over
0x400000-0x41FFFF: 32 M10K. MAME maps 128 KB of distinct RAM. The firmware
stays below 0x408000 statically (mn10200_design.md 3.4) and the board flag
for accesses above 32 KB stayed clear in every run (10.3).

### 4.3 Program: cache, not a copy

The 512 KB program cannot sit in block RAM (about 410 M10K). It already
lives in the flash area of SDRAM in the test-build layout (U27 at SDRAM
0x1200000, zn2_layer_design.md 13.4 on zn2-layer), so a second "full copy"
in SDRAM would add nothing: the question is only the cache in front of it.

I measured the MN10200's program reads in the board runs (every read of
0x080000-0x0FFFFF, instruction fetch and data, fed to 17 cache models in
the testbench, sim/zoomboard/tb.cpp `CacheModel`):

Misses per 1,000 instructions, direct mapped unless marked 2-way; raycris
90.6 M instructions (attract and play), psyvaria 103.5 M (attract and
play):

| Size | 8-byte lines | 16-byte lines | 32-byte lines | 16-byte, 2-way |
|---|---|---|---|---|
| 2 KB | 96.8 / 94.8 | 62.3 / 59.7 | 47.7 / 42.7 | |
| 4 KB | 54.0 / 65.1 | 35.0 / 41.3 | 31.2 / 30.6 | |
| 8 KB | 23.6 / 33.3 | 14.7 / 20.5 | 12.1 / 15.7 | 5.79 / 5.92 |
| 16 KB | 4.44 / 6.52 | 3.37 / 4.34 | 3.05 / 3.48 | 0.56 / 1.18 |
| 32 KB | 0.23 / 0.34 | 0.18 / 0.29 | 0.14 / 0.25 | |

(raycris / psyvaria). The firmware's working set during play is the code
(about 28 KB, mn10200_design.md 3.2) plus the sound data it reads, which
is why 8 KB (FX-1B's size) misses 15 to 20 times per 1,000 instructions
once the music runs, against about 1 in the first seconds after boot.

Miss cost with the SDRAM channel 3 path (zoom_line32 plus sdram.sv): about
10 clk_1x per 64-bit line (two 32-bit accesses of about 4 to 5 clocks each,
sdram.sv:418-501 and the ready path at lines 155 and 302), so 20 to 25 clocks per 16-byte
line. At 8 KB that is 0.34 to 0.47 clocks per instruction (3 to 4% of the
11.27 available), at 16 KB 0.08 to 0.10, at 32 KB under 0.01. The cost
comes in bursts when the music changes, which is when the pacer has least
slack (6.4). On DDR3 with several times the latency only 32 KB keeps it
negligible.

Decision: 32 KB, direct mapped, 16-byte lines (`PC_IDX_W = 11`,
`PC_LN_W = 1`): 32 M10K of data and 1 of tags (2,048 x 5 bits). The board
total stays under FX-1B's measured M10K (11.2), the hit path keeps one
compare (a 2-way cache would put a second compare and a way multiplexer
into the half-cycle path of 4.1), and the miss rate stays near 0.3 per
1,000 instructions whatever the memory behind it. The tag sweep at a Zoom
reset takes 2,048 clocks (60 us), far inside the shortest hold (48 ms).
The parameters allow 8 or 16 KB if M10K becomes tight. Measured in the
psyvaria board run with this cache: 30,048 misses in 103.5 M
instructions.

## 5. Wave memory path

### 5.1 Placement

6 MB of wave data (U56, U55, U29) in the flash area: SDRAM in the test
build (0x1400000-0x19FFFFF, zn2_layer_design.md 13.4), DDR3 later. Line L
of the ZSG-2 (64 bits, blocks 2L and 2L + 1, docs/zsg2_rtl.md 3.1) is byte
WAVE_BASE + 8L of the flash area (zoom_board.sv, `z_line`).

### 5.2 Ports

- zoom_board exposes one 64-bit line port into the flash area (`m_req`,
  `m_line` = byte address bits 23:3, `m_ready`, in-order `m_rvalid` /
  `m_rdata`, several outstanding).
- zoom_memarb.sv shares it between the program cache (first) and the ZSG-2
  prefetcher. A cache miss stalls the CPU at once; a ZSG-2 prefetch has a
  sample period of slack.
- zoom_line32.sv turns a line into two 32-bit word reads with a
  request / acknowledge port of the gnet_fc `fmem` style, so the
  integration arbitrates it against the glue's flash port on SDRAM channel
  3 (sdram.sv: 32-bit, one access at a time, lowest priority after the DMA
  FIFO, ch1 and ch2, sdram.sv:418-484).
- For DDR3 the line port maps one to one onto a 64-bit DDR3 read, with
  several outstanding.
- Reads into SDRAM must use byte enables 1111. sdram.sv drives ~be[1:0]
  onto DQMH/DQML with the READ command (sdram.sv:476); with the read DQM
  latency of 2 a partial mask blanks lanes of the burst on real SDRAM,
  while simulation models ignore read DQM (the first MiSTer test of the
  G-NET build failed this way). zoom_line32 drives `w_be` = 1111 and
  `w_we` = 0 as explicit ports; the line port itself carries no byte
  enables. sim/zoomboard/build_line32.sh tests zoom_line32 against a
  channel 3 model that applies read DQM (masked bytes read 0xA5): 2,000
  random lines equal, and the model's self-test with a forced 0011 mask
  fails all 2,000, so the case is caught. The board testbench's memory
  model works on whole lines and needs no mask.

### 5.3 Latency budget

docs/zsg2_rtl.md 5 (latency sweep at the worst load, 48 channels at full
pitch, 24 line fetches per sample): with `INFL` requests in flight the
engine tolerates about 43 x `INFL` clocks per line, 40 clocks at `INFL` 1
and 160 at `INFL` 4 (24 and 96 with 48 key-ons at once); the game peak is
about a quarter of that load (12 blocks per sample at most, design study
5.2). The SDRAM path serialises lines (effectively `INFL` 1) at about 10
clocks each, 4 times inside the worst-case limit and 16 times inside the
game peak. Contention with the main CPU on SDRAM (ch1 has priority) adds a
few clocks per access; even doubling the line time keeps the worst case
inside the `INFL` 1 limit. DDR3 latency through the PSX arbiter is higher
but pipelined, so `INFL` 4 covers it (needs-review against the measured
DDR3 latency of the integration).

Measured in the board runs with a 10-clock line and one line at a time:
the ZSG-2's late-block flag (`dbg_late`, a pass waited for a line) never
set in either game run (10.3), and the arbiter never overflowed. The
longest passes were 682 clocks (raycris) and 769 (psyvaria) of 1,040.

## 6. Clocks and the time base

### 6.1 Board clocks: `CLK_H`

clk is clk_1x (33.8688 MHz) and clk2x is clk_2x (67.7376 MHz), phase
aligned from one PLL. `CLK_H` (zoom_board.sv header) picks the
arrangement:

| `CLK_H` | MN10200 side (CPU, bus decoder, program cache, work RAM, mailbox port B, time base) | ZSG-2, TMS57002, slot feeder, memory arbiter, output | RAM reads | MN10200 `PIPE` | Real time in play (6.4) |
|---|---|---|---|---|---|
| 2 | clk | clk | clk2x mid-cycle, next-clock answer (4.1) | 0 | 0.14 to 0.26% slow |
| 4 (RTL default) | clk2x | clk | clk2x, one wait clock (14.76 ns, as at `CLK_H` 2) | 1 | exact |

At `CLK_H` 4 the pacer and the time base's real-time source count clk2x
(`PACE_SUB` and `RT_SUB` = 42,336 x `CLK_H`); the output stage always runs
on clk. The board's behaviour in virtual time is the same at both settings
(10.3).

Crossings at `CLK_H` 4 (zoom_board.sv, "clocks" and "time base"): the two
clocks come from one PLL, so the paths are synchronous and timed by the
fitter; no synchronisers. `s_en` marks the clk2x cycles that end on a clk
edge (a toggle on clk sampled on clk2x). A pulse from the clk2x side that
clk must see once (the ZSG-2 sample tick, the TMS57002 host byte) is held
over one `s_en` cycle; a clk-side pulse (the ZSG-2 acknowledge, the
memory port's ready and rvalid at the program cache) is taken only in an
`s_en` cycle; levels (the ZSG-2 request and address, PLOAD/CLOAD, EMPTY,
the slot feeder's SYNC pending) cross as they are. The slot feeder
(zoom_tmsfeed.sv) moved to clk: the time base publishes the cycles
stepped and the last boundary, and the feeder turns them into slots and
SYNC in order. Before a ZSG-2 access the bus decoder now also waits until
the lookahead tick has reached the ZSG-2 (`t_idle`).

- MN10200: MAME's rate needs 11.27 clk_1x clocks per instruction on
  average (mn10200_design.md 3.3). At clk_1x the board needs 9.11
  unpaced (raycris), but dense stretches of 1-cycle instructions (the
  voice-poll loop) and ZSG-2 read waits need more than they get for longer
  than any pacer cap can absorb (6.4). At clk_2x it has twice the clocks.
- ZSG-2: 1,040.45 clocks per sample at clk_1x; the longest game pass is 769
  (docs/zsg2_rtl.md 5).
- TMS57002: two clocks per instruction slot, 16.9 M slots per second
  against 12.5 M needed (docs/tms57002_rtl.md 1).
- The PSX SPU stays on clk_1x under R1 (r1_cpu_domain_design.md table at
  line 578), so the Zoom and SPU outputs mix in one domain.
- DDR3 stays on clk_2x under R1 (line 579), so a DDR3 wave and program
  path needs no crossing; SDRAM moves to the CPU domain under R1 (line
  573), so the test build's SDRAM path becomes a crossing (a dual-clock
  request and response FIFO in zoom_line32's place). That is the main
  reason to move the flash area to DDR3 later.
- Main-CPU side: `hclk` is a separate clock port. The mailbox RAM has one
  clock per port, the doorbell crosses as a toggle, the reset bit through a
  three-stage synchroniser on each side and the gains as quasi-static
  double-registered words. Under R1 `hclk` becomes clk_cpu.

The PCB's own 25 MHz is not needed as a clock: the board runs in the
MN10200's virtual machine-cycle time (6.2).

### 6.2 One virtual time base

rtl/zoom/zoom_tbase.sv. On the PCB one 25 MHz crystal clocks all three
chips: 192 MN10200 machine cycles per sample (design study 6.1). The board
counts sample boundaries in MN10200 machine cycles (`mc_step`, one per
stepped cycle), so every ZSG-2 access falls at the same sample position as
on the PCB, whatever the FPGA clocks per instruction.

MAME places an access at the end of its instruction: every cycle charge in
mn10200.cpp comes before the memory access (docs/mn10200_rtl.md 3.2). The
core steps an instruction's cycles only after it retires, so before a ZSG-2
access the bus decoder sends the instruction's cycle count (`acc_cyc`, an
output I added to mn10200_core.sv and mn10200.sv; the other MN10200
changes are `mc_step`, `ext_go` and `PIPE`, 6.3 and 6.5) and the time base
ticks a boundary that falls
inside the instruction at once, marking it so it is not ticked again when
the stepped time reaches it (zoom_tbase.sv, zoom_bus.sv `B_ZLOOK`).

While the MN10200 is held in reset, the time base counts real-time machine
cycles instead (zoom_tbase.sv `rt_cyc`): the ZSG-2 keeps rendering, as in MAME.

Sample period parameters: 192 + 0 / 1 cycles (the PCB). MAME computes the
ZSG-2 stream rate in integers as 32,552 Hz (zsg2.cpp:137), 192 + 16 /
32,552 cycles; the testbench uses that and loads the phase at each release
(10.1).

### 6.3 TMS57002 slots

Two TMS57002 instruction slots per machine cycle and the SYNC at each
boundary in stepped time (not at a lookahead tick), delivered in order by
the slot feeder at most one pulse every two clk cycles (zoom_tmsfeed.sv).
The ZSG-2 output of each pass goes into a 4-entry queue primed with one
zero entry; each SYNC takes the oldest, so the program for sample k runs on
the ZSG-2 output of sample k - 1, as the serial link on the PCB requires
(design study 6.1; the `sq` queue in zoom_board.sv). Host bytes reach the
TMS57002 at the start of the writing instruction in virtual time; MAME's
own landing point is coarser (60 kHz quantum, design study 7.4; 10.5).

The DSP takes at most 16.9 M slots per second, 1.35 times the slot rate.
When the MN10200 catches up after a lag it steps cycles faster than that,
and in my first split runs the feeder fell more than a sample behind and
had to merge two SYNCs (`dbg_sync_ovf`, psyvaria at cap 1,024), which
drops a DSP sample. The MN10200 now starts no instruction while the feeder
holds a SYNC behind undelivered slots (mn10200 input `ext_go`,
zoom_board.sv `feed_sp`): the virtual time can then run ahead of the DSP
by at most one instruction (20 cycles), and no SYNC is ever merged. It
only slows the catch-up.

### 6.4 Real time: the MN10200 pacer

The pacer lets the MN10200 run only while its virtual time is behind real
time and lets it catch up by at most `PACE_CAP` machine cycles
(mn10200.sv:84-97). The output stage's FIFO depth and lead follow the cap
(`PACE_CAP` / 192 + 2 samples). Measured with the pacer on (10.2); the
lockstep builds read the output at MAME's 32,552 Hz from the runs marked
(m), so that repeats count only the board's own lag:

| Configuration | Run | Machine-cycle rate | Clocks with the lag at the cap | Max lag (cycles) | Output samples repeated |
|---|---|---|---|---|---|
| `CLK_H` 2, cap 64 | psyvaria 40 s | 6.2338 MHz (-0.26%) | 0.27% | 64 | 2,923 of 1,127,423 |
| `CLK_H` 2, cap 256 | psyvaria 40 s | 6.2410 MHz (-0.14%) | 0.15% | 256 | 1,622 of 1,126,121 |
| `CLK_H` 2, cap 64 / 256 / 2,048 | raycris canary 1.9 s | 6.2426 / 6.2454 / 6.2473 MHz | 0.18 / 0.13 / 0.06% | | 72 / 46 / 26 of about 61,800 |
| `CLK_H` 2, cap 256 (m) | raycris 46 s | 6.2460 MHz (-0.06%) | 0.071% | 256 | 626 of 974,326 |
| whole board on clk_2x, cap 256 (superseded) | psyvaria 40 s | 6.2500 MHz | 0 | 92 | 3 of 1,124,502 (the testbench's rate, below) |
| whole board on 50.8 MHz, cap 256 (superseded) | psyvaria 40 s | 6.2500 MHz | 0.0001% | 256 | 5 of 1,124,503 |
| split, no `PIPE`, cap 256 | psyvaria 40 s | 6.2497 MHz | 0.0047% | 256 | 56 |
| split, no `PIPE`, cap 1,024 (m) | psyvaria 40 s | 6.2500 MHz | 0 | 542 | 190 |
| split + `PIPE`, cap 256 (m) | psyvaria 40 s | 6.2494 MHz | 0.0094% | 256 | 106 |
| split + `PIPE`, cap 1,024 (m), no feeder gating | psyvaria 40 s | 6.2500 MHz | 0 | 681 | 378, and SYNCs merged |
| **split + `PIPE` + feeder gating, cap 1,024 (m): the default** | psyvaria 40 s | **6.2500 MHz** | **0** | **682** | **0 of 1,124,499** |
| same | raycris 46 s | **6.2500 MHz** | **0** | **614** | **0 of 973,700** |
| same | raycris canary 1.9 s | 6.2500 MHz | 0 | 129 | 0 of 61,771 |

Where the time goes. At clk_1x the lag reaches the cap in the voice-poll
loop (0x081090 to 0x0810D7, design study 3.7; logged at 0x0810CB and
0x0810CD), short register and work-RAM instructions that MAME charges 1 or
2 machine cycles (5.4 or 10.8 clocks) each while the core needs about 7 to
9, and after reset in the boot code. A ZSG-2 read that arrives while a pass
runs waits up to the pass length: 769 clk cycles, 142 machine cycles. In
the split the ZSG-2 stays on clk, so that wait counts double against the
MN10200's faster clock, and `PIPE` adds two clk2x cycles per instruction;
together they push the lag in play to about 680 cycles, which needs a cap
of 1,024 to recover without loss.

What a lag of up to 682 cycles (109 us) means: the MN10200's virtual time
trails real time by at most that much, so a mailbox write or doorbell from
the main CPU reaches it up to 109 us later in virtual time than with no
lag. MAME's own coupling is a 60 kHz quantum (16.7 us), so this is a
classified timing difference of the same kind, larger; it does not change
what the firmware does with the commands. Shrinking it means making ZSG-2
reads faster (answer once the read channel is rendered, a zsg2.sv change)
or the ZSG-2 faster (6.5).

The 3 and 5 repeated samples of the superseded rows are the testbench's,
not the board's: those builds read the output at 32,552.083 Hz while the
lockstep builds use MAME's sample period (192 + 16 / 32,552 cycles, 6.2),
2.9 samples over 34.5 s. The rows marked (m) read at 32,552 Hz.

### 6.5 Timing at 67.7 MHz

The chips fitted alone at 29.525 ns, slow-model Fmax (main checkout
builds/; Fmax tables in each `*.sta.rpt`):

| Block | Fmax | At `CLK_H` 4 runs on |
|---|---|---|
| MN10200, trimmed (builds/20261005_1405_mn102) | 52.3 / 52.43 MHz | clk2x, 67.7 MHz |
| ZSG-2 (builds/20261005_1148_zsg2) | 54.08 / 55.22 MHz | clk, 33.9 MHz |
| TMS57002 (builds/20261005_1240_tms57) | 40.69 / 40.64 MHz | clk, 33.9 MHz |

Only the MN10200 side needs 67.7 MHz, which is why the board is split.
The STA path list of the trimmed MN10200 fit (
tools/zoom/sta_paths.tcl, builds/mn102_paths) has 87 endpoints that would
fail at 14.762 ns, in four groups:

| Group | Worst data delay | Endpoints | Retiming (`PIPE` = 1) |
|---|---|---|---|
| ib0 (instruction byte) -> page and register fields -> MLAB read -> ALU, DIVU compare (LessThan25) -> psw, rf_wd, state | 18.44 ns | 11 | decode fields (page, key byte, register fields, immediates) registered, one more decode clock before the boundary; the DIVU overflow compare `mdr >= Dn` done one clock early (mn10200_core.sv, `page_r`, `div_ovf_q`) |
| icr_ir (interrupt request) -> priority -> take decision -> m_wd, m_addr, m_ret, irq_lvl_q | 16.28 ns | 66 | candidate, level, group, NMI and `pirq_set` registered in the core; the boundary sample waits one more clock after the timers finish stepping (`cand_q`, `tmr_busy_q`) |
| pend, t_cur -> step -> timer cascade -> pirq_set, t_cnt | 16.73 ns | 3 | `step` and the timer zero tests (`t_cur == 0`, `t_base == 0`) kept as flags beside their registers (mn10200_periph.sv `pend_nz`, `t_curz`, `t_basez`); behaviour-neutral, so also at `PIPE` = 0 |
| pc -> fetch position -> buffer hit -> nb, f_done | 15.48 ns | 4 | not changed yet; the fit at 67.7 MHz decides |
| m_addr -> read lane select -> md | 14.93 ns | 3 | not changed yet |

`PIPE` costs two clk2x cycles per instruction (7.21 against 6.21 clk
cycles per instruction on the directed test at `PIPE` 1 and 0) and changes
nothing in virtual time: the directed test of all 159 forms equals MAME
with `PIPE` 1 (136,236 instructions, the same count as docs/mn10200_rtl.md
4.2), and so do all board runs (10.3).

Fits (builds/, not committed; slow models):

| Fit | Source | ALMs | Registers | RAM blocks | DSP | Worst setup slack | Worst hold slack |
|---|---|---|---|---|---|---|---|
| MN10200_FIT67: MN10200 alone, `PIPE` 1, 14.762 ns (builds/20261005_1809_mn102f67) | 557d874 | 2,090 | 1,240 | 2 | 0 | +1.723 ns | +0.164 ns |
| ZOOM_FIT2X: split board, clk 29.524 ns, clk2x 14.762 ns (builds/20261005_1718_zoomfit2x) | 5905c50 plus the `PIPE` edits, cap 256, before the feeder gating | 4,771 | 3,884 | 147 | 5 | clk2x +2.065 ns, clk +5.292 ns | clk2x +0.086 ns, clk +0.095 ns |

Both meet timing. The split board is 143 ALMs larger than ZOOM_FIT at
`CLK_H` 2 (4,628, 11.3), mostly the slot feeder (122 ALMs in the map
report) and the crossing registers. The feeder gating and the cap of 1,024
came after this fit; they add a few registers (a wider pacer compare is
already 32 bits).

## 7. Output path

### 7.1 Chain

ZSG-2 sends 0 to 3, route gains 0.5, 0.5, 1, 1 with SIM = 1 alignment
(taito_zm.cpp:205-208, tms57002.cpp:927-931), into TMS57002 SI0/SI1; SO1
(16 bits, SOM = 2) at each SYNC into the output FIFO (zoom_out.sv); read at
a real-time 32,552.083 Hz tick (15,625 / 16,257,024 per clk_1x clock,
1,040.45 clocks per sample, no drift); the volume gain; then the mix.

The FIFO (8 entries, reading starts at 2) absorbs the difference between
the virtual time (paced to real time within the pacer's window) and the
real-time tick. Underflow repeats the last sample and sets a flag.

### 7.2 Volume

MB87078 law or MAME's linear law (3.3), as an unsigned Q1.15 factor per
channel on the 16-bit output, one multiplier shared by both channels
(zoom_out.sv:82-97).

### 7.3 Mix with the SPU

rtl/zoom/zoom_mix.sv: out = 0.3 x SPU + 1.0 x Zoom, saturated to 16 bits,
both inputs 16-bit full scale as in MAME (taitogn.cpp:441-448; SPU
spu.cpp put_int with 32768, TMS57002 tms57002.cpp:933-936). Both gains are
parameters until PCB recordings settle R13. Each input is held between its
own sample ticks; MiSTer's audio_out resamples the sum.

## 8. TMS57002

rtl/zoom/tms57002.sv from branch tms57002-rtl, merged (docs/tms57002_rtl.md).
Connections (zoom_board.sv, `u_tms`): `step` and `sync` from the slot
feeder (6.3), `host_wr` from the 0xC00000 byte write, `pload_n` / `cload_n` from
port 1 bits 0 and 1, `empty` to the IRQ1 pin (MAME inverts the line and the
MN10200 maps an asserted line to a low pin, so the pin equals EMPTY:
taito_zm.cpp:198, mn10200.cpp:350), SI0/SI1 from the ZSG-2 queue, SO1 16-bit
words to the output stage, `dbg_hold` tied to 0.

Parameters: `TMS_MAME = 0` (default) keeps the TMS57002 User's Guide
behaviour (XM_CYCLES 6, XM_COUNT_IDLE 1, UPD_AFTER_CLOAD 1, MPY_A32 0,
SI_RAW 0), which outranks MAME; `TMS_MAME = 1` selects the set that is
bit-exact with MAME 0.288 (XM_CYCLES 2, XM_COUNT_IDLE 0, UPD_AFTER_CLOAD 0,
MPY_A32 1, SI_RAW 1; sim/tms57002/build.sh:18). Oracle comparisons use the
MAME set and say so (10.2).

Earlier in this branch the board carried a black box with the same ports
(a dry bypass, EMPTY high); it was removed when the core was merged.

## 9. Reset sequencing

| Event | MAME | Board |
|---|---|---|
| Power on | MN10200 held (driver_reset); control = 0x10 | `rst`; zoom_reset = control bit 4 = 1; the program cache sweeps its tags |
| Control bit 4 rises | MN10200 reset line asserted, through MAME's synchronised input, so it takes effect at the write's time on the MN10200's clock | MN10200 held (`cpu_rst`, zoom_board.sv:96); program cache invalidated and swept; ZSG-2 and TMS57002 keep running (`RST_LEVEL = 0`) |
| Control bit 4 falls | taito_zoom device reset: ZSG-2, TMS57002, MN10200, register number; U27 and wave flashes to read array (taitogn.cpp:524-531) | One-clock reset of the ZSG-2 and TMS57002 (`chip_rst`, zoom_board.sv:97), MN10200 released once the tag sweep is done (2,048 clocks, 60 us; every hold in the traces lasts at least 48 ms) |

Whether the PCB holds the ZSG-2 and the TMS57002 in reset while bit 4 is 1
is unknown; `RST_LEVEL = 1` does that (Z17).

## 10. Verification

### 10.1 Method

- Oracle: tools/zoom/zoom_oracle.lua with the 61c7940 build (ZN2_CPU_HZ
  unset), streamed through a FIFO into the testbench
  (sim/zoomboard/run_vs_mame.sh). One stream in MAME's execution order:
  per-instruction MN10200 state (T lines, as tools/mn102/mn102_oracle.lua),
  every MN10200 access to the ZSG-2 (with its local time in attoseconds and
  m_sample_count), the TMS57002 port and the mailbox (B), every main-CPU
  access to the Zoom ports (H) and the control register (C), and the
  TMS57002's serial inputs and SO1 pair once per sample (S). Each TMS57002
  byte write also carries the DSP's PC and the stream's sample count where
  MAME applies it (its landing point).
- Testbench (sim/zoomboard/tb.cpp, Verilator 5.050): zoom_board with the
  real firmware (U27 and wave images from tools/build_flash.py, identical
  to MAME's NVRAM for both games), a flash-area memory model (10 clocks per
  64-bit line, one line at a time, as SDRAM channel 3), lockstep by
  instruction. Inputs from MAME are only the main CPU's accesses and the
  IRQ1 pin (taken from MAME's FC57, because the TMS57002 consumes
  coefficient updates on its own schedule in MAME, 10.3; the board's own
  EMPTY is compared and counted); all MN10200 reads of the ZSG-2, the
  mailbox, the program and the work RAM come from the board.
- Main-CPU events: mailbox and register writes land where they sit in the
  stream (MAME's memory is shared directly). The reset bit and the IRQ0
  doorbell go through MAME's synchronised input lines, so they take effect
  at the write's time on the MN10200's own clock: the testbench applies a
  doorbell before the first instruction that starts at or after that time,
  and a reset assert just before the following release. I found both on
  the way (10.4).
- Sample phase: MAME's MN10200 local time is t0 + C x 160 ns per run
  segment (C = totalcycles). On the canary every one of 2,568 timed ZSG-2
  accesses fits that with one t0 per segment. At each release the testbench
  takes t0 from the first ZSG-2 access, computes the first boundary after
  the first instruction and loads the board's time base (`tb_ld`). From
  then on the board's ticks run free and are checked at every ZSG-2
  access.
- Checks: per instruction PC, D0-D3, A0-A3, PSW, MDR, the previous
  instruction's cycles, FC42, FC50; per access address, lanes, write data
  and the read data the board returns; per ZSG-2 access the sample
  position; per sample the four ZSG-2 outputs and the SO1 pair (at offsets
  of -2 to 2 samples); per TMS57002 byte the landing point against MAME's;
  host reads.
- Directed: sim/zoomboard/build_host.sh runs tb_host.cpp on zoom_host and
  the mailbox for what no trace reaches: every MB87078 code, C0, C32,
  EN = 0, channel 2, the MAME law, host mailbox reads by lane, the doorbell
  and the status read (93 checks, both laws, all pass).

### 10.2 Runs

All with the 61c7940 build, ZN2_CPU_HZ unset, warm NVRAM from
sim/r18/nv_<set> (post first-boot copy), the testbench built with
TIMER_EXACT = 1 (MAME timer phase; the build and fit default is 0, the
chip's shared prescalers), DEBUG = 1 and MAME's 32,552 Hz sample period;
memory 10 clocks per 64-bit line, one at a time. Every TMS57002 result
below uses the MAME parameter set; the default build uses the guide's
(8).

| Run | MAME time | Board configuration | MN10200 run time |
|---|---|---|---|
| raycris canary | 18 s, trace on disk | early RTL, 8 KB cache, TMS57002 black box, pacer off; later rerun at every `CLK_H` and cap after each change | 0.048 s power-on run + 1.85 s |
| raycris A | 46 s, coin at 24 s, then start, fire, left/right | `CLK_H` 2, 8 KB cache, TMS57002 black box (dry bypass), pacer off | 0.048 s + 29.8 s |
| psyvaria A | 40 s, coin at 20 s | `CLK_H` 2, 32 KB cache, TMS57002 RTL (`TMS_MAME = 1`), pacer cap 64 | 0.048 s + 34.5 s |
| psyvaria B | 16 s, no input | as A, landing check | 0.048 s + 10.5 s |
| psyvaria C | 40 s, coin at 20 s | as A, cap 256 | 0.048 s + 34.5 s |
| psyvaria D | 18 s, no input | as C, landings listed before the first SO1 difference | 0.048 s + 12.5 s |
| psyvaria E | 40 s, coin at 20 s | `CLK_H` 4, cap 256, landing log 372,200 to 372,510 | 0.048 s + 34.5 s |
| psyvaria F | 18 s, no input | `CLK_H` 4, cap 256, update-episode check (10.5) | 0.048 s + 12.5 s |
| raycris B | 46 s, coin at 24 s | `CLK_H` 4, cap 256, 32 KB cache, TMS57002 RTL, all checks | 0.048 s + 29.8 s |
| psyvaria G | 40 s, coin at 20 s | `CLK_H` 3 (then the whole board on 50.8 MHz), cap 256 | 0.048 s + 34.5 s |
| psyvaria H, I, J | 40 s, coin at 20 s, three runs, each one MAME stream into two builds (run_vs_mame2.sh) | split board: without `PIPE` (cap 256, 1,024), with `PIPE` (256, 1,024), with `PIPE` and feeder gating (256, 1,024); output read at 32,552 Hz | 0.048 s + 34.5 s |
| raycris C | 46 s, coin at 24 s, one stream into two builds | split board, `PIPE`, gating, cap 1,024 (the default); and `CLK_H` 2, cap 256 | 0.048 s + 29.8 s |

The raycris segments start at 0.0772 s and 16.153 s, psyvaria's at
0.0772 s and 5.52 s; each run ends at the MAME time limit.

### 10.3 Results

| Check | raycris A | raycris B (`CLK_H` 4, one clock) | psyvaria A | psyvaria E (`CLK_H` 4, one clock) |
|---|---|---|---|---|
| MN10200 instructions equal to MAME (whole run) | 90,606,702 | 90,606,702 | 103,543,027 | 103,543,027 |
| MULU NF cases accepted (docs/mn10200_rtl.md 4.3) | 30,444 | 30,444 | 44,868 | 44,868 |
| External accesses equal (address, lanes, data) | 806,942 | 806,942 | 958,482 | 958,482 |
| of which ZSG-2 reads answered by the board's ZSG-2 | 52,624 | 52,624 | 77,164 | 77,164 |
| of which mailbox reads answered by the board's mailbox | 126 | 126 | 58 | 58 |
| of which TMS57002 byte writes | 560,641 | 560,641 | 625,439 | 625,439 |
| ZSG-2 accesses at MAME's sample position | 246,121 | 246,121 | 332,948 | 332,948 |
| ZSG-2 output samples equal (four sends, 24 bits each) | 973,251 of 973,251 | 973,251 of 973,251 | 1,124,037 of 1,124,037 | 1,124,038 of 1,124,038 |
| Main-CPU lines applied (H), doorbells timed | 422, 6 | 422, 6 | 345, 6 | 345, 6 |
| TMS57002 SO1 equal before the first difference (MAME set, offset 1 sample) | n/a (black box) | 210,859 | 372,443 | 372,443 |
| TMS57002 host bytes in MAME's sample / one sample earlier / further | n/a | 557,668 / 2,973 / 0 | not logged | 622,173 / 3,266 / 0 |
| Board flags | sync_ovf (unpaced), out_under | out_under | out_under | out_under |

Rows B and E ran the earlier `CLK_H` 4, the whole board on clk_2x. The
split board with `PIPE`, gating and cap 1,024 (psyvaria J, raycris C) gives the
same counts in every row: 103,543,027 and 90,606,702 instructions,
958,482 and 806,942 accesses, 332,948 and 246,121 sample positions,
1,124,037 and 973,251 ZSG-2 output samples, all equal; SO1 equal for the
first 372,443 and 210,859 samples; host bytes 622,174 and 557,770 in
MAME's sample, 3,265 and 2,871 one sample earlier, none further; board
flags 00 (no SYNC merged, no repeated sample).

No divergence in any run: every instruction, every access, every sample
position and every ZSG-2 output sample equals MAME, at `CLK_H` 2, at the
earlier one-clock `CLK_H` 4 and in the split board.
psyvaria B, C, D, F and G agree with these over their lengths; the
mailbox reads of raycris B ran on the RTL of b74ee7b (template mailbox,
no casts). The work RAM flag (access
above 32 KB), the unmapped flag, the TMS57002 read flag, the ZSG-2 late
and overrun flags and the arbiter overflow never set.

Notes:

- The TMS57002 SO1 pair is bit-exact against MAME, with the board's
  sample k + 1 equal to MAME's sample k (the one-sample serial-link delay
  the design study planned, 6.1), until the first coefficient update whose
  effect shows; 10.5 explains the difference.
- The board's own EMPTY differs from MAME's IRQ1 pin at about 1% of
  instruction starts: MAME's TMS57002 takes coefficient updates on its own
  schedule in the 60 kHz interleave (10.5). The firmware only polls the
  pin before an update, so this changes how long it polls, not what it
  writes; it is why the lockstep takes the pin from MAME.
- `sync_ovf` in the unpaced raycris run: without the pacer the virtual
  time runs about 24% faster than real time and the TMS57002 slot feeder
  (one slot per two clocks) falls more than a sample behind in bursts. With
  the pacer on it never set.
- `out_under` is the output FIFO running dry (6.4).

### 10.4 Found on the way

- Reset and doorbell timing in MAME (10.1): the first runs failed where
  MAME's MN10200 ran on after a reset write and where it took IRQ0 later
  than the write's stream position. Both are MAME's synchronised input
  lines, and the testbench now applies them by time. The board itself
  takes the doorbell within a few clocks of the write, which on the PCB is
  the physical behaviour.
- The board's sample boundaries matched MAME's at every timed access once
  the phase used the first instruction's totalcycles (MAME counts 43
  cycles before the first instruction of the power-on run and 1 before the
  first of the game run).

### 10.5 Why SO1 leaves MAME's (I4)

(Very likely superseded: the serial input latch fixed in 14.12 silences
the DSP from the first sample with signal, where this difference starts.
The update landings below are real; the lockstep runs were not repeated.)

What differs. psyvaria F logs every CMEM update the board applies, with
the last host byte before it on both sides (tb.cpp `EP` lines). All
updates in these runs are to coefficient 30 (SA byte 0x1E), read by the
program at PC 226. The MAME parameter set applies an update at the next
CMEM read of its address after the last byte (UPD_AFTER_CLOAD = 0, as
MAME tms57002.cpp:146, 683-697), so the sample it takes effect in follows
from where the last byte lands against PC 226:

| Run | Updates applied | In MAME's sample | One sample later than MAME | One sample earlier |
|---|---|---|---|---|
| psyvaria F (12.5 s of Zoom time) | 53,328 | 50,496 | 2,827 | 5 |
| raycris B (29.8 s) | 111,501 | 105,427 | 6,043 | 31 |

In every "later" case the board's last byte lands at PC 228 to 234 and
MAME's at PC 187 to 223 of the same sample (first 20 listed in the
psyvaria F log, the first at sample 176,872). The first of them comes long
before the first SO1 difference (sample 372,501 in psyvaria, 210,907 in
raycris): coefficient 30 scales a path that is silent until then, so the
one-sample lag shows only when signal reaches it. Everything else that
feeds the DSP is equal (ZSG-2 outputs, programs, host bytes and their
order), and the TMS57002 core is bit-exact when bytes land where MAME's do
(docs/tms57002_rtl.md 4), so the update landings are the cause.

Which side is right. On the PCB a host byte reaches the DSP at the time
the MN10200 writes it, and the DSP's position then is that time in
instruction slots: one crystal, 384 slots per 192 machine cycles. The
board's DSP has executed exactly the slots of the virtual time stepped
when the write happens, minus any slots still queued, and the write
happens at the start of its instruction in virtual time (6.3). So the
board's landing PC is never later than the physical one. In all 2,827 and
6,043 "later" cases it is already past PC 226, so the physical landing is
past it too: the update takes effect in the next sample, as in the board.
MAME's TMS57002 is a separate CPU in the scheduler; inside each 60 kHz
timeslice the MN10200 runs ahead of it, so at the write MAME's DSP PC
still lags the write time (the logs show runs of bytes 16 slots apart in
time all landing at the same MAME PC). MAME's landing is early by up to a
timeslice, a scheduler artefact. Under the User's Guide rule, the default
(UPD_AFTER_CLOAD = 1: the first CMEM read of SA after CLOAD returns high,
p.3-43), the update can only land at or after the board's MAME-set point,
because CLOAD rises after the last byte. So the board is right in these
cases with both parameter sets, and I left the RTL as it is.

The 5 and 31 "earlier" cases are where MAME's last byte lands after
PC 226 and the board's before it. There the board's landing is a lower
bound only: it can be early by the writing instruction's own cycles (a
store takes at most 4, plus 7 after an interrupt entry, so up to 22 slots)
plus queued slots, so a few of these may be early on the
board. Making it exact needs the host bytes and the PLOAD/CLOAD pin
changes queued with their virtual time (end of the writing instruction, as
for the ZSG-2 lookahead) and delivered to the TMS57002 between the right
two slots (open item I5).

## 11. Budget

### 11.1 Estimate (method as design study 6.5; the MN10200 row from its first fit)

| Block | ALMs | M10K | DSP | Basis |
|---|---|---|---|---|
| MN10200 | 1,700 to 2,085 | 3 | 0 | docs/mn10200_rtl.md 5: first fit 2,085 without the fit's virtual-pin share, about 1,700 expected after the trims |
| ZSG-2 | 950 to 1,400 | 7 | 1 | docs/zsg2_rtl.md 6 |
| TMS57002 | 630 to 970 | 67 | 2 | docs/tms57002_rtl.md 6 (design study: 710 to 1,240) |
| Program cache (32 KB, tags, fill) | 50 to 90 | 33 | 0 | about 60 flip-flops, 4-bit tag compare, 21-bit line adder; 32 data blocks, 1 tag block (2,048 x 5) |
| Work RAM 32 KB | 5 to 15 | 32 | 0 | address only |
| Mailbox | 5 to 10 | 1 to 2 | 0 | two byte lanes |
| Host side (decode, MB87078 latches and law ROM, answer register) | 80 to 130 | 0 | 0 | about 80 flip-flops, 64-entry ROM |
| Bus decoder | 50 to 80 | 0 | 0 | 16-bit 3:1 read mux, FSM |
| Time base and TMS57002 feeder | 60 to 100 | 0 | 0 | 18, 16 and 9-bit counters, two 11-bit slot counters |
| ZSG-2 to TMS57002 queue | 70 to 110 | 0 | 0 | 4 x 64 flip-flops |
| Arbiter, synchronisers | 30 to 50 | 0 | 0 | |
| Output stage (FIFO, real-time tick, gain) | 60 to 100 | 0 | 1 | FIFO in flip-flops or MLAB |
| zoom_line32 (SDRAM build only) | 40 to 60 | 0 | 0 | 64-bit line register |
| zoom_mix | 30 to 60 | 0 | 0 to 2 | two constant products |
| **Board glue (rows 4 to 14)** | **480 to 805** | **66 to 67** | **1 to 3** | |
| **Zoom total** | **3,760 to 5,260** | **143 to 144** | **4 to 6** | |

### 11.2 Against F0

docs/f0_budget.md 5.1 counts the Zoom as 3,202 (FX-1B without its
MN10200, line 242) + 930 to 1,670 (own MN10200, line 243) + 50 to 200
(G-NET changes, line 244) = 4,182 to 5,072 ALMs. This design: 3,760 to
5,260, that is 422 lower to 188 higher. The F0 projection (34,534 to
36,684, line 246) becomes 34,112 to 36,872 ALMs (81.4 to 88.0% of 41,910),
under the 90% margin of f0_budget.md 5.2 over the whole range.
M10K 143 to 144 against FX-1B's 156 (the F0 M10K projection drops from
407 to about 395); DSP 4 to 6 against FX-1B's 4 (93 to 95 of 112). Neither
is a constraint.

### 11.3 First fit (ZOOM_FIT, `CLK_H` 2)

Fitted from 00b9742 (
builds/20261005_1535_zoomfit, not committed; ZOOM_FIT.fit.summary, .sta.summary): 4,628
ALMs (11%), 3,715 registers, 148 RAM blocks, 5 DSP, every clock met. Per
entity (fit_entities.py figures): mn10200 1,666, zsg2
1,250, tms57002 921, own logic 417 (with the virtual-pin overhead), tbase
98, bus 79, out 65, host 60, pcache 38 (+33 M10K), memarb 28, mbox 2.5
(+2 M10K), wram 32 M10K. Worst setup slack 3.151 ns on clk and 5.722 ns
on clk2x (slow models), worst hold 0.119 ns: the half-cycle clk2x RAM
paths of 4.1 close with room. The total is inside 11.1 (3,760 to 5,260)
and inside F0's Zoom line (4,182 to 5,072, f0_budget.md 5.1). Putting the
measured 4,628 in place of that line, the F0 projection's low case becomes
34,534 - 4,182 + 4,628 = 34,980 ALMs (83.5%). zoom_line32 and zoom_mix are
not in this fit (about 70 to 120 ALMs, 11.1).

### 11.4 Fit project

ZOOM_FIT.qpf/.qsf/.sdc, top zoom_board, all ports virtual, hardware
parameters, the TMS57002 with the guide parameters, `CLK_H` 2: clk
29.524 ns with clk2x exactly half; `tools/pc_build.sh zoomfit
push|task|run|fetch`, then `tools/fit_entities.py
output_files/ZOOM_FIT.fit.rpt --node 'zoom_board$'`. It measures the whole
board and checks the half-cycle clk2x paths (4.1). Revision ZOOM_FIT2X
(ZOOM_FIT2X.qsf/.sdc, target `zoomfit2x`) is the split board at `CLK_H`
4: clk 29.524 ns, clk2x 14.762 ns. Revision MN10200_FIT67 of project
MN10200_FIT (target `mn102f67`) is the MN10200 alone at 14.762 ns with
`PIPE` 1, and tools/zoom/sta_paths.tcl lists the worst paths of any fitted
revision. The fits are in 11.3 and 6.5. The first ZOOM_FIT try stopped at the mailbox RAM inference, fixed
in 98945b9; the Quartus 17 audit's cast class is removed in b74ee7b.

## 12. Open questions

| # | Question | Evidence that would settle it |
|---|---|---|
| Z17 | Does control bit 4 hold the ZSG-2 and the TMS57002 in reset on the PCB (`RST_LEVEL`), or only the MN10200 as in MAME | FC PCB trace of the reset pins; PCB audio across a Zoom reset |
| Z10 | MB87078: DSEL wiring (address bit 1 assumed), channel 0 = left, what the channels attenuate | FC PCB trace; PCB audio of nightrai (0x30) against raycris (0x3F) |
| R7, O8 | Work RAM 32 KB mirrored against MAME's 128 KB | FC PCB decode (XC95108); the board flag never fired |
| R13 | SPU against Zoom balance (0.3 / 1.0 in MAME) | PCB line-out recordings |
| I1 | DDR3 latency of the integration's arbiter for the line port (5.3) | Measured in the integrated build |
| I2 | The glue's U27 write strobe into `prog_inval` (only needed if a game writes U27 while the Zoom runs; none of the six does) | gnet_fc change at integration |
| I3 | Done: split board and MN10200 retiming meet 67.7 MHz (6.5). The lag against the main CPU is down from 109 us to 35 us in play with ZSG-2 reads answered inside a pass (15.3) | |
| I4 | Answered (10.5): coefficient updates whose last byte lands past the read in the board but before it in MAME; MAME's landing is a scheduler artefact | |
| I5 | Done (15): host bytes and pin changes delivered at the end of the writing instruction in virtual time, between the right two DSP slots | |

## 13. Files

| File | Content |
|---|---|
| rtl/zoom/zoom_board.sv | Top: resets, CPU, bus, RAMs, ZSG-2, time base, TMS57002, output |
| rtl/zoom/zoom_bus.sv | MN10200 bus decoder |
| rtl/zoom/zoom_pcache.sv | Program cache for U27 |
| rtl/zoom/zoom_wram.sv | Work RAM |
| rtl/zoom/zoom_mbox.sv | M66220FP mailbox |
| rtl/zoom/zoom_host.sv | Main-CPU ports, MB87078, doorbell |
| rtl/zoom/zoom_tbase.sv | Virtual time base, lookahead, cycle and boundary counters |
| rtl/zoom/zoom_tmsfeed.sv | TMS57002 slot feeder (clk side) |
| rtl/zoom/zoom_memarb.sv | Program and wave memory arbiter |
| rtl/zoom/zoom_line32.sv | Line port to 32-bit word port (SDRAM channel 3) |
| rtl/zoom/zoom_out.sv | Output FIFO, real-time tick, volume |
| rtl/zoom/zoom_mix.sv | SPU and Zoom mix |
| rtl/zoom/tms57002.sv | TMS57002 (merged from tms57002-rtl) |
| rtl/zoom/mn10200.sv, mn10200_core.sv, mn10200_periph.sv | `mc_step`, `acc_cyc` (6.2), `ext_go` (6.3), `PIPE` and the periph flags (6.5) |
| tools/zoom/zoom_oracle.lua, zoom_oracle.sh | MAME board oracle |
| sim/zoomboard/tb.cpp, build.sh, run_vs_mame.sh, run_vs_mame2.sh, files.lst | Board testbench; run_vs_mame2.sh feeds one MAME stream to two builds |
| sim/zoomboard/tb_line32.cpp, build_line32.sh | zoom_line32 against a read-DQM channel 3 model |
| sim/zoomboard/tb_host.cpp, zoom_host_tb.sv, build_host.sh | Host and mailbox directed test |
| ZOOM_FIT.qpf, .qsf, .sdc, ZOOM_FIT2X.qsf, .sdc; tools/pc_build.sh targets zoomfit, zoomfit2x | Stand-alone fits (`CLK_H` 2 and 4) |
| MN10200_FIT67.qsf, .sdc; target mn102f67; tools/zoom/sta_paths.tcl | MN10200 at 67.7 MHz; worst-path lists |

Game-derived data (flash images, traces, logs, testbench builds) stay in
sim/zoom/, gitignored.

## 14. Integration into the G-NET core (branch zoom-into-z1)

Branch zoom-into-z1: gnet-cpu50 (048cf9e, the 50 MHz CPU group with the
ZN-2 layer) with zoom-board merged at 4ee67d5. Revision GNET_Z1_ZOOM,
`tools/pc_build.sh z1zoom` (DIR gn_z1zoom, TASK gnz1zoom). Not fitted.

### 14.1 What is wired where

| Where | What |
|---|---|
| rtl/gnet/zn2_board.vhd | generic `ZOOM` (default 0): the Zoom ports of 3.1 go out on a new `zm_*` port (zn bus conventions: request pulse, ack pulse with data); zn2_io keeps the rest of the 0x1FB8xxxx to 0x1FBExxxx banks (writes ignored, reads 0, as MAME's unmapped space). `ZOOM = 0` keeps zn2_io's silent stub |
| rtl/gnet/zoom_cdc.vhd (new) | crossings Z1 (host port) and Z2 (control bit 4), 14.3 |
| rtl/psx_top.vhd | generics `ZOOM_BOARD` (default 0; needs `ZN2_BOARD` 1 and `CPU_CLK_SPLIT` 1, asserted) and `ZOOM_INFL` (ZSG-2 reads outstanding, default 4); in the `gzn2c` generate: zoom_cdc and zoom_board (component, `CLK_H` 4, `PACE_CAP` 1,024, `TIMER_EXACT` 0, `DEBUG` 0, the guide's TMS57002 behaviour and the MB87078 law by default); new ports `zoom_m_*`, `zoom_rst`, `zoom_aud_l/r`, `zoom_flags`, all on clk_1x |
| rtl/psx_mister.vhd | the generics and ports passed through |
| PSX.sv, macro `GNET_ZOOM` | wires `zoom_m_req`, `zoom_m_line[20:0]`, `zoom_m_ready`, `zoom_m_rvalid`, `zoom_m_rdata[63:0]` (zoom_board's m_* port as it is, clk_1x) and `zoom_rst`; zoom_mix after the SPU (14.6) |
| PSX.sv, macro `GNET_ZOOM_SDRAM` | temporary memory path for the first test build: rtl/gnet/zoom_sdram_link.vhd (new) on zn2_ch3_arb port c (14.4). Ignored when `GNET_DDR3_ARB` is defined; with neither macro nothing answers the line port and the Zoom stays silent |
| PSX.sv, macro `GNET_DDR3_ARB` | the release memory path: the DDR3 arbiter of branch ddr3-arb-int drives `zoom_m_ready`, `zoom_m_rvalid`, `zoom_m_rdata`; `ZOOM_INFL` 8 |
| rtl/gnet/zn2_ch3_arb.vhd | port c (defaults keep the two-port instantiation); b and c take turns when both wait, a (downloads) first |
| rtl/zoom/zoom_board.sv | parameter `ZSG_INFL` (default 4) to the ZSG-2 `INFL` |
| GNET_Z1_ZOOM.qsf | GNET_Z1_CPU50.qsf byte for byte (CRLF and LF kept) with the header replaced, plus `GNET_ZOOM=1`, `GNET_ZOOM_SDRAM=1`, the rtl/zoom files of ZOOM_FIT2X with zoom_mix.sv, zoom_cdc.vhd and zoom_sdram_link.vhd; same SDC files (GNET_LEAN.sdc, GNET_CPU50_B1.sdc) and seed |
| mra/ | Ray Crisis Zoom test, warm and cold boot (rbf gnet_z1zoom) |

### 14.2 Main-CPU side

The addresses of 3.1, decoded in zn2_board exactly as zoom_host decodes
them: 0x1FB80000 to 0x1FB80003 (MB87078 data and address words),
0x1FBA0000 (doorbell, IRQ0), 0x1FBC0000 (reads 0), 0x1FBE0000 to
0x1FBE01FF (mailbox, lanes 0 and 2). Control bit 4 is gnet_ctrl's
`control[4]` at 0x1FB40000 (reset value 0x10, so the Zoom is held from
power-on as in MAME's driver_reset). There is no interrupt or status back
to the main CPU: MAME has none (sound_irq_r returns 0) and the M66220FP has
no flags (3.2).

The games' release sequence, from MAME 0.288 (61c7940 build) on Ray Crisis
warm (tools/zoom/zoom_hostlog.sh, 26 s): the MN10200 runs at power-on
(control C8h at 0.077 s; at 0.091 s it writes mailbox bytes 0 to 11 with
0), is held at 0.126 s (D8h), and at 16.1529 s the main CPU clears the 256
mailbox bytes with 256 halfword writes (masks 0000FFFFh and FFFF0000h,
41 us), then writes control F0h (bit 3 clear), F8h (bit 3 set) and E8h
(bits 4 and 5 clear: release and a watchdog edge) within 0.5 us. Bit 3 has
no Zoom function in MAME (taitogn.cpp control_w decodes bits 5, 4 and 2).
The first command follows at 18.270 s: a status read at 0x1FBC0000, a read
of mailbox byte 0x83, bytes 0x80 to 0x83 written (70h, 7Fh, 0, 55h), the
doorbell; 30 us later the MN10200 reads 0x83, 0x80, 0x81, 0x82 and writes
0x83 = 0. Commands then move on by four bytes per slot.

### 14.3 Clocks and crossings

The board runs where it was fitted: clk_1x and clk_2x (`CLK_H` 4, the
MN10200 side on clk_2x), with `hclk` = clk_1x, so its mailbox RAM, doorbell
toggle and gain words stay inside the PS1 group (one PLL, timed as
synchronous clocks, as in ZOOM_FIT2X). zoom_board has no path to clk_cpu.
Every path between the CPU group and the Zoom goes through rtl/gnet/cdc,
with every source a `cdc_tx_*` register:

| # | Signal | Block | Notes |
|---|---|---|---|
| Z1 | host port: we, address, byte enables, write data (61 bits) to clk_1x, 32-bit read word back | cdc_handshake (zoom_cdc) | one request open (the bus waits for zn_ack); addresses zoom_board does not decode, and requests that meet the board reset, are answered 0 on the clk_1x side; the CPU side drops an answer that belongs to a request from before zn2_board's reset and starts no request while that reset is high |
| Z2 | control bit 4 | `cdc_tx_zrst`, cdc_sync INIT 1 (zoom_cdc) | the Zoom is held from configuration; zoom_board then re-synchronises it into clk_1x and clk_2x (synchronous) |
| Z3 | flash area lines (GNET_ZOOM_SDRAM only) | cdc_handshake (zoom_sdram_link): 21-bit line out, 64 bits back | clk_1x to clk_cpu, where SDRAM channel 3 runs; with GNET_DDR3_ARB there is no crossing to the CPU group (the arbiter is on clk_2x) |

SDC: no new lines. rtl/gnet/cdc/cdc.sdc (sourced by GNET_CPU50_B1.sdc)
bounds every `cdc_tx_*` to `cdc_rx_s1` and `cdc_rx_hold` path through its
wildcard collections, which pick up the new instances; they use only
cdc_sync and cdc_handshake, so no new Gray bus needs a set_max_skew. Any
other path between {clk_cpu, clk_cpu2x} and {clk_1x, clk_2x} would be a
design error (tools/sta/cpu50_xclk.tcl lists them on the fit). Measured in
the integration bench: a host access takes 10.0 to 13.7 clk_cpu on average
from request to ack, 14 at most.

### 14.4 Memory

The flash area layout is unchanged (zn2_layer_design.md 13.4): SDRAM
0x1000000 + 0x200000 for U27, + 0x400000 to + 0x9FFFFF for U56, U55, U29,
little-endian 16-bit words; zoom_board's `U27_BASE` 0x200000 and
`WAVE_BASE` 0x400000 hold. Line L is bytes 8L to 8L + 7 of the area, flash
byte 8L in `m_rdata[7:0]`.

`zoom_m_*` contract (zoom_memarb's m_* side, clk_1x): `m_req` is a level
that never drops before it is accepted, but `m_line` can change while it
waits (the program cache pre-empts a waiting ZSG-2 request), so the line is
taken on the accepting edge (`m_req` and `m_ready`); one `m_rvalid` cycle
per line, in order, never without an open line; up to 8 open (`OW` 3); no
byte enables, read only. `zoom_rst` (psx_top `reset_intern_p`) is the
board's reset: answers to lines requested before it must be dropped.

GNET_ZOOM_SDRAM (first test build, rtl/gnet/zoom_sdram_link.vhd): one line
at a time; on clk_cpu two 32-bit reads on zn2_ch3_arb port c with byte
enables 1111 (tied in PSX.sv: the read DQM issue of 13b6e1d,
zn2_layer_design.md 18.5), returned as {word at + 4, word at + 0}. Channel 3
is sdram.sv's lowest priority behind the DMA FIFO, ch1 and ch2, so a line
costs two of its accesses plus the crossing (about 4 clk_cpu out and 3 to 4
clk_1x back). The game peak is about a quarter of the ZSG-2's worst-case
load (5.3); the MN10200 cache adds 30,048 lines per 103.5 M instructions
(4.3).

GNET_DDR3_ARB (release, branch ddr3-arb-int; docs/ddr3_arbiter.md and
docs/ddr3_bandwidth.md on their branches): the flash area is mirrored into
DDR3 at 0x31000000 with the same layout (every channel 3 write to 0x1000000
to 0x19FFFFF also goes to DDR3: the MRA download and the BIOS's first-boot
copy), the arbiter's own clk_1x to clk_2x adapter and return queue sit
between `zoom_m_*` and its Z port, and `ZOOM_INFL` is 8 (latency up to
L + 193 clk_2x behind GPU and glue bursts).

### 14.5 ROM loading

Nothing new: index 3 of the existing MRAs already holds U27 and the three
wave flashes in the flash area (warm: `<set>.flash` from
tools/gnet/make_game_zip.py --warm; cold: the BIOS programs them from the
card during the first-boot copy, before the game releases the Zoom).
Neither path writes U27 while the MN10200 runs (3.4), so `prog_inval` stays
0. New MRAs: mra/Ray Crisis (G-NET Zoom test, warm boot).mra and (cold
boot).mra, the silent-test MRAs with rbf gnet_z1zoom.

### 14.6 Audio

PSX.sv (GNET_ZOOM): the SPU's `sound_out_left/right` and zoom_board's
`aud_l/r` (volume applied, held per 32,552.083 Hz sample, both clk_1x
registers) go through zoom_mix: SPU x 0.3 + Zoom x 1.0, saturated to 16
bits, into AUDIO_L/R (signed). This is MAME's routing (taitogn.cpp 441-448)
and makes the SPU quieter than in the silent build. The SPU output is taken
as 16-bit full scale like MAME's (needs-review against spu.vhd's scaling);
the balance against the PCB is R13.

### 14.7 Resets

zoom_board's `rst` and `hrst` are psx_top's `reset_intern_p` (the PS1
group's copy of the core reset, so downloads and the OSD reset hold the
whole board); control bit 4 from gnet_ctrl, reset to 1 with zn2_board,
holds the MN10200 as in 9. No crossing is reset; each side finishes what it
started and drops stale answers (14.3).

### 14.8 Verification

All runs under nice -n 15, one simulation at a time.

NVC, `sim/zoomlink/run.sh` (tb_zoom_cdc: zoom_cdc, zoom_sdram_link and
zn2_ch3_arb; zoom_board's host side and the line requester as models with
sequence-numbered data; a channel 3 model that applies read DQM):

| Run | Result |
|---|---|
| `unit`: clk_cpu 50 MHz and 28.57 MHz against 33.8688 MHz, seeds 1 and 2, synchroniser model on and off (8 runs) | each: the release sequence (256 clearing writes, Z2 order checked), 4,000 random host accesses on every lane mask, doorbell, status, volume and undecoded addresses, 4,000 lines against 2,000 glue flash reads on port b; 10,000 channel 3 accesses, about 970 with a three-cycle ready; 0 errors |
| `unit` with random resets on both sides (seeds 3 to 6, about 340 resets each) | 0 errors; 9 to 18 reads per run answered 0 because they met the board reset (allowed) |
| `neg` (sim/zoomlink/mutants.py) | all 6 mutants fail: word_swap, no_hit_gate, zrst_init0, stale_line, stale_host, start_in_reset |
| `arb`: sim/zn2cpu50's tb_zn2_ch3_arb on the arbiter with port c, seeds 1 and 2 | 4,000 downloads and 20,000 flash operations each, 0 errors (two-port behaviour unchanged); its no_gap mutant (updated for the third port) still fails (222 errors) |
| `top`: psx_top analysed with every RTL file and elaborated with ZN2_BOARD 1, CPU_CLK_SPLIT 1, the LEAN generics and ZOOM_BOARD 1, then 0 | both elaborate; the only warnings are the SystemVerilog components gnet_fc and zoom_board, unbound in NVC |
| `lint`: Verilator 5.050 | rtl/zoom with zoom_board on top, ZSG_INFL 4 and 8: 0 errors (the 12 width warnings of the sized localparams, as before); PSX.sv with the GNET_Z1_ZOOM macros, with GNET_ZOOM and GNET_DDR3_ARB, and with the GNET_Z1_CPU50 macros: no error other than the modules Verilator cannot read (VHDL entities, PLLs, framework); with generated stand-ins for those (sim/zoomlink/lint_stubs.py: the VHDL entities from their port lists) the whole emu module elaborates with 0 errors in all three sets (upstream's procedural assignments to emu output wires, PROCASSWIRE, waived; 54 warnings, all in framework files, the stand-ins or timescales); sim/zoomlink/check_ports.py: every PSX.sv connection to psx_mister, zn2_ch3_arb, zoom_sdram_link and cdc_handshake matches the VHDL port lists for all macro sets |

One defect found and fixed on the way: zoom_cdc started a pending host
request in the cycle zn2_board's reset rose, so the answer to a request the
bus had already dropped was acknowledged later (tb_zoom_cdc seed 3 with
resets; mutant start_in_reset keeps the case covered).

Verilator, `sim/zoomlink/build.sh` (integration bench): GHDL
(oss-cad-suite) synthesises zn2_board (ZOOM 1, with zn2_io, zn_sio0, the
CAT702 pair and znmcu), zoom_cdc, zoom_sdram_link and zn2_ch3_arb with their
cdc blocks to Verilog (sim/zoomlink/zl_vtop.vhd, wired as psx_top and
PSX.sv wire them); Verilator adds gnet_fc (the real control register) and
rtl/zoom. clk_cpu 50 MHz against clk_1x and clk_2x; a memorymux-like bus
master; an SDRAM channel 3 model (4 to 14 clk_cpu per word, reads must use
byte enables 1111) holding the Ray Crisis flash area from
tools/build_flash.py. tb_zoomref.cpp is zoom_board alone with the same
parameters and an ideal memory (10 clk_1x per line), driven at the clk_1x
cycles at which the integrated board saw each host request and zoom_reset
change.

Scripted run (control read, mailbox self-test with the MN10200 held, the
release sequence, 300 ms of play, a command and doorbell, 200 ms of
polling; 509 ms simulated in 129 s):

| Check | Result |
|---|---|
| Control register read after reset | 10h |
| Mailbox self-test, 256 bytes through lanes 0 and 2 | all equal |
| Host requests reaching zoom_board | 32,777 of 32,777 as sent (fields and order), none extra |
| Release | zoom_board saw bit 4 fall 64 ns after the write's ack and after all 256 clearing writes; no MN10200 instruction before it |
| Doorbell | IRQ0 pulse 27 ns before the write's ack reached the CPU (the ack follows the write) |
| Mailbox reads against both ports' writes | 32,000 host reads, 0 wrong |
| Memory | 700 lines, 1,400 SDRAM reads, 0 with partial byte enables; board flags 00 |
| Against tb_zoomref (ideal memory, same host cycles) | same instruction count (2,117,220) and the same 700 lines; 619 records in 10 runs of 52 to 86 instructions differ, all in the TMS57002 EMPTY poll at 0x0834A4 (MOVBU (0xFC56),D1; 10.3): one side polls once more or less, then the streams realign with every register equal. Through the SDRAM path the MN10200 reaches some polls at another point of the DSP's progress; what the firmware does is unchanged |

MAME replay (`tb_zoomlink <flashdir> <out> replay <hostlog> 16.1529
18.40`): MAME's main-CPU Zoom accesses and control writes from
tools/zoom/zoom_hostlog.sh (Ray Crisis warm, 26 s in 6.5 s of wall time),
16.1529 s to 18.40 s, issued at their MAME times through the integrated
path (2.247 s simulated in 568 s):

| Check | Result |
|---|---|
| Bus steps replayed | 380 (control writes, the 256 clearing writes, volume, status and mailbox), all acknowledged; 274 reached zoom_board as sent |
| Host reads (status, mailbox) | 4 of 4 equal to MAME's data |
| MN10200 mailbox accesses after the release | 24 in the bench, 24 in MAME, all 24 equal in order (read or write, address, lane, data): the 12 boot writes, both commands read (0x83, 0x80, 0x81, 0x82; 0x87, 0x84, 0x85, 0x86), both acknowledgements, the polls of the next slot |
| Timing against MAME | the boot writes 9 us earlier; each command answered 30 to 40 us later than MAME (MAME 30 us after the doorbell, the bench about 61 us; the MN10200's lag against real time, 6.4) |
| Other | 7,835,463 MN10200 instructions, 1,298 lines, 0 partial byte enables, board flags 00; no audio output in this window (MAME's light log records no samples, so audio is not compared here) |

Longer replay, 16.1529 s to 22.60 s (6.447 s simulated in 1,551 s), with
the third command group at 22.517 s (the main CPU queues three commands at
once, slots 0x88 to 0x93): 651 bus steps, 8 of 8 host reads equal to MAME's,
40 of 40 MN10200 mailbox accesses equal in order, 20,513,451 MN10200
instructions, 1,576 lines, board flags 00, 0 errors. The third group is
answered 2 to 28 us earlier than in MAME (MAME's own response time varies
with its 60 kHz interleave). Still no audio output by 22.6 s.

After merging gnet-cpu50 26cdad6 (sdram.sv 2:1 refill fix, MB3773 8 s,
zn2_board `WD_TIMEOUT_S`, loader back-pressure) the elaboration and lint
checks, the scripted canary and the replay to 18.40 s were rerun with the
same results.

### 14.9 Budget (estimate, not fitted)

| Block | ALMs | RAM blocks | DSP | Basis |
|---|---|---|---|---|
| GNET_Z1_CPU50 (measured) | 28,681 | about 255 (GNET_Z1 254, plus the CPU-split command FIFOs and the zn2_cdc loader FIFO) | about 84 | measured fit; RAM and DSP from the GNET_Z1 and GNET_CPU50_B1 fits |
| Zoom board, split (ZOOM_FIT2X, measured) | 4,771 | 147 | 5 | 6.5; includes the virtual-pin share; the feeder gating and cap 1,024 came after it (a few registers) |
| zoom_cdc | 100 to 150 | 0 | 0 | about 300 registers: 61 + 61 request, 32 + 32 response, 61 pending, 32 answer |
| zoom_sdram_link | 100 to 150 | 0 | 0 | about 300 registers: 21 + 21 line, 3 x 64 response, 32 low word, 27 address |
| zn2_ch3_arb port c, zn2_board routing | 40 to 80 | 0 | 0 | 27-bit address and 32-bit read multiplexers |
| zoom_mix | 30 to 60 | 0 | 0 to 2 | two constant products per channel |
| **Total** | **33,720 to 33,890** (80.5 to 80.9% of 41,910) | **about 402** of 553 | **89 to 91** of 112 | |

The debug outputs that ZOOM_FIT2X kept as virtual pins (`dbg_regs`,
`dbg_pc` and the rest) are unconnected in the core and can be removed by
synthesis, so the Zoom share may come out below 4,771.

### 14.10 Fit to queue

`tools/pc_build.sh z1zoom push|task|run|fetch` (revision GNET_Z1_ZOOM,
DIR gn_z1zoom, TASK gnz1zoom). Points to read in the reports: the mailbox
RAM inferred as a dual-clock M10K pair (clk_1x, clk_2x) as in ZOOM_FIT2X;
the clk_2x MN10200 paths at 14.762 ns inside an 80% full chip (ZOOM_FIT2X
had +2.065 ns alone); the TimeQuest clock list (no new clocks); that no path
between the CPU clocks and clk_1x/clk_2x starts outside `cdc_tx_*`
(tools/sta/cpu50_xclk.tcl); RAM blocks and DSP against 14.9.

### 14.11 Open

| # | Item |
|---|---|
| I6 | DDR3 path: needs branch ddr3-arb-int (arbiter, flash area mirror); build with GNET_DDR3_ARB instead of GNET_ZOOM_SDRAM |
| I7 | SPU output scale against MAME's full scale (14.6), with R13 |
| I2, I5, Z17, Z10, R13 | as in 12 |

### 14.12 In the full build (branch gnet-full, revision GNET_Z1FULL)

GNET_Z1FULL = GNET_Z1SHELL plus GNET_DDR3_ARB, GNET_ROT_DDR and GNET_ZOOM
(no GNET_ZOOM_SDRAM), pc_build target z1full:

- Memory: zoom_m_* and zoom_rst go to the DDR3 arbiter's Zoom port
  (rtl/gnet/gnet_ddr3_zport.sv, docs/ddr3_arbiter.md 4); the lines come
  from the channel 3 flash mirror at DDR3 0x31000000; ZOOM_INFL 8. This
  closes I6 for that revision (not fitted, not run on hardware).
- Audio: zoom_mix (SPU 0.3, Zoom 1.0, taitogn.cpp:441-448) drives the
  shell's snd_l/snd_r, ahead of the OSD volume (gnet_volume).
- Pause: psx_top port zoom_hold (default 0) drives zoom_board's dbg_hold;
  PSX.sv connects the core pause (`paused`, clk_1x level, taken on clk_2x,
  one PLL). The MN10200 stops at its next instruction boundary; with the
  CPU out of reset the time base counts only its stepped cycles, so the
  ZSG-2 sample tick, the TMS57002 SYNC and the output FIFO pushes stop
  too, and zoom_out repeats its last sample (and sets its sticky underrun
  flag, zoom_flags bit 0). The pacer credit saturates at PACE_CAP (1,024
  cycles, about 5 samples) during the pause, which refills the output
  FIFO's lead after it. While the Zoom CPU is still held in reset
  (control bit 4) the time base runs on real time as before.
- Silent pause: PSX.sv forces both zoom_mix inputs to 0 while `paused`
  (the SPU, whose ce is held, and zoom_out would each repeat their last
  sample, a held DC level).

Verification of the full build's Zoom path (sim/zoomddr3, Verilator,
nice -n 15): zd3_top.sv wires zoom_board (CLK_H 4, PACE_CAP 1024, ZSG_INFL
8 or 4) to gnet_ddr3_zport and gnet_ddr3_arb as PSX.sv does, with a DDRAM
model from sim/ddr3arb (random BUSY, a 20-cycle BUSY run every 3,000
cycles, latency base plus jitter) and random core traffic on the C port.
gnet_ddr3_mirror is filled from a channel 3 write stream of the whole flash
area (clk_cpu 50 MHz); the DDR3 copy is compared with the image, then a
tb_zoomlink hev.log is replayed. tb_zoomlink now also writes mbx.log (the
MN10200 mailbox accesses and host acks in order) for
sim/zoomddr3/cmp_runs.py.

| Run | Result |
|---|---|
| Fill, normal and stressed (one write per clk_cpu, BUSY 40%, latency 40+40: 627,536 cycles of stall) | DDR3 copy equal to the image (0xA00000 bytes); mirror ovf 0 |
| Scripted canary events (51 ms), INFL 4, 8 and 8 stressed | 219,659 instructions and 700 lines as the SDRAM path; mbx.log identical; 24 instruction records differ, all in the TMS57002 EMPTY poll at 0x0834A4 (as tb_zoomref in 14.8); 0 stray rvalid, 0 errors, flags 00 |
| MAME replay 16.1529 to 18.40 s, INFL 8 | 1,298 lines, mbx.log identical to the SDRAM path (24 MN10200 accesses, equal to MAME's there; 274 host acks); 0 errors. The SDRAM run's instruction log splits from both the DDR3 run and tb_zoomref (ideal memory) at record 4,433,003 (the scheduler at 0x080832 sees a flag a tick earlier or later); DDR3 against tb_zoomref: same 7,835,451 instructions, 21 records differ, all in the EMPTY poll |
| Pause hold, 300 ms at 1.0 s of the replay and 10 ms at 20 ms of the canary (host events delayed by the hold) | one instruction retires as the hold rises, then none; at the boundary throughout; 0 machine cycles, sample ticks, TMS57002 SYNC, output pushes and lines during the hold; no output FIFO overflow (only the sticky underrun); pacer credit at the cap at release, 7,234 machine cycles in the first ms (6,250 plus the capped burst) then 6,246 to 6,254 per ms and 32 to 33 sample ticks; instruction log equal to the run without the hold through the hold and for about 1.1 s after it, mbx.log identical. While held the prefetcher re-reads 0x0807EE/0x0807F0 (program cache hits, no lines, no machine time) |

These windows have no ZSG-2 wave reads (no audio by 22.6 s), so every
line is a program cache fill.

Wave reads and audio against MAME (Ray Crisis, warm NVRAM,
tools/zoom/zoom_hostlog_aud.lua on the 61c7940 build, 16.1529 to 24.0 s:
the game's own Zoom audio starts at about 22.63 s, 8 to 11 ZSG-2 channels
from 23.1 s). Replayed through tb_zoomlink (SDRAM path), tb_zd3 (DDR3 path)
and tb_zoomref (ideal memory); the output compared is the TMS57002 SO1
pair at every output FIFO push (before the volume and the SPU mix) against
MAME's so[2]/so[3] >> 8 per DSP sample (sim/zoomddr3/cmp_audio.py,
cmp_mame_audio.py):

| Run | Result |
|---|---|
| SDRAM path | 0 errors, flags 00, 40 of 40 MN10200 mailbox accesses and 8 of 8 host reads equal to MAME's, 33,407 lines |
| DDR3 path, INFL 8 (BUSY 10%, latency 14+8, core traffic) | 0 errors, flags 00 (no ZSG-2 late or overrun), 0 stray rvalid; 33,406 lines of which 29,444 ZSG-2 wave lines, latency max 77 and mean 30.5 clk_1x; mbx.log identical to the SDRAM run |
| DDR3 INFL 8 against DDR3 INFL 4; against tb_zoomref | SO1 stream identical; 4 samples differ by 1 LSB near silence (memory timing moves an MN10200 register write by a sample) |
| ZSG-2 sends against MAME's TMS57002 serial inputs | RMS equal to within 0.5% on all four sends |
| SO1 against MAME, before the fix below | 1,760.5 RMS in MAME, 16.9 in the board (about 40 dB down) |
| SO1 against MAME, with the fix (tb_zoomref, guide and MAME TMS57002 sets) | RMS 1,760.7 against 1,760.7 (guide) and 1,760.6 (MAME set); error RMS 25.1 and 24.8 (1.4% of the signal), max abs error 169 and 175, aligned at the onset (offset 53 samples); exact samples under 1%, since this replay is not lockstep: the board's own ZSG-2 output feeds the DSP and differs from MAME's in the low bits and in where each key-on lands |

The fix (rtl/zoom/tms57002.sv): the core took its serial inputs when it
applied a SYNC, after the slots banked before it, but zoom_board pops the
ZSG-2 to TMS57002 queue (`sq`) on the `tms_sync` pulse itself, so by then
the head had moved on and was usually the never-written 0 of `sq[1]`: the
DSP read silence. Found by an instruction trace of the first sample with
signal (at PC 0x76 the standalone core, fed MAME's inputs, has MACC
fffff00000010, the board 0). The core now takes the four inputs into
`si_sync` at the sync pulse and applies them with the sync. The standalone
replay (sim/tms57002/run_vs_mame.sh mame, also --freerun) stays bit-exact
over the whole window, 44,626 non-zero samples. The SO1 difference from
sample 210,907 in 10.5 starts with the first signal there too, so it is
very likely this fault rather than the update timing (not rerun).

### 14.13 Files

| File | Content |
|---|---|
| rtl/gnet/zoom_cdc.vhd | Z1 and Z2 crossings |
| rtl/gnet/zoom_sdram_link.vhd | temporary SDRAM path (GNET_ZOOM_SDRAM) |
| GNET_Z1_ZOOM.qsf; tools/pc_build.sh target z1zoom | the revision |
| sim/zoomlink/run.sh, tb_zoom_cdc.vhd, mutants.py, check_ports.py | NVC crossing benches, elaboration, lint, port check |
| sim/zoomlink/build.sh, zl_vtop.vhd, zl_dpram.vhd, zl_common.h, tb_zoomlink.cpp, tb_zoomref.cpp | integration bench and its reference |
| tools/zoom/zoom_hostlog.lua, zoom_hostlog.sh | light MAME log of the main CPU's Zoom traffic and the MN10200's mailbox accesses |

## 15. Exact TMS57002 landing (I5), shorter ZSG-2 read wait, audio against MAME (branch zoom-i5)

Branch zoom-i5 from zoom-into-z1 d15f51d. Not fitted.

### 15.1 Host events at the end of the writing instruction

Before: a host byte reached the TMS57002 as soon as the MN10200 wrote it,
PLOAD and CLOAD followed port 1 as levels. In virtual time that is the
start of the writing instruction, minus any slots the feeder still held,
so a byte could land up to one sample early (10.5).

Now (rtl/zoom/zoom_board.sv "host events", zoom_tmsfeed.sv):

- Each host byte (0xC00000) and each change of port 1 bits 0 and 1 is an
  event with a time in DSP slots: 2 x (cyc_cnt + acc_cyc), the machine cycle
  count at the end of the writing instruction, where MAME places every
  access (mn10200.cpp charges the cycles first; the ZSG-2 lookahead uses the
  same point, 6.2). Cycles are never stepped during an access, so cyc_cnt
  is the count before the instruction. For the port write the core's
  acc_cyc at the internal register write is kept in a new mn10200 output,
  `io_cyc`, because the change shows on p1_out one clock later. While the
  MN10200 is held a pin change (its reset value) lands at once.
- zoom_tbase's cycle counter is 16 bits wide; the feeder counts the slots it
  has delivered from the same origin (every stepped cycle gives two slots).
- The events cross to clk as the other pulses (held over an s_en cycle) and
  wait in a 16-entry queue. The feeder delivers the head once its slot is
  reached: after a SYNC at the same point (a boundary at or before the
  access comes first, as for the ZSG-2), before any later slot, and only
  when the TMS57002 has executed every slot, SYNC and host request given so
  far (new tms57002 output `busy`), so the byte or pin change falls between
  exactly the two slots the PCB's one crystal puts it between.
- The MN10200 starts no instruction while 12 or more events wait (the
  queue never filled in the runs below; an overflow would set flag bit 6
  with a merged SYNC).

Verification: the lockstep testbench (sim/zoomboard/tb.cpp, MAME parameter
set, pacer on, cap 1,024) now takes each landing when the byte reaches the
TMS57002. MAME 0.288 (61c7940) streams recorded once
(sim/zoomboard/record_oracle.sh) and replayed into three builds
(sim/zoomboard/run_builds.sh): the RTL of d15f51d, I5 alone, and I5 with
15.3:

| Run | Build | Instructions, accesses, ZSG-2 samples equal | Host bytes in MAME's sample / one later / one earlier | CMEM updates in MAME's sample / board later / board earlier | SO1 equal before the first difference |
|---|---|---|---|---|---|
| psyvaria 18 s, no input (12.5 s of Zoom time) | d15f51d | 38,796,282, 309,559, 407,444 | 268,470 / 0 / 1,399 | 50,496 / 2,827 / 5 | 372,443 |
| same | I5 (with or without 15.3) | the same | 269,856 / 13 / 0 | 50,246 / 3,082 / 0 | 372,443 |
| psyvaria 40 s, coin at 20 s (34.5 s) | d15f51d | 103,543,027, 958,482, 1,124,037 | 622,174 / 0 / 3,265 | 117,727 / 6,695 / 19 | 372,443 |
| same | I5 (with or without 15.3) | the same | 625,413 / 26 / 0 | 117,113 / 7,328 / 0 | 372,443 |

No landing is earlier than MAME's any more, as the argument of 10.5
requires (MAME's DSP lags its MN10200 inside a 60 kHz timeslice, so its
landing is early or equal): on average 14 slots after MAME's, at most 150.
The few updates that move from MAME's sample to the next are those whose
last byte the board used to land early. The first SO1 difference stays at
sample 372,501: it comes from the board-later updates of 10.5, which are
the physical behaviour, so SO1 against MAME cannot get closer than this
with exact landings. Board flags 00, no repeated output sample.

### 15.2 Firmware behaviour

Nothing the MN10200 does changes (every instruction and access equal in
all runs). The board's EMPTY (IRQ1) still differs from MAME's at some
instruction starts (the testbench takes the pin from MAME, 10.3); with I5
the DSP takes updates later, so it differs at more of them (538,059
against 430,148 in the 18 s run), which only changes how long the
firmware polls.

### 15.3 ZSG-2 reads inside a pass

A ZSG-2 read used to wait for the whole pass of the current sample (up to
769 clk_1x), the main source of the MN10200's lag in play (6.4). Now
(rtl/zoom/zsg2.sv, parameter `MID_READ`, zoom_board `ZSG_MID_READ`,
default 1) a read of a channel the running pass has already rendered, or of
a global register, is answered at the next channel step of that pass (two or
three clocks, then the pass goes on). Those values are final for the tick: a
channel's state changes only in its own step, and CPU writes wait for the
pass. The condition also requires that only this pass is outstanding and
no write is queued. The read returns the same data, so MAME equality is
unchanged (all 77,164 ZSG-2 reads of the 40 s run equal).

| psyvaria 40 s, coin at 20 s | ZSG-2 read wait (clk_2x) | Max lag | Clocks with lag >= 128 / 256 cycles |
|---|---|---|---|
| d15f51d | 7,244,777 | 682 cycles (109 us) | 3,477,855 / 1,585,292 |
| I5 alone | 7,244,777 | 682 cycles | 3,477,875 / 1,585,292 |
| I5 and MID_READ | 4,224,816 | 217 cycles (35 us) | 71,830 / 0 |

In the 18 s attract run the read wait halves (55,735 to 26,686) and the max
lag stays at 131 cycles. The pacer rate stays exactly 6.2500 MHz.
Cost (estimate, not fitted): a few registers and multiplexer inputs in zsg2 (the return state
and the channel compare), about 30 ALMs; the event queue in zoom_board is
16 x 26 bits (MLAB or registers) plus about 60 ALMs of feeder and capture
logic. The PCB answers a read at once; 35 us is the remaining classified
difference against MAME's 16.7 us coupling quantum.

### 15.4 Audio against MAME through the integrated path

MAME window: tools/zoom/zoom_hostlog.sh with `ZOOM_HOSTLOG_SO=1` (the
TMS57002's SO1 pair once per sample) on Ray Crisis warm, 50 s, coin at 30 s:
the Zoom output is silent until 22.632 s and plays from there (the attract
music after the command group at 22.517 s, 14.8), every sample non-zero to
the end of the run. The integration bench (sim/zoomlink, built with the MAME
TMS57002 set, `TMS_MAME=1 sim/zoomlink/build.sh`) replays MAME's main-CPU
traffic from 16.1529 s to 23.70 s through zn2_board, zoom_cdc, the SDRAM
path and zoom_board, and writes the board's SO1 pair at every SYNC
(so.bin); sim/zoomlink/compare_so.py compares it with MAME's.

The first run showed the board almost silent (SO1 RMS 159 against MAME's
561,233 in 24-bit units). Cause, found the same night on branch gnet-full
(2c8476d) and applied here and on zoom-into-z1 (da92ac2): the TMS57002 took
its serial inputs when it applied a SYNC, after its banked slots, while
zoom_board pops the ZSG-2 to TMS57002 queue on the SYNC pulse, so the DSP
read the next, normally empty, entry. It now takes them at the pulse. The
lockstep runs of 15.1 give the same results with the fix (all counts
unchanged in the 18 s run); the lockstep testbench's feeder timing hid the
fault there.

With the fix (I5 and 15.3 included; 7.547 s simulated, 0 bench errors, all
40 MN10200 mailbox accesses and 8 host reads equal to MAME's):

| Check | Board | MAME |
|---|---|---|
| First non-zero SO1 sample after the release | 210,908 | 210,908 |
| SO1 RMS over the 34,744 music samples (24-bit) | 450,559.5 | 450,569.8 |
| Error RMS at the best offset (0) | 5,970 (1.33% of MAME's), max 45,731 | |
| Samples equal | 568 of 34,744 | |

The music starts in the same sample and has the same level; it is not
bit-exact. The free-running board differs from MAME where the lockstep
testbench forces MAME's values: the MN10200 timers run in the chip's
shared-prescaler phase (`TIMER_EXACT` 0, the core's setting), the board's
own EMPTY drives IRQ1, the time base is not loaded with MAME's sample
phase, and the coefficient updates land at the physical point (10.5,
15.1). Bit-exact SO1 against MAME is covered by the lockstep testbench
(15.1: 372,443 samples).

### 15.5 Files

| File | Change |
|---|---|
| rtl/zoom/zoom_board.sv | host event capture, queue and delivery; `ZSG_MID_READ` |
| rtl/zoom/zoom_tmsfeed.sv | delivered-slot counter, event delivery |
| rtl/zoom/zoom_tbase.sv | 16-bit cycle counter |
| rtl/zoom/mn10200.sv | `io_cyc` |
| rtl/zoom/tms57002.sv | `busy` |
| rtl/zoom/zsg2.sv | `MID_READ` |
| sim/zoomboard/tb.cpp, record_oracle.sh, run_recorded.sh, run_builds.sh | landing at delivery; recorded streams |
| sim/zoomlink/tb_zoomlink.cpp, zl_vtop.vhd, build.sh, compare_so.py; tools/zoom/zoom_hostlog.lua | SO1 dump, TMS_MAME build, SO1 log and coin input in MAME, comparison |
