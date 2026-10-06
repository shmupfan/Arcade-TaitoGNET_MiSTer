# CPU-rate timing probe (R1)

2026-10-04. Question: which paths in the PSX_MiSTer CPU side would fail if
the CPU domain ran at 50 MHz (the inferred ZN-2 rate, PLAN.md R1) or at
67.7376 MHz (Robert Peip's experimental 2x build), measured on the LEAN
build `builds/20261004_2011_lean` (bcdec20, 65.7% ALM).

Method: `tools/sta/cpu50_probe.tcl` in TimeQuest (slow model) on the existing
fit, no constraint changed. On clk_1x (33.8688 MHz, 29.524 ns) a path with
setup slack s has about (29.524 - s) ns of data path, so it fits 20 ns if
s >= 9.524 ns and 14.762 ns if s >= 14.762 ns. Worst path per endpoint, for
registers in cpu, gte, dma, memctrl and memorymux (15,539 registers).

## Result

| Target | Failing endpoints | Worst over budget | Where |
|---|---|---|---|
| 50 MHz (20 ns) | 418 | 2.99 ns | cpu -> memorymux 312 (worst 2.99 ns); cpu -> cpu 106 (worst 1.24 ns) |
| 67.7376 MHz (14.76 ns) | 1,446 | 8.23 ns | cpu -> cpu 1,131 (worst 6.48 ns); cpu -> memorymux 315 (worst 8.23 ns) |

GTE, DMA and memctrl have no failing paths at either rate in this probe.

The 50 MHz failures are concentrated in one structure: `cpu.decodeJumpTarget`
feeding the memory request in memorymux combinationally (ram_Adr 2.99 ns
over, ram_ena 2.89, ram_dataWrite 2.04, page address, byte enables, cache
tags, wait counter, 1.4 to 1.7 ns). The CPU-internal paths are within
1.24 ns of 20 ns.

## Reading

- 50 MHz looks reachable with targeted work: one address-path structure to
  restructure, plus CPU-internal paths that are close enough for a fit
  constrained at 50 MHz to recover part of them (this fit was placed for
  33.87 MHz, so its paths were not pushed).
- 67.7 MHz (Peip's 2x approach, then clock-enabled down to 50 MHz on
  average) is much harder on this toolchain and fill level: 1,446 endpoints
  and up to 8.2 ns over.
- Registering the jump-target fetch address would add a cycle to jumps; any
  such change must keep the CPU's cycle behaviour (counted in the original
  clock's cycles) or it changes the very slowdown I am trying to get
  right. The design choice belongs in the CPU-rate plan, not here.

Next: a fit with the CPU-side paths constrained to 20 ns (set_max_delay in a
probe SDC) to see what the fitter recovers on its own, then the CPU domain
design.

## Constrained fit (2026-10-04)

Revision GNET_F0_CPU50 = LEAN plus `GNET_CPU50.sdc`: set_max_delay 20 ns on
cpu -> cpu and cpu -> memorymux register paths (all clk_1x, so this only
tightens). Build `builds/20261004_2123_cpu50` (flow 38 min, RBF md5
c3118e30b535f6d8ddf0d6e827684674). Check: `tools/sta/cpu50_check.tcl`.

| Measure | LEAN | CPU50 fit |
|---|---|---|
| ALMs | 27,534 | 27,610 (+76) |
| CPU-side endpoints failing 20 ns | 418 (probe, unconstrained fit) | 0 |
| Worst CPU-side path against 20 ns | -2.99 ns | +1.959 ns (cpu writebackTarget -> PCold0, "Setup Relationship (from Max Delay) 20.000") |
| Other clocks | all met | all met (worst setup +0.245 ns pll_hdmi, worst hold +0.246 ns) |

Reading: with the fitter asked for 50 MHz, every CPU-internal and
CPU-to-memorymux register path makes it with 1.96 ns to spare, at a cost of
76 ALMs. The jump-target to memory-address path that was 2.99 ns over in
the unconstrained fit closes without an RTL change. Not yet covered: paths
from memorymux back into the CPU, the GTE at a matching rate, and the clock
domain crossing that a separate CPU clock would add; those come with the
CPU-domain design. This makes a true-rate (about 50 MHz) CPU domain look
feasible on area and timing at the current fill level.

## Target rate from PCB footage

docs/r1_speed_study.md (PCB footage, rank 4): CPU-bound code on the board
runs at about 0.82 of MAME's ZN-2 model (boot loader 14.69 s against
12.34 s; matched at 82 MHz in a patched MAME). Because MAME's model has no
wait states and simple cache timing, this is consistent with a 50 MHz CPU
domain plus real memory timing. Plan: build the 50 MHz domain, then
calibrate wait states and cache behaviour against the 14.69 s loader
measurement. Slowdown in play comes mostly from GPU drawing time, which the
PSX_MiSTer GPU models and MAME does not (R23).

