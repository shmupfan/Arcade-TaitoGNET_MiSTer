# TMS57002 RTL (Taito Zoom effects DSP): status

Status: M3, the DSP in RTL with its delay RAM and host interface, verified
against MAME 0.288 by sample replay (2026-10-05). Not yet fitted; not yet
connected to the Zoom block. Design: docs/zoom_zsg2_tms57002_design.md
("design study"). Own code throughout: I wrote it from the design study,
the TMS57002 User's Guide (TI 1992, "guide", read from the page images in
`mister-arcade-survey/datasheets/tms57002/`) and MAME's behaviour where the
guide is silent. Nothing is taken from XelaNotPu's FX-1B core (I did not
open it).

## 1. Summary

- `rtl/zoom/tms57002.sv`: two modules (`tms57002`, `tms57002_xram`),
  about 630 lines. It implements what the two firmware programs use
  (design study 4.3): 16 primary, 19 secondary and 3 category 3 opcodes,
  DMEM0 with BA0, the 64 KB delay RAM in the ST0 = 0x0084AA mode, the host
  interface (ST0/ST1/PMEM download, CMEM download, CMEM update with 16
  UPDATE registers and EMPTY), SYNC, and SO1. Anything else sets
  `dbg_unsup` and prints in simulation.
- Rate: one instruction slot per `step` pulse, two clocks per instruction,
  so clk_1x (33.8688 MHz) gives 16.9 M slots/s against the 12.5 M needed
  (384 per sample).
- Verification: a Verilator testbench replays MAME 0.288 traces of the DSP
  host port (every byte and PLOAD/CLOAD change, at the DSP sample and PC
  where MAME made it) and of the serial inputs, and compares the SO1 pair
  of every sample plus full state snapshots (registers, CMEM, DMEM0, PMEM,
  all 32K delay RAM words). Three games, 60 s each (attract, a credit,
  play): raycris and nightrai (program A), psyvaria (program A, then B).
- Result with the MAME-equivalent parameters: bit-exact. Every compared
  SO1 sample (24 bits) equals MAME's, 5,850,386 samples of which
  4,156,318 are nonzero, and every periodic snapshot equals MAME's whole
  state (section 4.3). The same holds with the free-running time base.
- With the guide's behaviour (the defaults) the output differs from MAME in
  three places, each traced to a page of the guide (section 5). The first
  divergence in time is the multiplier input for `MPY C,A`: MAME
  multiplies by all 32 AACC bits, the guide's 32 x 25 array takes AACC
  bits 31-8 (guide p.3-22). The guide outranks MAME, so the core follows
  the guide by default.
- Area: not measured (no Quartus run). Paper estimate 630 to 970 ALMs,
  67 M10K (64 for the delay RAM), 2 DSP, inside the design study's range
  (710 to 1,240 ALMs). A stand-alone fit revision is ready (section 6).

## 2. Files

| File | Content |
|---|---|
| `rtl/zoom/tms57002.sv` | DSP core, host interface, memories, delay RAM module |
| `sim/tms57002/tb.cpp` | Verilator replay testbench (stepped and `--freerun`) |
| `sim/tms57002/build.sh` | Builds a testbench variant: `guide`, `mame`, or `mame` plus -G overrides |
| `sim/tms57002/run_vs_mame.sh`, `run_variants.sh`, `run_matrix.sh` | Runners (two simulations at a time, nice 15) |
| `tools/tms57/tms57_trace.lua`, `tms57_trace.sh` | MAME 0.288 oracle: host port log, per-sample serial in/out, state snapshots |
| `tools/tms57/tms57_dis.py` | Disassembler and program statistics (prints game code; never commit its output) |
| `TMS57002_FIT.qpf`, `.qsf`, `.sdc` | Stand-alone area-check revision (not run); `tools/pc_build.sh tms57` |

Traces, listings and testbench builds go to `sim/zoom/` (gitignored).

## 3. What is implemented

### 3.1 Instructions

Field layout as guide Fig. 4-2 and 4-3 (pp.4-4, 4-5); opcode numbers as
MAME's `tmsinstr.lst`.