## Experiment B: whole CPU side at 50 MHz, GTE at 100 MHz (2026-10-04)

Revision GNET_F0_CPU50B (`GNET_CPU50B.sdc`): 20 ns max delay among cpu, dma,
memorymux and memctrl registers in both directions; into GTE registers 20 ns
from clk_1x and 10 ns from clk_2x (the GTE runs on clk_2x, so a 50 MHz CPU
with the same ratio needs a 100 MHz GTE). Build `builds/20261004_2254_cpu50b`,
27,504 ALMs; check `tools/sta/cpu50b_check.tcl`.

| Path group | Failing endpoints | Worst slack |
|---|---|---|
| CPU side (cpu, dma, memorymux, memctrl), both directions, 20 ns | 0 | met |
| GTE outputs to the CPU side, 20 ns | 0 | met |
| Into GTE registers (10 ns from clk_2x) | 631 (628 inside the GTE) | -3.01 ns, MAC1req.mul1 -> gte_mac123 mac_result |

Reading: the CPU, DMA and memory paths reach 50 MHz without RTL changes.
The GTE's multiply-accumulate units do not reach 100 MHz (3 ns short).
Options for the CPU-domain design: pipeline the GTE MAC stages (keeping
the GTE's result timing in CPU cycles), or run the GTE at a ratio below 2x
the CPU clock if its cycle counts allow it. The real CXD8661R runs the GTE
on the CPU clock with fixed cycle counts per command; PSX_MiSTer's 2x GTE
clock is an implementation choice to finish within those counts. Next step:
read how gte.vhd counts command cycles to see how much margin the 2x clock
provides.

GTE timing note (rtl/gte.vhd): the GTE is a clk_2x state machine; gte_busy
stays high from a command (taken when clk2xIndex = '1') until its CALC_*
steps finish, and the CPU waits on it. Command latency in CPU cycles is
therefore (steps / clock ratio). Running the GTE at 1.5x instead of 2x the
CPU clock would make every GTE command 1.33 times longer in CPU cycles, i.e.
more slowdown than PSX_MiSTer intends, so a slower GTE clock is not a free
option. Preferred route: keep the 2x ratio (100 MHz) and pipeline the MAC
stages, keeping the step count per command. Experiments C (80 MHz) and D
(75 MHz) measure how far each target is.

## Experiment C: GTE at 80 MHz (2026-10-05)

Revision GNET_F0_CPU50C (`GNET_CPU50C.sdc`): as B, with paths into GTE
registers from clk_2x at 12.5 ns. Build `builds/20261005_0147_cpu50c`,
27,503 ALMs, 89 DSP; check `tools/sta/cpu50x_check.tcl`.

| Path group | Failing endpoints | Worst slack |
|---|---|---|
| CPU side, both directions, 20 ns | 0 | met |
| GTE outputs to the CPU side, 20 ns | 0 | met |
| Into GTE registers (12.5 ns from clk_2x) | 0 | +0.192 ns, MAC1req.mul2 -> gte_mac123 mac_result |
| Full design STA at its normal clocks | 0 | all slacks positive |

Reading: the unmodified GTE reaches 80 MHz with 0.19 ns to spare, so a
50 MHz CPU with a 1.6x GTE clock fits as is, and a 100 MHz GTE (2x) needs
the MAC path shortened by about 3 ns (one fit; seed variation not measured).

## Experiment D: GTE at 75 MHz (2026-10-05)

Revision GNET_F0_CPU50D (into GTE registers from clk_2x at 13.333 ns).
Build `builds/20261005_0228_cpu50d`, 27,498 ALMs, 89 DSP.

| Path group | Failing endpoints | Worst slack |
|---|---|---|
| CPU side, GTE outputs, into GTE (13.333 ns) | 0 | +0.743 ns into the GTE |
| Full design STA, setup | 0 | met |
| Full design STA, hold | clk_1x | -0.073 ns (TNS -2.208 ns) |

Reading: D adds no information over C on the GTE (C already meets 80 MHz).
The clk_1x hold miss is a property of this placement (C and B, with tighter
GTE constraints, had none), the kind of seed-dependent hold problem a
release build has to check for; it is not caused by the GTE target.


The failing group in B is led by gte_mac123 (MAC1/2/3): a 32 x 32 signed
multiply feeding a 45-bit add, -3.01 ns at 10 ns. The request mux in gte.vhd
(state and calcStep selecting the operands, -1.7 ns) is a second, separate
group, and MAC0 and the divider fail by under 1 ns.

Every request gte.vhd makes to gte_mac123 (all 90 distinct operand pairs, extracted
from the source) is one of:
- two operands that fit 18 bits signed: 16-bit matrix, vector and IR
  registers, or an IR times an 8-bit colour;
- a 32-bit operand (MAC registers, mac results, FC, BK, translation) times
  1, 10h, 1000h or 10000h (10000h only with an 8-bit colour).

So the product is either an 18 x 18 multiply or a left shift, with the same
45-bit result and the same cycle count. `GTE_NARROW_MUL` (generic on
psx_top, gte, gte_mac123; macro GNET_GTE_NARROW_MUL; default 0 = upstream)
selects this. Shift results keep numeric_std's resize semantics exactly
(computed at 64 bits, then resized to 45).

Equivalence: `sim/gte_narrow/run.sh` (NVC) drives the upstream and narrow
units with 2,000,000 random requests in those forms, with random add values,
flags and accumulate chains, and compares every output each clock:
0 mismatches. Negative control: with a 32-bit operand times a 16-bit one
(a form gte.vhd never issues) the outputs differ at once, so the check does
see differences.

Experiment E = B's constraints with GNET_GTE_NARROW_MUL (revision
GNET_F0_CPU50E). Build `builds/20261005_0309_cpu50e`, 27,788 ALMs (+284 on
B), 83 DSP (-6).

| Into GTE registers, 10 ns from clk_2x | B (32 x 32) | E (18 x 18 or shift) |
|---|---|---|
| Failing endpoints | 631 | 40 |
| Worst slack | -3.014 ns | -0.837 ns |
| CPU side and GTE outputs | met | met |

Remaining groups in E: MAC1 mac_result from mul1 (22 endpoints, -0.837),
MAC2 mac_result (3, -0.279), MAC1 macResult_1 (2, -0.134) and the request
mux from calcStep (13 endpoints, -0.033 to -0.286). The worst path is
register to DSP input 0.87 ns, 18 x 18 multiply 3.94 ns, product/shift
select 0.9 ns, then the 45-bit add and the output select. Seeds 2 and 3
(GNET_F0_CPU50E2/E3) are queued to separate placement variance from what
needs a further RTL change.

Seed variance of E (same source and constraints, into GTE at 10 ns):

| Seed | Build | Worst slack | Failing endpoints | ALMs |
|---|---|---|---|---|
| 1 | 20261005_0309_cpu50e | -0.837 ns | 40 | 27,788 |
| 2 | 20261005_0510_cpu50e2 | -1.203 ns | 97 | 27,855 |
| 3 | 20261005_0553_cpu50e3 | -1.315 ns | 215 | 27,820 |

Seed 1 was the best of three; placement alone moves the result by about
0.5 ns, so E needs a further 1.3 ns of margin to close reliably.