| Category | Opcodes (hex) | Mnemonics |
|---|---|---|
| 1 ALU | 01, 04, 05, 06, 09, 11, 12, 15 | abs; add c,a / d,m / c,m; sub d,a; lacd; lacc; and c,a |
| 1 MAC | 21, 22, 24, 26, 31, 35 | mpy d,c / c,a; mac d,c / c,a; lmhd; sfmr |
| 1 external RAM | 38, 39 | wre, rde |
| 2 before the primary | 01, 02, 03, 05, 06, 07, 0F, 10-13, 22, 23 | sacc, sacd, smhd, smhc, slmh, slml, srbd, dis (4 inputs), domh so1_l / so1_r |
| 2 after the primary | 3C, 3D, 60-63 | raom, saom, sfmo 0 / 2 / 4 / -8 |
| 3 | 08, 18, 20 | idle, lcak, lirk |

Program A uses 01 04 05 06 09 11 12 15 21 22 24 31 35 38 39 and program B
01 04 06 11 12 21 22 24 26 31 38 39 (tools/tms57/tms57_dis.py on the
snapshots of the raycris and psyvaria traces). Neither uses a branch, RPTK,
DMEM1 (DBP stays 0, no ADDS/AMAC/AMPY/LD0T/STD1), SO0, SFAI, SFAO, SFMA,
CRM or an RND other than 0 and 1.