E4 (GNET_GTE_NARROW_MUL=2, revision GNET_F0_CPU50E4): the add/subtract is
done for the 18 x 18 product and for the shifted operand in parallel and the
result selected after the adders, so the select no longer sits between the
DSP and the carry chain (three more 45-bit adders, same cycles).
Equivalence with the upstream unit: 2,000,000 random requests, 0
mismatches (NARROW_MUL=1 rerun after the change: also 0). Build
`builds/20261005_0429_cpu50e4`: 27,771 ALMs, 83 DSP; into the GTE at 10 ns
31 endpoints fail, worst -0.585 ns (MAC1 mac_result 15 endpoints; MAC2 and
MAC3 now pass; request mux to -0.301; divider -0.079). The worst path is
now register to DSP 0.89 ns, the DSP's 18 x 18 multiply 3.94 ns, then the
adder and output select. This fit also has a clk_1x hold miss of
-0.050 ns (as D). Seed 2 (`builds/20261005_0634_cpu50e4s2`): -0.953 ns,
126 endpoints; seed 3 (`builds/20261005_0714_cpu50e4s3`): -0.788 ns, 84
endpoints. E4 is 0.25 to 0.53 ns better than E seed for seed (seeds 1 to
3: -0.585, -0.953, -0.788 against -0.837, -1.203, -1.315), not enough to
close 100 MHz reliably. C4 (`builds/20261005_0755_cpu50c4`, 80 MHz with
NARROW_MUL=2): worst into the GTE +1.392 ns, no failing paths, all clocks
met (setup and hold), 27,742 ALMs: the ratio route has over 1 ns of margin
with the narrow multipliers. C seed 2 (`builds/20261005_0836_cpu50cs2`,
unmodified GTE at 80 MHz): -0.842 ns into the GTE, so C's +0.192 ns on
seed 1 was a good placement, not margin; the unmodified GTE does not meet
80 MHz reliably. Queued next: C4 (80 MHz with
the narrow multipliers, to measure the margin of the ratio route) and C
seed 2 (whether the unmodified GTE meets 80 MHz on another placement).

Baseline B1 (revision GNET_B1 = GNET_M1_2MB + GNET_GTE_NARROW_MUL=1, normal
clocks, `builds/20261005_0348_b1`): 27,709 ALMs, 245 RAM blocks, 83 DSP,
all clocks met (setup and hold). Against GNET_M1_2MB
(`builds/20261004_2333_m1vram`: 27,486 ALMs, 245 RAM blocks, 89 DSP) the
narrow multipliers cost 223 ALMs and free 6 DSP blocks.

## GTE clock ratio as an alternative (2026-10-05)

Question: with a 50 MHz CPU, can the GTE run at 80 MHz (1.6x, which C and C4
show it meets) instead of 100 MHz (2x), without making GTE command latency in
CPU cycles less faithful? Answer: no, not with gte.vhd as it is. At 2x
PSX_MiSTer reproduces the psx-spx cycle count of every one of the 22
commands exactly; at 1.6x the same step sequences hold the CPU 0% to 24%
longer (19% over the summed counts). 1.6x becomes exact only with a
per-command busy count in CPU cycles (below).

### How the CPU waits (PSX_MiSTer, turbo off)

- A COP2 command in execute in CPU cycle E is registered into
  execute_gte_cmdEna at edge E+1 (rtl/cpu.vhd:1921) and drives gte_cmdEna for
  one CPU cycle from edge E+2 (writeback, cpu.vhd:2456-2458, cleared at
  cpu.vhd:2269-2271).
- The GTE takes it on the next clk2x edge with clk2xIndex = '1'
  (gte.vhd:580-581), which is the mid-cycle clk2x edge (clk2xIndex generator,
  rtl/psx_top.vhd:712-721): 0.5 CPU cycles after edge E+2.
- calcStep counts one per clk2x edge from 0 (gte.vhd:571, 578); the last
  step sets state to IDLE; gte_busy drops on the next IDLE edge that has
  clk2xIndex = '0' (gte.vhd:619-620), i.e. a clk2x edge aligned with a CPU
  edge. B below is the busy time in clk2x periods from the take edge.
- An immediately following MFC2, CFC2, SWC2 or GTE command sees
  execute_gte_cmdEna = '1' or gte_busy = '1' (cpu.vhd:1505-1508, 1516-1519,
  1527-1530, 1695-1697), so its stall starts at edge E+2, and ends at the
  first CPU edge that samples gte_busy = '0' (cpu.vhd:1857-1859; for reads
  the data is taken in that cycle, cpu.vhd:1163-1166, 1850-1854).
- Hold of an immediately following GTE instruction, in CPU cycles:
  0.5 (take) + B/2 (busy) + 1 (CPU samples busy low) = (B + 3) / 2. Each
  instruction placed between the command and the read reduces it by one,
  because busy runs in real time.
- TURBO (gte.vhd turbomode) is TURBO_COMP (psx_top.vhd:2037), on only for
  the "High" turbo menu setting (PSX.sv:908); everything here is turbo off.

### Reference counts

psx-spx, https://psx-spx.consoledev.net/ps1/cpu/gte/geometrytransformationenginegte/
(the old URL .../geometrytransformationenginegte/ redirects there; fetched
once 2026-10-05), "GTE Command Summary (sorted by Real Opcode bits)", Clk
column: RTPS 15, NCLIP 8, OP 6, DPCS 8, INTPL 8, MVMVA 8, NCDS 19, CDP 13,
NCDT 44, NCCS 17, CC 11, NCS 14, NCT 30, SQR 5, DCPL (29h, DPCL in
gte.vhd) 8, DPCT 17, AVSZ3 5,
AVSZ4 6, RTPT 23, GPF 5, GPL 5, NCCT 39. The same page: "The instructions
that hold are MFC2 and CFC2 (on any register, including ones the running
command doesn't use), SWC2, and the next GTE command. MTC2, CTC2 and LWC2
don't wait ... The hold covers only what is left of the command: cycles
spent on other instructions between the command and the read come off it
one for one." It does not say whether the command's own issue cycle is
inside the count; that would be a constant offset for both ratios.
ps1-tests' gte folder (https://github.com/JaCzekanski/ps1-tests) has no timing test (README.md "GTE" section:
gte-fuzz and test-all are value checks; gte/test-all/psx.log: 1150 passed,
0 failed).

### Measurement

`sim/gte_timing/run.sh` (NVC) drives the unmodified gte.vhd: gte_cmdEna for
one CPU cycle from edge P, then counts CPU edges until one samples
gte_busy = '0'. GTE clock 10 ns; CPU 20 ns (2x) or 16 ns (1.6x). At 1.6x
there are 8 GTE edges per 5 CPU cycles, and the psx_top generator (which
assumes exactly two clk2x edges per clk1x cycle) cannot be used, so the
testbench marks the first GTE edge after each CPU edge as clk2xIndex = '1';
each command is issued at all 5 CPU-edge phases. Check: that strobe at 2x
gives the same counts as the psx_top generator for every command and phase.

| Command | Last calcStep (gte.vhd) | B (clk2x) | psx-spx | 2x hold | 1.6x hold (5 phases) | 1.6x mean | 1.6x error | 1.6x turbo steps |
|---|---|---|---|---|---|---|---|---|
| RTPS | 25 (647) | 27 | 15 | 15 | 18..19 | 18.4 | +3.4 (+23%) | 13..14 |
| NCLIP | 11 (729) | 13 | 8 | 8 | 9..10 | 9.6 | +1.6 (+20%) | 6..7 |
| OP | 7 (745) | 9 | 6 | 6 | 6..7 | 6.6 | +0.6 (+10%) | 4..5 |
| DPCS | 10 (777) | 13 | 8 | 8 | 8..9 | 8.6 | +0.6 (+7%) | 7..8 |
| INTPL | 10 (799) | 13 | 8 | 8 | 8..9 | 8.6 | +0.6 (+7%) | 7..8 |
| MVMVA | 10 (871) | 13 | 8 | 8 | 8..9 | 8.6 | +0.6 (+7%) | 6..7 |
| NCDS | 33 (944) | 35 | 19 | 19 | 23..24 | 23.4 | +4.4 (+23%) | 15..16 |
| CDP | 20 (990) | 23 | 13 | 13 | 14..16 | 15.0 | +2.0 (+15%) | 12..13 |
| NCDT | 22+22+40 steps (934-945) | 85 | 44 | 44 | 54..55 | 54.6 | +10.6 (+24%) | 43..44 |
| NCCS | 29 (1054) | 31 | 17 | 17 | 20..21 | 20.6 | +3.6 (+21%) | 13..14 |
| CC | 16 (1091) | 19 | 11 | 11 | 12..13 | 12.6 | +1.6 (+15%) | 9..11 |
| NCS | 22 (1145) | 25 | 14 | 14 | 16..17 | 16.6 | +2.6 (+19%) | 9..11 |
| NCT | 13+13+29 steps (1136-1146) | 57 | 30 | 30 | 36..37 | 36.6 | +6.6 (+22%) | 26..27 |
| SQR | 5 (1157) | 7 | 5 | 5 | 5..6 | 5.6 | +0.6 (+12%) | 3..4 |
| DPCL | 10 (1183) | 13 | 8 | 8 | 8..9 | 8.6 | +0.6 (+7%) | 8..9 (no turbo exit) |
| DPCT | 9+9+11 steps (766-777) | 31 | 17 | 17 | 19..21 | 20.0 | +3.0 (+18%) | 18..19 |
| AVSZ3 | 5 (1194) | 7 | 5 | 5 | 5..6 | 5.6 | +0.6 (+12%) | 5..6 (no turbo exit) |
| AVSZ4 | 7 (1206) | 9 | 6 | 6 | 6..7 | 6.6 | +0.6 (+10%) | 6..7 (no turbo exit) |
| RTPT | 41 (715) | 43 | 23 | 23 | 28..29 | 28.4 | +5.4 (+23%) | 16..17 |
| GPF | 4 (1218) | 7 | 5 | 5 | 4..6 | 5.0 | +0.0 (0%) | 4..6 (no turbo exit) |
| GPL | 5 (1240) | 7 | 5 | 5 | 5..6 | 5.6 | +0.6 (+12%) | 5..6 (no turbo exit) |
| NCCT | 18+18+38 steps (1044-1055) | 75 | 39 | 39 | 48..49 | 48.4 | +9.4 (+24%) | 35..36 |
| Sum | | | 314 | 314 | | 373.6 | +59.6 (+19%) | |