Order inside a word follows guide p.4-2 ("the secondary instruction will
take precedence") and MAME (tmsmake.py EmitCdec): the secondary transfer
uses the old AACC and MACC, a primary that reads the same operand sees
the secondary's data, mode changes (SFMO, SAOM, RAOM) apply from the next
word.

### 3.2 Datapath

- Addressing (guide 4.3, Table 3-2 p.3-15): DMEM0 at (G or ID) + BA0, CMEM
  at G or CA; post increments from bits E and P. An increment applies only
  to an operand the word references (MAME tms57kdec.cpp:15-30; the guide
  does not say, and no word in either program sets an increment on an
  unreferenced operand).
- ALU: 32-bit AACC, overflow to AOV (guide p.3-17). ST1 bit 3 saturates on
  overflow when set by SAOM; bit 3 is "reserved" in guide Fig. 3-24 and
  SAOM/RAOM are not in the guide, so this is MAME's behaviour
  (tmsmake.py:70-75, tmsinstr.lst:549-557). Program A sets it around one
  ADD (PMEM 224 to 230).
- MAC: product of CREG (32 bits) and DREG (24 bits sign extended to 25),
  MSB and 7 LSBs dropped, sign extended into the 52-bit MACC (guide
  pp.3-18 to 3-22). A MAC result is read by an output instruction two
  words later, an accumulation sees it at once (guide p.3-28 note): the
  core keeps `mw`, the MACC value at the start of the previous word, as
  MAME's macc_write (tms57002.cpp:860-861).
- MACC output (guide pp.3-22, 3-23): SFMO shift, RND (0 and 1), MOVM limit
  and the MOV flag for DOMH, SMHD, SMHC and the ALU's MACC operand;
  overflow check and limit without shift for SLMH and SLML.
- External RAM (guide pp.3-63 to 3-72): address (XOA + XBA) mod 32K, one
  16-bit word, M10K. An RDE or WRE runs for XM_CYCLES slots; RDE/WRE in
  that time are ignored and SRBD reads the previous XRD (p.3-72).
- Serial: four 24-bit inputs latched at SYNC; with ST0.SIM = 1 bits 7-0
  read 0 (guide p.3-32). SO1 left and right latched at SYNC, 24 bits, plus
  the top 16 bits as the SOM = 2 word (design study 4.5).
- SYNC (guide p.3-36; XBA: p.3-66, design study 4.1): PC, CA, ID to 0,
  BA0 - 1 (INCS = 0), XBA - 1, AOV and MOV to 0, IDLE released. Ignored
  while PLOAD is low (MAME tms57002.cpp:220; the guide is silent).

### 3.3 Host interface

Modes as guide Table 3-6 (p.3-37); byte order MSB first (pp.3-39 to
3-42).

- PLOAD low: execution stops; the falling edge restarts at ST0 and sets PC
  and CA to 0 (MAME tms57002.cpp:40-57). Bytes fill ST0, ST1, then PMEM.
- PLOAD and CLOAD low: CMEM download from CA.
- CLOAD low alone: the first byte is SA, then up to 16 words go to the
  UPDATE registers (guide p.3-42). EMPTY is high while all are empty.
- An update starts at a CMEM read of address SA after CLOAD has returned
  high, then every CMEM read takes the next word (guide p.3-43, example
  p.3-44); the word replaces the operand and is written to the address
  read.

### 3.4 Timing

Two clocks per instruction: RUN (decode, operand addresses to the M10K
ports, prefetched PMEM word) and EXEC (datapath, write back, PMEM
prefetch of PC + 1). Instructions run back to back. `step` grants slots
into a credit counter; `sync` splits the credit into the slots before it
(used first) and after it. Host bytes and pin changes are taken between
instructions, before the next slot starts. PLOAD and SYNC also restart the
PMEM fetch (one extra clock).

## 4. Verification

### 4.1 Oracle

`tools/tms57/tms57_trace.sh <set> <s> <nvram> <outdir>` runs stock MAME
0.288 (`/opt/homebrew/bin/mame`) with `tms57_trace.lua`:

- every MN10200 write to 0xC00000 and to port 1 (0xFE64), with the DSP's
  XBA, PC, `sti` and `hidx` at that moment;
- per DSP sample, at its first external RAM read: XBA, PC, the four `si`
  words and the four `so` words MAME streamed at that sync;
- full snapshots (save items, PMEM, the 64 KB data space) before the first
  download, at the first idle point after each PLOAD release ("resync")
  and every 10 s ("periodic").

The DSP comparison uses MAME's own serial input words, so the ZSG-2 fix
61c7940 does not matter here; stock 0.288 is enough.

### 4.2 Replay method

The testbench counts syncs as MAME's XBA does, so the XBA logged with an
event gives its sample. Stepped mode grants one slot at a time and applies
each host input when the core stands at the logged PC. `--freerun` drives
`step` from a 12.5 / 33.8688 accumulator and `sync` every 384 steps, as the
G-NET time base will, and holds the core (`dbg_hold`) only while it
injects inputs that MAME made at one DSP position.

Two kinds of samples are not compared:

- After a PLOAD release MAME resumes the new program mid-sample if the DSP
  was not idle when PLOAD fell, and the number of instructions before the
  next sync depends on MAME's scheduler (the DSP starts at the beginning
  of the MN10200's timeslice). The testbench skips the samples from each
  PLOAD fall to the next "resync" snapshot, reports the state differences
  there and loads MAME's state. These windows cover 22 samples in
  raycris, 389 in psyvaria and 386 in nightrai.
- A Zoom reset (main CPU) resets XBA; the testbench waits for the next
  resync.

### 4.3 Results

Trace sizes: raycris 1,304,149 host writes (162,717 update episodes, 3
downloads), psyvaria 1,434,376 (178,944 episodes, 3 downloads, program B
from 9.94 s), nightrai 3,244 (156 episodes, 2 downloads); 1.95 million
samples each.

| Set | Samples compared | Nonzero in MAME | Skipped (windows) | `mame` stepped | `mame` free-running |
|---|---|---|---|---|---|
| raycris (A) | 1,950,371 | 1,216,640 | 22 | 0 mismatches | 0 mismatches |
| psyvaria (A, B) | 1,949,991 | 1,463,140 | 389 | 0 | 0 |
| nightrai (A) | 1,950,024 | 1,476,538 | 386 | 0 | 0 |
| Total | 5,850,386 | 4,156,318 | 797 | 0 | 0 |

Mismatch = a compared sample whose SO1 left or right 24-bit word differs
from MAME's. No input reached the core at a different PC than MAME's
("position mismatches" 0); the free-running runs reached every input in
time ("late" 0). The one sync that came while a program still ran
(psyvaria, free-running) fell in the skipped window after the Zoom reset
at 5.5 s.

All periodic snapshots (5 per game) equal MAME's state in the `mame` runs,
stepped and free-running: ST0, ST1, PC, CA, ID, BA0, XBA, AACC, MACC, the
MACC pipeline register, XRD, SA, the UPDATE count, SO1, all of CMEM, DMEM0
and PMEM, and all 32,768 delay RAM words. Resync snapshots after a
download alone match in full (raycris 0.09 s and 18.61 s, psyvaria
0.09 s and 9.94 s, nightrai 0.09 s); those after a Zoom reset differ
(raycris 192 items at 16.17 s, psyvaria 216 at 5.53 s, nightrai 264 at
5.50 s, mostly DMEM0), as expected from the skipped window.

### 4.4 Bug found by the free-running replay

The first free-running run diverged where the stepped one did not: with
instructions back to back, a DMEM or CMEM write registered one clock late
collided with the next instruction's read of the same word. The core now
drives the EXEC write ports combinationally, so the write lands at the end
of EXEC; both modes then agree on every sample.

## 5. Divergences from MAME

Each line is one parameter changed from the MAME set to the guide's value
(sim/tms57002/build.sh), replayed over the same traces. Mismatch counts are
compared samples whose SO1 word differs from MAME's (24-bit / 16-bit).

| Parameter (MAME / guide) | raycris 24 / 16-bit | psyvaria 24 / 16-bit | nightrai 24 / 16-bit | First divergence (raycris) |
|---|---|---|---|---|
| XM_CYCLES 2 / 6, XM_COUNT_IDLE 0 / 1 | 0 / 0 | 0 / 0 | 0 / 0 | none |
| MPY_A32 1 / 0 | 610,950 / 8,421 | 0 / 0 | 686,204 / 3,078 | sample at about 22.65 s: left 0x00870B against MAME 0x00870C |
| UPD_AFTER_CLOAD 0 / 1 | 957,853 / 957,498 | 1,394,516 / 1,392,575 | 0 / 0 | about 30.56 s: right 0xFFCFAB against 0xFFD053 |
| SI_RAW 1 / 0 | 1,214,513 / 1,202,776 | 1,360,466 / 1,125,393 | 0 / 0 | about 22.69 s: right 0xFFC71D against 0xFFC7C5 |
| all four (`guide`) | 1,215,356 / 1,214,119 | 1,394,667 / 1,392,968 | 686,204 / 3,078 | about 22.65 s (MPY_A32) |

24-bit counts are the larger of left and right; 16-bit counts are samples
where either side's top 16 bits differ. Times are those of the nearest
logged host input. In psyvaria the MPY_A32 difference changes 1 to 5
state words at the snapshots but never reaches SO1 in these 60 s, and
nightrai has no input word with bits 7-0 set (0 of 1,950,410) and only
156 updates, which give the same output both ways.

Notes:

- **MPY_A32** (multiplier input from AACC). MAME computes `c * aacc >> 15`
  with all 32 AACC bits (tmsinstr.lst:301-305, 266-270). Guide p.3-22: for
  24-bit input from the B bus, AACC bits 31-8 go to the MAC input shifter
  (Fig. 3-10: 32 x 25 multiply array). The two agree when AACC bits 7-0
  are 0. Program A runs `mpy C(76),a` after `lacc C(78)` (PMEM 25 to 27),
  a coefficient with low bits set, so its output differs in the low bits
  of the 24-bit word. Core: guide.
- **UPD_AFTER_CLOAD** (CMEM update start). MAME queues the word at the
  fourth byte and applies it at the next read of SA even while CLOAD is
  still low (tms57002.cpp:136-157, comment at 146; 683-697). Guide p.3-43:
  the compare starts for CMEM reads after CLOAD has been set high. The
  firmware raises CLOAD 0.64 us (8 slots) after the fourth byte (median
  and minimum over the 162,717 raycris episodes), but in MAME the DSP runs
  in timeslices, so the logged distance between the two in DSP slots
  ranges from 0 (50,855 episodes) to more than a sample. An update that lands one
  sample later shifts the effect LFO phase accumulators for good (program
  A: `lacc C(77); add C(80),a; abs; sacc C(77)` at PMEM 7 to 9), hence the
  persistent mismatch. Core: guide (design study Z9).
- **XM_CYCLES / XM_COUNT_IDLE** (external RAM timing). MAME completes an
  access in 2 executed instructions (one byte each, tms57002.cpp:852-858),
  the guide in 2(m + 1) = 6 machine cycles for DRAM with 8-bit port and
  16-bit words (p.3-72). Both programs leave at least 8 words between an
  RDE and the next RDE/WRE and 10 before SRBD (tms57_dis.py), so the
  output is identical. Core: guide.
- **SI_RAW** (serial input width). MAME routes ZSG-2 sends 0 and 1 to the
  DSP at gain 0.5 and converts through float (taito_zm.cpp:205-206,
  tms57002.cpp:927-931), so input bits 7-0 are not 0 in about 40% of
  samples (raycris 796,705 of 1,950,393). With SIM = 1 the chip receives
  16-bit words and bits 7-0 are 0 (guide p.3-32). The reverb feeds back, so one
  bit changes most later samples. This is a board-level difference (design
  study Z7): the ZSG-2 RTL will deliver 16-bit words. Core: guide.

Further differences that the traces do not exercise:

- MACC width. MAME keeps MACC in 64 bits; the core in 52 (guide p.3-18).
  They differ only beyond the 52-bit range or after SFML/SFMR of a
  negative value followed by an ALU read of MACC (MAME clears bits 63-52).
  Program A's two SFMR results go to SLML only (PMEM 31/33, 55/57).
- RND 3: MAME rounds at bit 17 (tmsmake.py:48, "48-30"), not at the
  20-bit point the guide names (p.3-23). Not implemented (asserted).
- Partial program after a PLOAD release (4.2): the core does what MAME
  does (resume at PC 0 if not idle); the guide is silent.

## 6. Area expectation and fit project

Paper estimate, method as docs/mn10200_design.md 5.9:

| Unit | ALMs low | ALMs high | M10K | DSP |
|---|---|---|---|---|
| Host interface, UPDATE registers (MLAB), EMPTY | 60 | 100 | | |
| Sequencer, slot credit, PMEM fetch | 40 | 70 | 1 | |
| Decode (two copies: RUN and EXEC) | 30 | 50 | | |
| Addressing, CMEM/DMEM ports | 40 | 70 | 2 | |
| ALU (43-bit add/sub, abs, limits, operand muxes) | 110 | 160 | | |
| MAC (52-bit accumulate, LMHD/SFMR, 32 x 25 multiply) | 70 | 110 | | 2 |
| MACC output (58-bit shifter, rounder, limiter, MOV) | 120 | 170 | | |
| Secondary data muxes, SI/SO registers | 80 | 120 | | |
| External RAM address, XRD, timer | 30 | 50 | 64 | |
| Registers not packed with logic | 50 | 70 | | |
| **Total** | **630** | **970** | **67** | **2** |

Design study 6.5 expected 710 to 1,240 ALMs, 67 M10K, 2 DSP with the full
instruction set; leaving out DMEM1, branches, RPTK and the unused modes
accounts for the lower range. The MAME-only parameters (MPY_A32 = 1) would
add a 32 x 32 multiplier; they are for simulation.

Fit revision: `TMS57002_FIT` (top `tms57002`, guide defaults, every port a
virtual pin, 29.525 ns clock), target `tools/pc_build.sh tms57`
(DIR gn_tms57, TASK gntms57). Not run.

## 7. Open items

1. Fit: queue `tools/pc_build.sh tms57 push`, `task`, `run`, then
   `fetch`; check ALMs against section 6 and timing at 33.8688 MHz (the
   longest paths are CMEM read to MACC through the multiplier and MACC to
   AACC through the output shifter and the 43-bit adder, each one clock).
2. Integration (design study 6.1): `step` two per MN10200 machine cycle,
   `sync` every 384 slots, host decode of 0xC00000 and port 1 bits 0/1,
   EMPTY to IRQ1 inverted, the ZSG-2 sends as 16-bit words (send 0/1
   scaling, Z7), SO1 16-bit words to the output FIFO, `dbg_hold` tied 0.
3. Delay RAM starts at 0 (M10K power-up); the PCB's DRAM does not (Z13).
4. The partial program after PLOAD release follows MAME; nothing above
   MAME settles it.
5. Coverage: 3 of 6 games, 60 s each. psyvarrv, shikigam and xiistag run
   the same two programs (design study 4.3).

## 8. Questions for Lee

1. Default behaviour: the core follows the guide on the three points of
   section 5, so its SO1 will not be bit-exact against stock MAME at board
   level (the input width alone changes most samples once reverb is
   active). Keep the guide as default and use the `mame` parameter set
   for oracle runs, or the other way round for the M3 gate?
2. May I (or you) queue the `tms57` fit on the compile PC?