Triple commands loop per vertex by resetting calcStep (DPCT at step 8,
NCDT at 21, NCCT at 17, NCT at 12) and run longer in the last vertex; the
steps column is the clk2x steps per vertex. The 2x column also equals
(B + 3) / 2 from the derivation above, for all 22.

### Reading

- 2x: error 0 cycles on all 22 commands. PSX_MiSTer's step counts are
  matched to the real counts through the 2:1 clock and the clk2xIndex
  handshake.
- 1.6x with gte.vhd unchanged: mean error +2.7 cycles per command, 0% to
  +24%. The commands that dominate 3D code are the worst: RTPT +5.4, NCDT
  +10.6, NCCT +9.4, NCT +6.6 (+22% to +24%), and the result varies by one
  or two cycles with the CPU/GTE phase. Not acceptable as a faithful
  setting. The cost appears only where code reaches a holding instruction
  before the command ends; how often that happens in G-NET games is not
  measured.
- The 1.6x figures are the command-to-command case and a lower bound for
  reads. gte_busy only falls on a clk2xIndex = '0' edge, which at 1.6x is
  always the second GTE edge of a CPU cycle, so no GTE edge is left before
  the CPU edge that releases an MFC2/CFC2/SWC2 to latch gte_readData
  (cpu.vhd:1163-1166). A 1.6x design needs a changed busy-drop rule or one
  more CPU cycle on reads. The CPU/GTE edges at 50 and 80 MHz also come as
  close as 2.5 ns (GTE edge at 37.5 ns, CPU edge at 40 ns; CPU 60 ns, GTE
  62.5 ns), which the probe constraints of B to E (20 ns on the CPU side,
  10 to 13.333 ns into the GTE) do not model.
- Separate from the ratio: PSX_MiSTer holds MTC2, CTC2 and LWC2 while the
  GTE is busy (cpu.vhd:1535-1545, 1673-1676); psx-spx says they do not wait.

### What would make 1.6x exact (not implemented)

Count the hold in CPU cycles instead of GTE steps: a CPU-domain counter
loaded with the psx-spx count when gte_cmdEna is driven, and the CPU's busy
= counter not zero OR the GTE state machine not idle. Then the hold equals
the real count at any GTE clock that finishes the work first, with no phase
variation. The turbo step sequences (the turbo exits in gte.vhd) at 1.6x
already finish within the real count, worst phase, for 16 of 22 commands
(last column). The other six need shorter sequences: DPCL, AVSZ3, AVSZ4,
GPF and GPL have no turbo exit and are 1 cycle over in the worst phase
(their last steps after the final register write have not been checked
for slack); DPCT is 2 over, limited by its 9-step per-vertex loop
(gte.vhd:766-777). The alternative remains 2x (100 MHz), where E4 is
0.59 to 0.95 ns short over three seeds.

## GTE at 100 MHz with unchanged results and counts: GTE_NARROW_MUL = 3 (2026-10-05)

Target: the GTE at 101.6064 MHz (9.842 ns), 2x a 50.8032 MHz CPU
(r1_cpu_domain_design.md, option d1), with every result and every step
count unchanged. E4 was 0.59 to 0.95 ns short at 10 ns over three seeds,
so 0.74 to 1.11 ns at 9.842 ns. Its failing groups: the MAC path (MACreq
register, 0.89 ns route, 3.94 ns DSP multiply, adder, output select), the
request mux (calcStep and state to MACreq, to -0.95 ns in seed 2), the step
decode (calcStep to state, to -0.25 ns in seed 2) and the divider's last
stage (-0.08 ns).

What I changed, as value 3 of the existing generic (macro
GNET_GTE_NARROW_MUL=3; values 0, 1 and 2 unchanged):

1. Requests decoded one step early (gte.vhd). A function req3At gives, for
   a state and step, the MAC requests of the upstream case statement as
   one-hot operand selects and flags, plus the step's exit and loop flags.
   The process registers req3At of the next state and step, so each step's
   selects come from a register. The next state and step are formed from
   these registered exit and loop flags instead of calcStep compares
   (overriding the case statement outside IDLE). Upstream's MACreq
   assignments stay in the file and are unused in this mode.
2. Products registered in the request cycle (gte.vhd, gte_mac123.vhd,
   gte_mac0.vhd). In the cycle that writes a request, the selected 16-bit
   (or 8-bit colour) operands go through an AND-OR mux straight into the
   18 x 18 multiplier, whose output is registered in the MAC unit (DSP
   output register); a wide operand times 1, 10h, 1000h or 10000h is
   shifted and registered instead, so shift against multiply is decided
   when the request is written. The trigger cycle then selects the
   product, takes the sign by inverting one input (a - p = a + not p + 1,
   p - a = p + not a + 1) and does one 45-bit add. This replaces the
   doc's dedicated DSP input registers: the request register no longer
   sits between the mux and the DSP. MAC0 (17 x 18) works the same way.
3. Divider (gte_UNRDivide.vhd, generic RETIME = 1 for this mode): same
   7-clock latency, stages 0 and 1 (leading zeros, shift) merged, and the
   32 x 20 product registered before the rounding add, overflow check and
   result select.

The state machine runs the same steps; only the work inside them moved.

Equivalence (NVC):

| Check | Size | Result |
|---|---|---|
| sim/gte_equiv (new): two full gte instances, NARROW_MUL 0 and 3, same random inputs, outputs and 164 internal signals (all GTE registers, step state, MAC and divider outputs) compared every clk2x cycle | 4 seeds x 25,000,000 clk2x cycles: 3,480,346 commands taken (each of the 22 at least 67,572 times with turbo off and 86,434 with turbo on, plus 68,211 unknown opcodes), register writes and reads also during commands, 699,893 ce-low events, 16,784 resets, 12,168 savestate loads | 0 mismatches |
| Sim-only assertion in gte.vhd: req3 equals req3At of the current state and step | same runs | never fired |
| Negative controls: 11 one-line mutations of the new logic (run.sh MUT=1..11: wrong flag, operand, shift amount, loop step, carry in, rounding constant, product not held while ce = 0) with the assertion off | 1 run each | all caught, first mismatch after 32 to 19,791 cycles |
| NARROW_MUL 0 of the changed RTL against the unmodified base RTL (a83879f) | 5,000,000 cycles | 0 mismatches |
| NARROW_MUL 1 and 2 against 0 in the same full-GTE bench | 5,000,000 cycles each | 0 mismatches |
| sim/gte_narrow (tb_mac_narrow, extended for the new MACmul port, with requests held as while ce = 0), NM = 3, 1, 2 | 2,000,000 requests each | 0 mismatches; control (wrong shift for the 10h form) caught at request 2 |
| sim/gte_timing at 2x, NARROW_MUL 3 | 22 commands x 5 phases, turbo off and on | identical to upstream: all 22 equal the psx-spx counts (sum 314) |

Expected timing (my estimates from E4's path delays, not a fit): request
cycle about 7 to 7.5 ns (select register, two LUT levels, 0.9 ns route,
3.94 ns multiply into the DSP output register); trigger cycle about 5.5 to
6 ns (E4's part after the DSP was 5.4 ns); step decode and request selects
two or three LUT levels from registers; divider about 6 to 7 ns (two DSPs
and their adder) then 3 to 4 ns. The known groups should then have 2 ns or
more at 9.842 ns. Paths outside them are unmeasured; the closest known one
is gte_busy through cpu.vhd's combinational gte_readEna to gte_readData
(-0.020 ns at 10 ns in E4 seed 1, about -0.18 ns at 9.842 ns), which I did
not change because the enable is formed in cpu.vhd. Area: the multipliers
keep their sizes, so I expect E4's 83 DSP blocks; ALMs within a few hundred
of E4's 27,771 (E4's parallel adders go, about 100 select and flag
registers, the shifted-operand and product registers and the early decode
come in). Both need the fit.

Revision GNET_F0_CPU50E5 = E4 with GNET_GTE_NARROW_MUL=3, target cpu50e5 in
tools/pc_build.sh. It keeps E4's SDC (10 ns into the GTE), so the slack at
9.842 ns is the reported slack minus 0.158 ns.

E5 seed 1 (`builds/20261005_0957_cpu50e5`): 26,805 ALMs, 83 DSP; into the
GTE at 10 ns 93 endpoints fail, worst -1.283 ns. The MAC and divider groups
are gone (prod0 and prodN3 are packed into the DSP output registers). All
failing paths come from my early decode: req3At wrote the RTPT rows as
r3RT(r, (s mod 3) + 1, s / 3), which Quartus built as an lpm_divide on the
step number, and register retiming then moved the req3 registers back into
it (state.IDLE to req3.bV2X -1.283 ns, v3_step to the divider -0.599 ns,
retimed req3.bV2Y to prodN3 -0.186 ns). A pll_hdmi setup miss of -0.085 ns
also appeared.

E6 (revision GNET_F0_CPU50E6, target cpu50e6, same macro value 3): every
row call in req3At now has constant arguments (no division or mod), and the
first step of a new command is decoded from gte_cmdData separately from the
next step of the running command, so state = IDLE only selects between the
two decodes. Rerun after the change: sim/gte_equiv 4 x 25,000,000 cycles
(same stimulus as above) 0 mismatches, NARROW_MUL 0 against the base RTL
5,000,000 cycles 0 mismatches, all 11 mutations caught (32 to 19,791
cycles), sim/gte_timing at 2x identical to upstream with turbo off and on.

## B1 seeds and a hold miss (2026-10-05)

B1 seed 2 (`builds/20261005_0918_b1s2`, normal clocks): 27,744 ALMs, 83 DSP,
setup met, one hold miss on clk_2x: -1.140 ns slow model, -0.497 ns fast
model (`tools/sta/hold_query.tcl`, hold_*_summary.rpt in that folder). The
path is gpu vramRange[10] (clk_1x) to gpu_videoout DisplayOffsetY[0]
(clk_2x, gpu_videoout.vhd:245): 0.36 ns of data path inside one LAB
against 1.4 ns of clock skew between the two global clocks. The structure
is upstream's (only its width changed for VRAM_Y_BITS), so this is a
placement-dependent hold risk of the base design, not of the G-NET
changes. The next worst hold path is +0.116 ns (SPU voice MLAB). Release
builds must check hold on every fit; a fix if it recurs: register
vramRange into the clk_2x domain once (it changes at most once a frame),
or let the fitter's hold fixing see it with a multicycle-hold of 0 (needs
review).

## Experiments E5 and E6: GTE_NARROW_MUL = 3 (2026-10-05)

Branch gte-mac-100 (worktree, not merged): requests decoded one step early,
products registered in the request cycle (packed into the DSP output
registers), divider retimed; results and cycle counts unchanged (full-GTE
equivalence 4 x 25 M clk2x cycles, 0 mismatches; gte_timing at 2x equal to
psx-spx for all 22 commands). Into GTE registers at 10 ns:

| Build | Worst slack | Failing endpoints | ALMs | DSP |
|---|---|---|---|---|
| E5 seed 1 (`20261005_0957_cpu50e5`) | -1.283 ns | 93 | 26,805 | 83 |
| E5 seed 2 (`20261005_1038_cpu50e5s2`) | -1.235 ns | 130 | 26,900 | 83 |
| E6 seed 1 (`20261005_1133_cpu50e6`) | **+1.536 ns** | **0** | 26,802 | 83 |

E5 failed in its own new decode: a `mod 3` and `/ 3` on the step number
became an inferred divider that register retiming pulled into the request
path. E6 writes those rows with constant arguments and decodes the first
step of a new command separately from the running one. E6 meets 10 ns
(100 MHz, the GTE clock for a 50.000 MHz CPU) with 1.5 ns to spare, and
CPU-side and GTE-output paths also pass. This fit has one clk_1x hold miss
of -0.082 ns (placement, as D, E4 and B1 seed 2). Seed 2
(`20261005_1226_cpu50e6s2`): +1.792 ns, 0 failing endpoints, 26,786 ALMs,
and no negative slack anywhere (setup or hold). Seed 3 queued.
