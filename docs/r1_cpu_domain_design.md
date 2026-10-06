# R1: CPU clock domain at the ZN-2 rate (design study)

2026-10-05. Design study only: no RTL, SDC or PLL file changed, no fit run.
Question: how to run the CPU side of the PSX_MiSTer base at the inferred
ZN-2 rate (about 50 MHz, PLAN.md R1) while the parts of the board that run
on other crystals keep their rates. Inputs: docs/r1_speed_study.md,
docs/cpu_rate_probe.md (all experiments, including the GTE clock ratio
section), the RTL in rtl/ and PSX.sv, and MAME 0.288 sources
(docs/mame_sources.md, plus rcnt.cpp, dma.cpp and sio.cpp from a local
mame0288 clone, tag commit 27a8d9e8, whose psx.cpp has the same md5 as
the one listed there, e7f365b7...).

## Summary

- Today every PSX block runs every clk_1x cycle (33.8688 MHz). `ce` is a
  run/pause enable, not a rate divider. clk_2x and clk_3x are exact
  multiples from the same PLL, and several blocks rely on that through the
  clk2xIndex and clk3xIndex phase strobes (section 1).
- On the ZN-2 the CPU (CXD8661R, 100 MHz crystal), the GPU (53.693 MHz) and
  the SPU (67.73 MHz crystal, 33.8688 MHz in MAME) are separate chips on
  separate crystals (section 2). The parts that belong with the CPU are the
  ones inside the CXD8661R: CPU, GTE, DMA, root counters, IRQ, SIO, memory
  control. GPU and SPU keep their PS1 rates.
- Recommendation (section 4): a CPU domain made of a CPU clock and an exact
  2x clock, holding cpu, gte, memorymux, memctrl, dma, timer, irq, the
  SDRAM controller and the new G-NET bus glue. GPU, SPU, DDR3 and the
  framework stay on clk_1x/clk_2x/clk_vid. Crossings use small
  handshake/FIFO entities that are safe for asynchronous clocks. Bring-up
  at 50.8032 MHz / 101.6064 MHz (3/2 of clk_1x, the existing clk_3x as the
  2x clock, one PLL, deterministic and fully timed by STA), then a switch
  to exactly 50.000 / 100.000 MHz is a PLL and SDC change if Lee wants the
  last 1.6%. The GTE stays at 2x the CPU clock with unchanged step
  sequences, so its per-command hold stays exact; closing 10 ns needs MAC
  path work in gte_mac123/gte.vhd (option d1). The busy counter (d2) is the
  fallback.
- Superseded 2026-10-05 (my decision, section 5 item 1): there is no
  50.8032 MHz bring-up. The CPU domain runs at exactly 50.000 / 100.000 MHz
  from its own PLL from the start. The current plan is the section "Plan
  for exactly 50.000 MHz (2026-10-05)" after section 6. The (b) partition
  and the GTE at 2x stay.

## 1. Clocks in PSX_MiSTer today

### 1.1 Sources

| Clock | Frequency | Source | Notes |
|---|---|---|---|
| clk_1x | 33.8688 MHz | `pll` outclk_0 (PSX.sv:68-76; rtl/pll/pll_0002.v:28) | System and CPU clock |
| clk_2x | 67.7376 MHz | `pll` outclk_1 (pll_0002.v:31) | Same PLL, phase 0 (pll_0002.v:32) |
| clk_3x | 101.6064 MHz | `pll` outclk_2 (pll_0002.v:34) | Same PLL, phase 0 (pll_0002.v:35); SDRAM clock |
| clk_vid | 53.693175 MHz | `pll_vid_fixed` in G-NET builds (PSX.sv:79-87; rtl/gnet/pll_vid_fixed.v:32); upstream `pll2` with runtime reconfiguration (PSX.sv:88-125; rtl/pll2/pll2_0002.v:30) | Asynchronous to the others: false paths in PSX.sdc:6-16 and GNET_LEAN.sdc:4-15 |
| DDRAM_CLK | = clk_2x | PSX.sv:1430 | DDR3 bridge (rtl/ddram.sv:107) |

The `pll` is a fractional PLL from the 50 MHz board clock
(pll_0002.v:24-27). Its VCO frequency is not in the source; the fit
report's PLL summary would give it (needs-review, relevant to option c2).

### 1.2 `ce` and the phase strobes

- `ce` (psx_top.vhd:762-818) is '1' on every clk_1x cycle while the system
  runs and '0' during reset or pause. It is distributed to every block
  (port maps at psx_top.vhd:982, 1243, 1287, 1400, 1528, 1709, 1799, 1954,
  2033). It is not a rate enable: no block in the design runs at a fraction
  of its clock today.
- clk2xIndex (psx_top.vhd:705-721): clk1xToggle flips on every clk_1x edge;
  on clk_2x the index is '1' on the clk_2x edge in the middle of a clk_1x
  cycle and '0' on the edge that coincides with a clk_1x edge
  (cpu_rate_probe.md "How the CPU waits"). This needs exactly two clk_2x
  edges per clk_1x cycle, phase-aligned.
- clk3xIndex (psx_top.vhd:723-734, used by dma) and a second copy inside
  the SDRAM controller (sdram.sv:232-235): '1' on one clk_3x edge per clk_1x
  cycle. My derivation from that code: with three fast edges per slow cycle
  the compare `clk1xToggle3X_1 == clk1xToggle` is true on the last fast
  cycle before the next slow edge; with two fast edges per slow cycle it is
  never true, so SDRAM requests would never be captured. The controller
  therefore needs a 3:1 ratio as written (needs-review: confirm in
  simulation before any ratio change).

### 1.3 Block by block (G-NET LEAN configuration)

| Block | clk_1x | clk_2x | clk_3x | clk_vid | Fixed-ratio assumption | Source |
|---|---|---|---|---|---|---|
| CPU | pipeline (9 processes), tag RAM, icache read port | scratchpad read port (mid-cycle read) | icache fill port, written by the SDRAM controller | | Scratchpad: address from clk_1x registers, read on the mid-cycle clk_2x edge, data used at the next clk_1x edge | cpu.vhd:605, 620-636 (clock_a clk3x at 626), 2039-2055 (clock_b clk2x at 2052) |
| CPU data cache | write port | read port | | | Turbo only (TURBO_CACHE, cpu.vhd:2220, 2374), fixed to 0 in G-NET builds (PSX.sv:919, 993-994), so pruned | datacache.vhd:73-95 |
| GTE | SS/idle only | command state machine, MAC0/MAC123, divider | | | Command taken on clk2xIndex = '1', busy dropped on clk2xIndex = '0', read data latched on the mid-cycle edge; per-command hold exact only at 2x | gte.vhd:281, 395-451, 580-581, 619-620, 1534; cpu.vhd:1163-1166, 1850-1858; cpu_rate_probe.md table |
| DMA | all logic | | output FIFO to SDRAM | | FIFO write strobe gated by clk3xIndex | dma.vhd:957-979 |
| memorymux | all logic | port present, unused | | | RAM/BIOS waits in CPU cycles | memorymux.vhd:11, 488-830 |
| memctrl | all logic | | | | Delay registers in CPU cycles | memctrl.vhd:58-82 |
| SDRAM controller | front end (`clk_base`: ready pulses, DMA word unpacking, refresh idle flag) | | command engine | | 3:1 index (1.2); refresh constants for 100 MHz | sdram.sv:25, 101-102, 151-196, 232-260; PSX.sv:1307-1310 |
| DDR3 arbiter and bridge | | all logic | | | VRAM and SPU RAM bandwidth in clk_2x cycles | psx_top.vhd:865-976; PSX.sv:1430 |
| GPU | register/bus side, GPUSTAT | command FIFO write, all drawing, VRAM access | | via videoout | GP0 writes and DMA words enter the FIFO on clk2xIndex = '1'; FIFO read gated by clk2xIndex = '0' only with REPRODUCIBLEGPUTIMING; GPUREAD FIFO read on clk2xIndex = '0' | gpu.vhd:556, 828-850, 869, 929, 1131-1133, 1540, 1637 |
| Video out (async, used in G-NET) | reports in (3 FF) | requests out (3 FF) | | timing generator | None: real CDC | gpu_videoout_async.vhd:169-230, 611-669; syncVideoOut = 0 (PSX.sv:90) |
| SPU | all voice/reverb processing | SPU RAM interface | | | Sample period = 768 clk_1x cycles; SPU RAM requests on clk2xIndex = '1' | spu.vhd:812, 1458-1461; spu_ram.vhd:245, 378-387, 466 |
| Timers | all logic | | | | sysclk = one tick per clk_1x | timer.vhd:97, 148-185 |
| IRQ, SIO, EXP2 | all logic | | | | | irq.vhd, sio.vhd, exp2.vhd (clk_1x only) |
| MDEC | | | | | Removed (HAS_MDEC = 0, R18) | psx_top.vhd:1660-1701 |
| CD, pads, memory cards, cheats, savestates | | | | | Removed in LEAN (GNET_HAS_* = 0, PSX.sv:927-944) | psx_top.vhd:1053-1206, 1434-1516, 2071-2167 |
| Framework glue (hps_io, downloads) | yes | | | | | PSX.sv:413, 488, 497-559 |

### 1.4 Real-time behaviour derived from clock counts

- **Timers:** sysclk mode counts one per clk_1x cycle and timer 2's /8 mode
  uses a 3-bit subcounter (timer.vhd:149, 176-180), so the counters run at
  33.8688 MHz real time. Dot clock, hblank and vblank come from the video
  timing generator on clk_vid through three flip-flops into clk_1x
  (gpu_videoout_async.vhd:203-211, 246; timer.vhd:151-170).
  Side note (needs-review): the dot clock signal is a one-cycle clk_vid
  pulse (gpu_videoout_async.vhd:613, 669; 18.6 ns), shorter than a clk_1x
  period (29.5 ns), so timer 0 in dot-clock mode can miss pulses in the
  asynchronous video mode. This is upstream behaviour and does not depend
  on the CPU rate, but a faster sampling clock changes how many are missed.
- **SPU:** 768 clk_1x cycles per sample (spu.vhd:1458-1461), i.e.
  33.8688 MHz / 768 = 44.1 kHz. The SPU also has 768 cycles of processing
  budget per sample for 24 voices and reverb.
- **GPU:** drawing runs on clk_2x and VRAM traffic goes through the DDR3
  arbiter on clk_2x (1.3), so drawing time is clk_2x real time. Display
  timing is clk_vid (docs/m1_gpu_zn2.md, video timing table).
- **Memory:** memorymux waits are in CPU cycles (RAM page miss 3, BIOS
  25/26 per fetch, BIOS data 1/9/25 by size: memorymux.vhd:579-668; the
  external bus, which carries the G-NET flash at 0x1f000000-0x1f7fffff,
  uses the memctrl delay registers: memorymux.vhd:691-697, 1031-1260,
  memctrl.vhd:73-82). The SDRAM part of every RAM access is in clk_3x
  cycles. A RAM access in CPU cycles is therefore part CPU-counted and part
  real time at 101.6064 MHz.
- **CD:** removed; its timing constants are 33.8688 MHz counts
  (cd_top.vhd:84-88, 1840, 2175, 2310).

## 2. What the ZN-2 clocks

### 2.1 MAME 0.288

| Part | MAME | Source |
|---|---|---|
| CPU CXD8661R | XTAL 100 MHz, executes clock/4 = 25 M cycles/s | [MAME 0.288 zn.cpp:91](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/zn.cpp#L91); psx.h:181-182 |
| GPU CXD8654Q | 53.693175 MHz | zn.cpp:94 |
| SPU | 67.7376 MHz / 2 = 33.8688 MHz | zn.cpp:95 |
| SPU sample rate | clock / 768, stream at 44,100 Hz | spu.cpp:961, 1094-1097 |
| Board crystals | 67.73 MHz, 53.693 MHz, 100 MHz | taitogn.cpp:44, 51 |
| Video | 59.8260 Hz, 15.4333 kHz (note) | taitogn.cpp:83; analysed in docs/m1_gpu_zn2.md |
| Root counters | value read back from CPU total cycles x 2 (50 M/s on ZN-2), but target IRQs scheduled at a fixed 33,868,800 Hz with "TODO: figure out if this should be calculated from the cpu clock for 50mhz boards?" | mame-src-0288 src/devices/cpu/psx/rcnt.cpp:129-133, 220-222 |
| DMA, SIO | fixed 33,868,800 Hz time base | dma.cpp:69; sio.cpp:107 (SIO0 is declared with DERIVED_CLOCK(1, 2) of the CPU, psx.cpp:3461, but sio.cpp ignores it) |
| Integrated devices | irq, dma, mdec, rcnt, sio0/1 are subdevices of the CPU device | psx.cpp:3446-3461 |
| CPU/SPU TODO | "is this a work around for mismatched CPU & SPU clock?": reads of 0x1fa51c00-0x1fa51dff return nothing, 0x1fa60000 toggles bit 3 on every read | zn.cpp:170-172, 233-243 |

The 0x1fa51c00-0x1fa51dff window has the same low bits as the PS1 SPU
registers (0x1f801c00-0x1f801dff, memorymux.vhd:684). That suggests a
second, board-level path to the SPU with a ready flag at 0x1fa60000 (the
EPM7064 CPLD sits next to the 67.73 MHz crystal in the layout,
taitogn.cpp:42-44), but this is my inference (needs-review, R2). The games
do write the SPU at the PS1 address in MAME: SPU key-on taps at
0x1f801d88-8b fired in all six games (docs/r18_mdec_spu.md:9-11, 32-37).

### 2.2 Which parts move with the CPU

| Part | On the ZN-2 | Core rate | Basis |
|---|---|---|---|
| CPU, GTE | CXD8661R, 50 MHz (inferred) | CPU domain | PLAN.md R1; the real GTE runs on the CPU clock with fixed counts (cpu_rate_probe.md) |
| DMA, IRQ, memory control/BIU | inside CXD8661R | CPU domain | MAME models them as CPU subdevices (psx.cpp:3446-3461) |
| Root counters | inside CXD8661R; MAME is inconsistent (reads at 50 M/s, IRQs at 33.8688 MHz) | CPU domain by default, with a generic to tick at 33.8688 MHz equivalents | needs-review: settle with the R1 rank-1 test program (counter 2 against VBlank) |
| SIO0 (CAT702, znmcu) | inside CXD8661R; MAME times it at 33.8688 MHz | CPU domain, baud base a parameter | needs-review; only affects protection/MCU transfer timing |
| GPU | CXD8654Q on its own 53.693 MHz crystal | unchanged: drawing on clk_2x, video on clk_vid | taitogn.cpp:51; zn.cpp:94 |
| SPU | CXD2925Q, 33.8688 MHz from the 67.73 MHz crystal | unchanged on clk_1x: 768 cycles per sample stays exact | zn.cpp:95; PLAN.md R2, R24 |
| Zoom board | own 25 MHz crystal | own domain (already separate in the FX-1B reference) | PLAN.md 3.4 |
| G-NET glue (flash bank, RF5C296, ATA, control registers) | on the CPU's external bus | CPU domain (new code, written for it) | PLAN.md 3.2 |
| SDRAM controller | implementation detail | CPU domain, clocked at 2x the CPU clock | 1.2 (needs an integer ratio to the request side) |

## 3. Design options

Existing timing evidence (docs/cpu_rate_probe.md), all on the LEAN base:

| Experiment | Constraint | Result |
|---|---|---|
| Probe (unconstrained fit) | 20 ns CPU side | 418 endpoints fail, worst -2.99 ns (jump target to memorymux) |
| GNET_F0_CPU50 | 20 ns cpu to cpu and cpu to memorymux | all met, worst +1.959 ns, +76 ALMs |
| B | 20 ns among cpu, dma, memorymux, memctrl both ways; 10 ns into the GTE from clk_2x | CPU side met; GTE 631 endpoints, -3.014 ns (32 x 32 MAC) |
| C / D | GTE at 12.5 ns / 13.333 ns | C +0.192 ns; D +0.743 ns but clk_1x hold -0.073 ns |
| E, E2, E3 (NARROW_MUL = 1) | GTE at 10 ns | -0.837, -1.203, -1.315 ns |
| E4, seeds 1 to 3 (NARROW_MUL = 2) | GTE at 10 ns | -0.585, -0.953, -0.788 ns; worst path: register to DSP 0.89 ns, 18 x 18 multiply 3.94 ns, adder, output select; request mux to -0.301 ns, divider -0.079 ns; seed 1 clk_1x hold -0.050 ns |
| C4 (NARROW_MUL = 2) | GTE at 12.5 ns | +1.392 ns, all clocks met |
| Peip-style 2x CPU | 14.76 ns CPU side | 1,446 endpoints, worst -8.23 ns |

GTE ratio (cpu_rate_probe.md, "GTE clock ratio"): at 2x the hold of all 22
commands equals the psx-spx count; at 1.6x with gte.vhd unchanged the hold
is 0% to 24% longer (+19% summed), phase-dependent, and MFC2/CFC2/SWC2 can
read stale data because no GTE edge falls between busy low and the CPU
edge that latches gte_readData.

Area context: projected total 34,534 to 36,684 ALMs of 41,910 (82.4 to
87.5%, docs/f0_budget.md:236-247). Every ALM figure below marked
"estimate" is mine, not measured.

### (a) Move the whole clk_1x/clk_2x pair to 50/100 MHz

Everything on clk_1x and clk_2x moves; SPU sample tick and (if wanted)
timers are re-derived from a fixed clock or a fractional strobe
(50 MHz / 44.1 kHz = 1133.79 cycles, so a phase accumulator).

- Pros: no new clock domain for the CPU side; every existing 2:1 handshake
  stays valid; smallest change inside cpu, gte, memorymux, dma.
- Cons:
  - GPU drawing and DDR3 VRAM traffic are clk_2x real time (1.4), so the
    GPU would draw about 1.48x faster. That breaks exactly the GPU-bound
    slowdown R23 needs (Ray Crisis demo 1, docs/r1_speed_study.md). The GPU
    drawing side would have to move to its own clock, which is option (b)
    for the GPU anyway.
  - clk_3x would become 150 MHz; sdram.sv is set up for 100 MHz (CAS
    latency 2 "for < 100MHz", refresh constants, sdram.sv:96-102), so the
    SDRAM must drop to 2x and its 3:1 index must be redesigned (1.2).
  - The SPU (4,345 ALMs) and its SPU RAM path would have to close 20/10 ns
    instead of 29.5/14.8 ns: not measured.
  - The SPU's bus and DMA timing would run at 50 MHz while the real SPU is
    a 33.8688 MHz chip.
- Risk: high (timing of every clk_2x block at 100 MHz, GPU split needed
  regardless).
- Estimate: +400 to +900 ALMs (GPU split crossings, fractional SPU strobe,
  SDRAM front end); GTE -0.59 to -1.32 ns at 10 ns (E, E4).

### (b) Separate CPU clock domain with CDC to the rest

A CPU clock and an exact 2x clock (one PLL, phase-aligned) for the
CXD8661R blocks (2.2); GPU, SPU, DDR3 and framework unchanged.

- Crossings to build (psx_top.vhd port maps and signals):
  - memorymux bus to GPU (bus_gpu_*, with the existing bus_gpu_stall wait,
    memorymux.vhd:120, 424, 801-802);
  - DMA to GPU: write stream, GPUREAD stream, gpu_dmaRequest,
    DMA_GPU_waiting (psx_top.vhd:500-505, 1323-1328);
  - memorymux to SPU on the external bus path (memorymux.vhd:684-690),
    DMA to SPU (16-bit, psx_top.vhd:517-521);
  - IRQs from GPU and SPU; hblank, vblank, dot clock into the timers
    (already synchronised from clk_vid, so they only change destination);
  - ce/pause and reset (psx_top.vhd:695-700, 762-818);
  - SDRAM channel 3 (HPS downloads, PSX.sv:1339-1345) from clk_1x;
  - G-NET card engine to the DDR3 arbiter (if the card image is in DDR3,
    PLAN.md 3.3), or the card engine on clk_2x with only its registers
    crossing.
- Main RAM needs no crossing: the SDRAM controller moves into the CPU
  domain at 2x the CPU clock (100 MHz is the rate sdram.sv was written
  for, sdram.sv:101-102), with its index generator rewritten for 2:1. RAM
  latency in CPU cycles changes (3 SDRAM cycles per CPU cycle become 2) and
  must be measured and then calibrated (section 4, step 0.3).
- Pros: matches the board's partition (separate chips on separate
  crystals); GPU and SPU untouched, so their verified PS1 behaviour and the
  GPU drawing time stay as they are; exact 50.000 MHz possible.
- Cons: at exactly 50.000 MHz the CPU domain is asynchronous to clk_1x
  (33.8688 / 50 = 10584 / 15625 in lowest terms, so no common VCO), which
  makes the timing of every crossing vary from run to run and makes
  simulation against a reference trace harder. Each crossing adds
  synchroniser latency (2 to 3 cycles per direction) to GPU and SPU
  register accesses; the real chip-to-chip latency is unknown
  (needs-review, calibration item).
- Risk: medium (CDC correctness, verification effort). Timing: CPU side
  closes 20 ns (CPU50, B); GTE as (d); crossing paths are false or max-delay
  paths.
- Estimate: +350 to +800 ALMs for the crossings (two or three asynchronous
  FIFOs for GP0/DMA and GPUREAD, request/acknowledge handshakes for
  register access, pulse synchronisers), one more PLL (PLL count on the
  5CSEBA6 and current use: needs-review from the fit report).

### (c) Keep 33.8688/67.7376 MHz and derive the CPU rate from a higher base

- (c1) CPU on clk_3x (101.6064 MHz) with a clock enable every second
  cycle (50.8032 MHz) and the GTE free-running on clk_3x. Every CPU-side
  register would have to be enabled by the new ce and every path between
  enabled registers declared multicycle 2. `ce` already gates most state
  (memorymux.vhd:520, timer.vhd:148), but not single-cycle strobes such as
  ram_ena (memorymux.vhd:493) or the RAM blocks' clock enables, so this
  needs a full audit, and a missed path is either a timing failure or a
  silent double strobe. Risk high; rejected in favour of (c2).
- (c2) A fourth output of the existing PLL at 50.8032 MHz (3/2 of clk_1x,
  19.684 ns) as the CPU clock, and clk_3x (101.6064 MHz, exactly 2x) as
  its 2x clock. All clocks then come from one VCO (if the VCO is a multiple
  of 101.6064 MHz, as it must be for the current three outputs; e.g.
  609.6384 MHz gives /18, /9, /6 and /12; needs-review against the fit
  report). Crossings between the CPU clock and clk_1x repeat every 3 CPU
  cycles = 2 clk_1x cycles; the closest edges are 9.84 ns apart (one clk_3x
  period), so STA times every crossing and the system is deterministic.
  - Pros: deterministic, simulates like today, every crossing timed; uses
    clk_3x for GTE and SDRAM, no new PLL.
  - Cons: the CPU runs 1.6% above 50.000 MHz. The GTE needs 9.842 ns, 0.16
    ns harder than B to E4 (E4 seeds would be -0.74 to -1.11 ns).
  - Risk: medium-low. Estimate: same crossing logic as (b), +350 to +800
    ALMs if written async-safe (recommended), less if written as
    phase-indexed handshakes like clk2xIndex.
  - Superseded 2026-10-05: (c2) is no longer used, not even for bring-up
    (exact 50.000 MHz decided). The VCO question is answered by the B1 fit
    report: 406.425598 MHz, C 12/6/4 (see the 50.000 MHz plan, P1).
- (c3) Peip-style: CPU on clk_2x (67.7376 MHz) with a 50/67.7 enable.
  Rejected on measurement: 1,446 endpoints fail by up to 8.23 ns
  (cpu_rate_probe.md Result).

### (d) The GTE

**(d1) Keep the GTE at exactly 2x the CPU clock and shorten the MAC path
by about 1.3 ns without changing any step.** The E4 worst path is
register to DSP 0.89 ns, multiply 3.94 ns, then adder and output select
(cpu_rate_probe.md, E4). Changes that keep the cycle count (each is my
proposal; the gain per item is an estimate, needs-review until a fit):

1. DSP input registers. MAC1req/MAC2req/MAC3req.mul1 and mul2 are 32-bit
   fields of one request record (gte.vhd:623-626 onwards) and in gte_mac123 also feed
   the shift path and the mul2 constant compare (gte_mac123.vhd:99-113), so
   Quartus cannot pack them into the DSP's input registers. Add duplicate
   18-bit operand registers written in the same clk2x assignments
   (mul1n, mul2n) that feed only the multiplier. Removes the 0.89 ns route
   and lets the DSP use its registered-input mode (estimate 0.5 to 1.0 ns;
   whether the Cyclone V DSP absorbs them this way: needs-review).
2. Operand pre-selection. Decide shift against multiply and the shift
   amount when the request is written, from the request table (the 90
   operand pairs are fixed per step, cpu_rate_probe.md E), and store a
   2-bit code, so no 32-bit compare of mul2 sits in front of the final
   select (estimate 0.2 to 0.4 ns).
3. Sign pre-selection. addsub (gte_mac123.vhd:62-71) picks a + p, a - p or
   p - a after the product. Negating an operand at request time (the
   product of an 18-bit and a negated 18-bit operand needs 19 bits signed,
   needs-review against the DSP modes) or pre-negating the add value
   leaves one adder after the DSP (estimate 0.2 to 0.4 ns).
4. Lookahead request decode for the separate request-mux group (-0.03 to
   -0.30 ns): calcStep advances by one per clk2x edge (gte.vhd:571), so the
   decode of (state, calcStep + 1) can be registered one step early.

Verification needs no new method: the existing random equivalence bench
(sim/gte_narrow, 2,000,000 requests, compares every output per clock) and
the per-command hold bench (sim/gte_timing, 22 commands at 2x) must give 0
mismatches and unchanged counts. Estimate +100 to +300 ALMs (duplicate
registers for three MAC units plus MAC0, decode registers). Risk: medium
(the gain is unproven; seed spread is 0.37 ns in E4).

**(d2) CPU-domain busy counter.** On gte_cmdEna, load a counter with the
psx-spx count for the command; the CPU's busy is counter not zero OR the
GTE not idle (cpu_rate_probe.md, "What would make 1.6x exact"). Then the
hold is exact at any GTE clock that finishes in time.

- Needs: the read-latch fix (gte_readData is latched on the mid-cycle
  clk2x edge, gte.vhd:395-451, cpu.vhd:1163-1166, which does not exist at
  a non-2x ratio; for example read the GTE registers through a mux
  registered on the CPU clock, with the counter guaranteeing they are
  stable, plus the matching timing exception); the turbo step sequences
  (gte.vhd:646, 714, 728, 744, 768, 798, 870, 936, 989, 1046, 1090, 1138,
  1156) checked for identical results (needs-review: run the ps1-tests
  gte value tests with turbo on); shorter sequences for DPCL, AVSZ3,
  AVSZ4, GPF, GPL (+1 cycle at 1.6x) and DPCT (+2).
- Pros: GTE can run at 80 MHz, where C4 has +1.392 ns; the counter could
  also implement psx-spx's rule that MTC2, CTC2 and LWC2 do not wait
  (PSX_MiSTer holds them, cpu.vhd:1535-1545, 1673-1676).
- Cons: changes GTE control behaviour (needs value and count
  verification, not just equivalence); 80 MHz is not an integer multiple of
  50 MHz (8:5, edges as close as 2.5 ns, cpu_rate_probe.md); with the
  50.8032 MHz PLL (c2) the available GTE clocks are 76.2048 MHz (1.5x) or
  87.09 MHz (VCO/7), neither measured.
- Estimate: +50 to +150 ALMs (counter, 22-entry count table, read path).
  Risk: medium.

### Summary

| Option | Rate | Determinism | Main work | ALMs (estimate) | Timing state | Risk |
|---|---|---|---|---|---|---|
| (a) | 50.000 | GPU split makes it async anyway | GPU split, SPU strobe, SDRAM 2:1, all clk_2x at 100 MHz | +400 to +900 | GPU, SPU, DDR3 at 100 MHz unmeasured; GTE -0.59 to -1.32 ns | high |
| (b) | 50.000 | asynchronous | CPU domain, async crossings, SDRAM 2:1 | +350 to +800 | CPU side met (+1.96 ns); GTE per (d) | medium |
| (c1) | 50.8032 | synchronous | ce audit, multicycle SDC | +100 to +300 | every ce path at risk | high |
| (c2) | 50.8032 | synchronous 3:2 | as (b), one PLL output | +350 to +800 (async-safe) | CPU side met at 20 ns, 19.68 ns not measured; GTE at 9.842 ns | medium-low |
| (c3) | 50 average | synchronous | none | 0 | 1,446 endpoints, -8.23 ns | rejected |
| (d1) | GTE 2x | | MAC path restructure | +100 to +300 | needs about 1.1 ns (worst E4 seed at 9.842 ns) plus margin, about 1.3 ns | medium |
| (d2) | GTE any | | busy counter, read fix, turbo sequences | +50 to +150 | 80 MHz has +1.392 ns (C4) | medium |

With the high estimates (+800 crossings, +300 GTE) the projection becomes
35,634 to 37,784 ALMs (85.0 to 90.2%); the high end touches the 90%
margin of docs/f0_budget.md 5.2.

## 4. Recommendation and steps

**Recommended:** the (b) partition, built with async-safe crossing
entities, first clocked as (c2) at 50.8032 / 101.6064 MHz, with the GTE
on the 2x clock and (d1) to close it.

Superseded in part 2026-10-05: the (b) partition, the async-safe
crossings and the GTE at 2x stand; the (c2) bring-up clock, step 3's
50.8032 MHz PLL output and step 5 as a separate later step are replaced by
the section "Plan for exactly 50.000 MHz (2026-10-05)", whose step list
(P4) replaces steps 1 to 5 below. Reason 2 (determinism through c2) no
longer applies.

Reasons:

1. The partition matches the board: CPU-side chip on one crystal, GPU and
   SPU on theirs (2.2). The GPU drawing time and the SPU sample rate, both
   already right for PS1 timing and both needed for R23, are not touched.
2. (c2) keeps the system deterministic during bring-up and lets STA check
   every crossing; the clocks already exist except one PLL output.
3. Writing the crossings async-safe from the start means the later choice
   between 50.8032 and 50.000 MHz is a PLL output and an SDC change, not a
   redesign.
4. At 2x the GTE's per-command hold is already exact for all 22 commands;
   (d1) changes no behaviour, and its equivalence can be shown with the
   benches that exist. (d2) stays the fallback if (d1) does not close.

Every change goes behind generics on psx_top, defaulting to upstream, as
for the F0 trims (PLAN.md 5, 2026-10-04 decision).

### Steps and gates

**0. Measure first (no RTL change)**

0.1 MAME oracle (Mac, cheap): trace reads and writes at 0x1fa51c00-0x1fa51dff
    and 0x1fa60000 (R2), SPU register accesses at 0x1f801c00-0x1f801dff
    with their spacing, and root counter mode writes (sysclk, /8, dot
    clock, hblank) and target IRQ use in the six games. Decides whether the
    SPU crossing needs the second window and whether the timer clock source
    matters to any game.
0.2 RAM latency table in simulation: CPU-cycle latency of RAM read, RAM
    write, instruction fetch miss, BIOS fetch and an external-bus (flash)
    read, with the upstream system testbench (sim/system/src/tb/tb.vhd:220-256
    runs 33/66/100 MHz clocks with sdram_model3x), at today's 3:1 ratio.
    This is the baseline the 2:1 SDRAM front end is compared against.
0.3 sdram.sv index at 2:1: confirm in a small simulation that the current
    generator never fires (1.2), then specify the 2:1 replacement.
0.4 STA query on an existing fit (compile PC):
    paths from clk_1x to clk_2x and clk_3x registers, and back, inside cpu,
    gte, dma and the SDRAM front end, with their slack against the half
    period they have today (14.76 ns and 9.84 ns). Paths with less than
    4.76 ns of slack today fail at 10 ns. Not covered by B to E4, which
    constrained register groups, not these clock pairs as such.
    Gate 0: the list of paths and the latency table exist.

**1. GTE (d1)**, generic default off.
    Gate 1a (sim): sim/gte_narrow 2,000,000 random requests 0 mismatches;
    sim/gte_timing all 22 commands exact at 2x; ps1-tests gte value tests
    pass (harness needs-review).
    Gate 1b (fit, B-style SDC at 9.842 ns into the GTE): three seeds, no
    failing GTE endpoint, worst slack at least +0.2 ns (my margin choice
    for seed spread). If not met after (d1), go to (d2) at a 1.6x or 1.5x
    clock and add the read fix.

**2. Partition refactor at unchanged clocks**: CPU-domain clock ports on
    psx_top tied to clk_1x/clk_2x (SDRAM still 3:1), crossing entities in
    place but bypassed by generic.
    Gate 2: upstream configuration synthesises to identical totals (the
    F0 check method, f0_budget.md 3.1); system testbench traces identical
    to before (bus and PC trace).

**3. CPU domain on.** PLL output 50.8032 MHz, SDRAM front end 2:1 on
    clk_3x, crossings active, timers on the CPU clock by default (generic
    for 33.8688 MHz ticks).
    Gate 3a (sim): each crossing entity in a unit bench with random
    back-pressure and both clock phases; PS1 BIOS boot in the system
    testbench; G-NET boot when the M2 simulation exists; GTE counts
    unchanged in the full system.
    Gate 3b (fit): all clocks meet setup and hold over three seeds (D and
    E4 showed seed-dependent clk_1x hold misses of -0.05 to -0.07 ns);
    ALM delta recorded against the estimate.

**4. Calibration (needs M2/M4):** boot loader 14.69 s and Ray Crisis demo
    1 at 51.5 s (docs/r1_speed_study.md) against the core; wait states
    (RAM, BIOS, memctrl delays, step 0.2 table) adjusted only with
    evidence; results recorded in R1/R23.

**5. Exact 50.000 MHz (my decision):** separate PLL with 50 and 100 MHz,
    asynchronous clock groups in the SDC, gates 3a/3b and 4 repeated with
    non-rational clocks in simulation (for example 20 ns against
    29.5257 ns).

## 5. Open decisions for Lee

1. Final CPU rate: DECIDED 2026-10-05 (Lee): exactly 50.000 MHz (100 MHz
   crystal halved, the PS1 convention; medium confidence, inference). The
   design targets it directly: crossings to the PS1-clock blocks are
   asynchronous-safe. Calibration once the system boots: the PCB boot
   loader (14.69 s, docs/r1_speed_study.md); rank-1 check: a clock
   measurement on a CXD8661R board.
2. Root counters and SIO0 baud base: CPU clock (CXD8661R-internal, MAME's
   counter readback) or 33.8688 MHz (MAME's IRQ scheduling). Proposed
   default: CPU clock, behind a generic, until a board measurement.
   (Superseded: Measurement 1c changed the proposed default to 33.8688
   MHz-equivalent ticks; the 50.000 MHz plan, P3, gives the accumulator.
   Still open for Lee.)
3. GTE route: (d1) first with (d2) as fallback, or (d2) directly, which
   also allows fixing the MTC2/CTC2/LWC2 hold divergence from psx-spx.
4. Whether to fix that MTC2/CTC2/LWC2 hold divergence at all (separate from
   the rate; it changes PSX_MiSTer behaviour that games may rely on).
5. Approval for step 0.4 (Quartus STA on the compile PC) and later fits.

## 6. Needs-review list

- PLL VCO of rtl/pll (whether 50.8032 MHz is an integer divider) and free
  PLLs on the 5CSEBA6 for a separate 50/100 MHz PLL. (Answered from the B1
  fit report: VCO 406.425598 MHz, 4 of 6 PLLs used; see the 50.000 MHz
  plan, P1.)
- sdram.sv index at 2:1 (my derivation says it never fires).
- Root counter and SIO clock source on the ZN-2 (MAME inconsistent).
- Meaning of the 0x1fa51c00 window and 0x1fa60000 toggle (R2).
- GPU and SPU register access latency across the chip boundary on the
  real board.
- Gains of (d1) items 1 to 3 and the Cyclone V DSP modes they rely on.
- Value equivalence of the GTE turbo exits (needed only for d2).
- Dot clock pulses missed by the timer in asynchronous video mode (1.4).

## Plan for exactly 50.000 MHz (2026-10-05)

Design only: no RTL, SDC, PLL or QSF file changed, no fit run. Basis: my
decision (section 5, item 1), the sections above, docs/cpu_rate_probe.md
(main and branch gte-mac-100), branch r1-clk-ratio (section "Step:
fast-clock ratio generic" in its copy of this file), branch zn2-layer, and
the B1 fit report `builds/20261005_0348_b1/GNET_B1.fit.rpt`. Line numbers
are main at 8b8a3bc unless a branch is named. Cycle counts are CPU cycles
at 50 MHz (20 ns) unless stated; ALM figures marked "estimate" are mine.

Summary: the CPU group {clk_cpu 50.000 MHz, clk_cpu2x 100.000 MHz} comes
from a new integer-mode PLL; the PS1 group {clk_1x, clk_2x} and clk_vid
keep their PLLs unchanged. The SDRAM controller moves with the CPU at 2:1
(the CLK_FAST_RATIO = 2 case already verified on r1-clk-ratio), so main
RAM, BIOS and flash need no crossing. 20 interfaces cross between the
groups: 3 dual-clock FIFOs, 5 request/acknowledge handshakes, 3 pulse
synchronisers and 9 level groups, about 540 to 900 ALMs (estimate). GPU
and SPU register reads become 7 to 12 cycles instead of 2 (GPU) and gain
6 to 11 cycles (SPU); this is timing only and is a calibration item.

### P1. Clocking

What the fit report says (GNET_B1.fit.rpt):

| Item | Value | Report line |
|---|---|---|
| PLLs used | 4 of 6: pll_hdmi, pll_audio, emu pll, pll_vid_fixed | 91, 7778, 8919-9100 |
| emu pll (rtl/pll/pll_0002.v) | VCO 406.425598 MHz, M 8 plus fraction 551954751 / 2^32, N 1; C 12 (clk_1x 33.868799), 6 (clk_2x 67.737599), 4 (clk_3x 101.606399) | 9003-9059 |
| pll_vid_fixed | VCO 429.5454 MHz, M 8, N 1, 53.693175 MHz | 9061-9100 |
| Global clocks | 12 of 16 | 7780 |
| Reference | emu pll fed from FPGA_CLK2_50 (CLKIN(2)) | 9030 |

The existing emu PLL cannot add exact 50.000 and 100.000 MHz outputs
without changing its others. Every output of one PLL is VCO / C with an
integer C. 50 / 33.8688 = 15625 / 10584 in lowest terms, so a VCO giving
both exactly must be a multiple of 33.8688 x 15625 MHz = 529.2 GHz. Quartus
could only approximate, which means retuning the VCO and with it clk_1x and
clk_2x. (I did not check the Cyclone V counter and VCO limits in the device
handbook; the argument does not depend on them.)

Plan:

- New file rtl/gnet/pll_cpu.v, a second altera_pll written like
  rtl/gnet/pll_vid_fixed.v (lines 25-43): refclk CLK_50M,
  fractional_vco_multiplier("false"), outputs 50.000000 MHz and
  100.000000 MHz, phase 0, duty 50. Both are integer multiples of the
  50 MHz reference, so an integer M/N/C setting exists (for example the
  report-convention VCO of 400 MHz with M 8, N 1 as the emu PLL uses, and C
  8 and 4; Quartus picks, the fit report confirms). Both outputs come from
  one VCO at phase 0, so clk_cpu and clk_cpu2x are phase-aligned and STA
  times their paths as synchronous, the relation clk_1x and clk_2x have
  today. CLK_50M itself is not used as the CPU clock: the PLL's 100 MHz
  output would then sit at an offset set by the compensation mode.
- rtl/pll/pll_0002.v stays byte-identical, so clk_1x and clk_2x keep their
  exact settings. clk_3x then only feeds sdram2, which exists only with
  MISTER_DUAL_SDRAM (PSX.sv:1363-1415).
- Resources: PLLs 5 of 6; global clocks 14 of 16 (13 if clk_3x becomes
  unused). A third output at 80.000 MHz (C 5 on the same VCO) is available
  for the GTE fallback (d2) without a further PLL.
- Lock and reset: the main SDRAM's init takes pll_cpu's locked instead of
  the emu PLL's (PSX.sv:1308); the core reset is held until both PLLs lock.
- Needs-review: whether the fitter gives a fifth PLL a dedicated reference
  path from a 50 MHz pin (FPGA_CLK1_50, FPGA_CLK2_50, FPGA_CLK3_50) or
  routes the reference over the global network.

Block assignment:

| Block | Instance | Clocks today | Clocks in the plan |
|---|---|---|---|
| cpu | psx_top.vhd:1948-1953 | clk1x; clk2x (scratchpad read port); clk3x (icache fill port written by the SDRAM controller, cpu.vhd:626) | clk_cpu; clk_cpu2x on both the clk2x and clk3x ports |
| gte | psx_top.vhd:2026-2031 | clk1x, clk2x | clk_cpu, clk_cpu2x (2x, 100 MHz) with GTE_NARROW_MUL = 3 from gte-mac-100 |
| memorymux | psx_top.vhd:1794-1798 | clk1x (clk2x port unused) | clk_cpu |
| memctrl | psx_top.vhd:978-981 | clk1x | clk_cpu |
| dma | psx_top.vhd:1281-1285 | clk1x, clk3x | clk_cpu, clk_cpu2x; DMA FIFO strobe from the 2:1 generator (CLK_FAST_RATIO = 2, r1-clk-ratio) |
| irq, timer, sio (SIO1), exp2 | psx_top.vhd:1239, 1396, 1208, 1780 | clk1x | clk_cpu; timer and SIO0 bit timing from sys_tick (P3) |
| ce/pause generator, RAM glue, index generators | psx_top.vhd:703-734, 762-818, 1366-1394 | clk1x, clk2x, clk3x | CPU copies on clk_cpu/clk_cpu2x. A second clk2xIndex generator stays on clk_1x/clk_2x for gpu, spu and savestates |
| SDRAM controller `sdram` (main RAM, BIOS, flash via ch3) | PSX.sv:1293-1345 (clk 1309, clk_base 1310) | clk_3x / clk_1x, 3:1 | clk_cpu2x / clk_cpu, exactly 2:1 with CLK_FAST_RATIO = 2. At 100.000 MHz the controller runs at the rate its constants assume (sdram.sv:96-102: CAS 2 "for < 100MHz", refresh 780 cycles "@ 100MHz") |
| G-NET glue (gnet_fc, gnet_ctrl, gnet_flash, gnet_rf5c296, gnet_ata) | rtl/gnet/*.sv (merged M2) | clk1x, CLK_HZ 33,868,800 (gnet_fc.sv:34) | clk_cpu, CLK_HZ 50,000,000 |
| ZN-2 I/O: zn2_board, zn2_io, zn_sio0, zn_cat702, znmcu | zn2-layer psx_top.vhd:2427; zn2_board.vhd:35, 238-342 | clk1x, CLK_HZ 33,868,800 | clk_cpu, CLK_HZ 50,000,000 |
| hps_io, hps_ext, download processes | PSX.sv:411-413, 486-488, 497-502, 559 onwards; zn2-layer PSX.sv:538-593, 661-676 | clk_1x | clk_cpu (my proposal): ioctl writes to SDRAM ch3 and to the zn2_board loader stay synchronous; only the card download crosses (C19) |
| gpu with videoout | psx_top.vhd:1520-1529 | clk1x, clk2x, clkvid | unchanged |
| spu (SPU RAM in DDR3: SPUSDRAM fixed 0 in LEAN, PSX.sv:1026) | psx_top.vhd:1703-1709 | clk1x, clk2x | unchanged |
| DDR3 arbiter, DDR3 mux, bridge | psx_top.vhd:865-976, 2061-2066; PSX.sv:1430 | clk_2x | unchanged |
| savestates engine (the reset sequencer when HAS_SAVESTATES = 0) | psx_top.vhd:2169-2178 | clk1x, clk2x | unchanged; types 12 and 16 move to a CPU-side filler (C17) |
| zn2_cardmem (DDR3 client for the card image) | zn2-layer psx_top.vhd:2484 | clk2x | unchanged |
| sdram2, framework video and audio | PSX.sv:1365-1415 | | unchanged |

### P2. Crossings

Groups: CPU {clk_cpu, clk_cpu2x}; PS1 {clk_1x 29.525 ns, clk_2x 14.763 ns};
clk_vid 18.624 ns. 33.8688 / 50 = 10584 / 15625, so the groups are
asynchronous and every crossing below is built to be safe for unrelated
clocks.

Latency building blocks (my calculation from the periods): a two-flop
synchroniser into clk_cpu shows a level 1 to 2 cycles after the source
edge, 3 if the first stage goes metastable; into clk_1x 29.5 to 59 ns (1.5
to 3 cycles), 88.6 ns (4.4) worst. A toggle pulse synchroniser adds one
register. A posted word through a dual-clock FIFO with gray pointers
reaches a clk_1x reader 4 to 7 cycles after the write. A
request/acknowledge read (request 2FF into clk_1x, about 2 clk_1x cycles of
device side, acknowledge 2FF back, one capture cycle) takes 128 to 178 ns
(7 to 9 cycles), 228 ns (12) worst.

| # | Interface | Direction | Source and sink | Method | Added latency | Visible to software |
|---|---|---|---|---|---|---|
| C1 | GP0 and GP1 writes, DMA channel 2 words to the GPU | CPU to clk_1x | memorymux.vhd:402-409 (bus_gpu_*), dma.vhd:697-700; gpu.vhd:828-850 (fifoIn written on clk2x with clk2xIndex = 1), GP1 in the clk1x process (gpu.vhd:552 onwards) | Dual-clock FIFO, 16 x 34 bits (data plus GP0/GP1/DMA tag, one FIFO keeps their order) on dpram.vhd's two-clock RAM; the GPU side emits at most one write per clk_1x cycle, the form gpu.vhd gets today | CPU 0 (posted); the GPU sees a word 4 to 7 cycles later than today | Only through later reads, which wait for C1 to drain (C2) |
| C2 | GPUSTAT and GPUREAD reads | CPU to clk_1x and back | memorymux.vhd:787-821 (BUSREAD waits on bus_stall, 424); gpu.vhd:594-624 | Request/acknowledge, 32-bit data held at the GPU side; the bridge holds bus_gpu_stall high; the GPU side waits for gpu.vhd's own bus_stall (vram2cpu not ready) before capturing; issued only when C1 is empty | 7 to 9 cycles from request to data, 12 worst, against 2 today | Timing only: each GPUSTAT poll takes longer. The real CXD8661R to CXD8654Q latency is unknown (calibration) |
| C3 | VRAM to CPU read-back: GPUREAD data and DMA channel 2 from the GPU | clk_2x to CPU | gpu_vram2cpu.vhd:101-124 (Fifo_ready, 1024-word fall-through FIFO); gpu.vhd:1131-1138; dma.vhd:220, 226, 701-705 (DMA_GPU_read used in the cycle readEna is high) | Dual-clock FIFO: gpu_vram2cpu's FIFO made dual-clock (write clk_2x, read clk_cpu), so the RAM already there is reused. All readers (CPU GPUREAD, DMA) pop on the CPU side; a CPU-side GPUREAD mirror, its non-empty ORed into GPUSTAT bit 27 and the direction-3 DMA request (gpu.vhd:528-531, 1138), Fifo_ready as a 2FF level for the GPUREAD stall | First word 4 to 7 cycles after the GPU writes it, then one word per cycle as today | Values and order unchanged if every reader goes through the CPU side. This is Measurement 4's largest clk_2x to clk_1x group (gpu_vram2cpu, 111 paths) |
| C4 | gpu_dmaRequest | clk_1x to CPU | gpu.vhd:500, 528-531; dma.vhd:226, 360, 370 | 2FF level, ANDed with "C1 empty" so a block does not start on a request computed before the previous block's words arrived | 1 to 3 | DMA start timing only |
| C5 | DMA_GPU_waiting | CPU to clk_1x | dma.vhd:216-218; gpu.vhd:522 (GPUSTAT bit 26) | 2FF level | 1.5 to 3 | Bit 26 lags the DMA state by less than a C2 read takes |
| C6 | irq_GPU | clk_2x to CPU | gpu.vhd:929-948 (high for one clk_1x period); irq.vhd:125-126 (rising edge) | Toggle pulse synchroniser | 2 to 4 | Interrupt latency only |
| C7 | irq_VBLANK | GPU to CPU | gpu_videoout_async.vhd:375, 432-437 (set at a line start, cleared at the next, so held one line); gpu.vhd:534 | 2FF level; irq.vhd's edge detect unchanged | 1 to 3 | No |
| C8 | SPU register writes and DMA channel 4 writes | CPU to clk_1x | memorymux.vhd:940-943; dma.vhd:349-351, 716-719; spu.vhd:1107, 2389-2393 | Dual-clock FIFO, 8 x 27 bits (10-bit address, 16-bit data, tag), one write per SPU clk_1x cycle | CPU 0 (posted); the SPU sees it 4 to 7 cycles later | Only through later reads (C9 waits for C8 to drain). Game SPU accesses are at least about 100 cycles apart (Measurement 1b) |
| C9 | SPU register reads | CPU to clk_1x and back | memorymux.vhd:1189-1211 (bus_spu_read in EXT_READ_NEXT, data taken in EXT_READ one cycle later, no wait input on main); spu.vhd:1213-1264 | Request/acknowledge as C2, 16 bits. memorymux needs a wait in EXT_READ: zn2-layer's zn_stall (its memorymux.vhd:991-992) is the mechanism to extend to the SPU select | +6 to +11 cycles on the ext bus counts: an SPU LH at the games' read setting, 6 cycles at 3:1 (Measurement 2), becomes about 12 to 17 | Timing only. In the games each SPU read follows the 0x1fa51c00 request and the 0x1fa60000 bit 3 poll, 1.0 to 2.0 us in MAME (about 50 to 100 cycles, Measurement 1a), so the added cycles fall inside the board's own handshake. The poll value comes from zn2_io's SPU_STATUS generic (zn2-layer zn2_io.vhd:33, 61, 233), not from C9 |
| C10 | SPU DMA reads (channel 4 from the SPU) | clk_1x to CPU | dma.vhd:224, 467-470, 721-723; spu.vhd:563-564 (show-ahead FifoOut) | Handshake per halfword with a DMA stall (dma.vhd's readStall, today channel 2 only, line 226, extended to channel 4) | About 8 to 12 per halfword (estimate) | Only if a game reads SPU RAM by DMA; raycris and psyvaria only wrote (CHCR 0x01000201, Measurement 1b) |
| C11 | spu_dmaRequest | clk_1x to CPU | spu.vhd:580; dma.vhd:362, 372 | 2FF level, ANDed with "C8 empty" | 1 to 3 | No |
| C12 | irq_SPU | clk_1x to CPU | spu.vhd:1083-1103 (one clk_1x cycle) | Toggle pulse synchroniser | 2 to 4 | Interrupt latency only |
| C13 | hblank to the timers | clk_vid to CPU | gpu_videoout_async.vhd:661-762 (hblank_tmr), today 3 FF into clk_1x (203-211), gpu.vhd:535 | 2FF level from the clk_vid register (new gpu output port), or 2FF on gpu's clk_1x copy | 1 to 3 cycles from the clk_vid edge (today 2 to 3 clk_1x cycles, 59 to 89 ns) | No: timer 1 counts edges |
| C14 | vblank to the timers | clk_vid to CPU | gpu.vhd:563; timer.vhd sync modes | As C13 | 1 to 3 | No |
| C15 | Dot clock to timer 0 | clk_vid to CPU | gpu_videoout_async.vhd:246 (one clk_vid cycle per dot, clkDiv 4 to 10, lines 620-626); gpu.vhd:1991 | Toggle in clk_vid, 2FF and edge detect on clk_cpu. Dots are at least 4 clk_vid periods (74.5 ns, 3.7 cycles) apart, so none are missed, unlike today's sampling (section 1.4) | 2 to 4 | Counter 0 dot clock mode only, unused by both traced games (Measurement 1c) |
| C16 | Run/pause and idle | both | psx_top.vhd:753-818 (SS_idle, Pause_Idle, ce, pausing); gpu ports allowunpause/system_paused (1531, 1533); gpu and spu ce (1528, 1709) | ce generator in the CPU group; ce and pausing to GPU and SPU as 2FF levels; SS_Idle_gpu, SS_idle_spu and allowunpause back as 2FF levels, ANDed with C1 and C8 empty | 1 to 3 | OSD pause only |
| C17 | Reset and the reset sequencer | both | reset_in psx_top.vhd:695-700; savestates.vhd:211-214, 336-360 (WAITPAUSE, WAITIDLE), 560 onwards (fill); SS_wren(12) scratchpad psx_top.vhd:2011, SS_wren(16) RAM fill memorymux.vhd:905 | Reset request (PSX.sv reset, watchdog, reset_exe) into the engine as a 2FF level stretched to at least 4 clk_1x cycles; reset_out into the CPU group through a reset synchroniser (asynchronous assert, synchronous release); savestate_pause and pausingSS are levels held through the engine's WAITPAUSE/WAITIDLE handshake, 2FF each; ss_reset is a one-cycle clk_1x pulse (savestates.vhd:214, 280-281), so the CPU group makes its own SS_reset from the synchronised reset; the scratchpad (type 12) and RAM (type 16) zero fill move to a CPU-side filler, the engine skips 12 and 16 by generic, 14 and 15 (SPU RAM, VRAM in DDR3) stay | Reset time only | No, if the fill result is the same (zeros) |
| C18 | Card memory port (gnet_ata to zn2_cardmem) | CPU to clk_2x and back | zn2-layer zn2_cardmem.vhd:13-24 ("request held until ack", written for clk2x = 2 x clk1x) | Four-phase handshake, address and data held stable | About 8 to 12 per 16-bit word on top of the DDR3 time (estimate) | Card load time (calibration with M4) |
| C19 | Card image download | CPU (hps_io) to clk_2x | zn2-layer PSX.sv:564-593 (zn_card_dl_wr pulse, dl_busy, ioctl_wait) | Pulse synchroniser with the data held, dl_busy back as a 2FF level; ioctl_wait already holds the HPS | None that matters | No |
| C20 | Static configuration (OSD video options) | CPU (hps_io status) to clk_1x/clk_vid | PSX.sv:995-1030 (mostly constants in LEAN) | 2FF or false path; changed only from the OSD | | No |

Measurement 4's inventory in the new partition:

| Measurement 4 group | Status in the plan |
|---|---|
| clk_1x to clk_3x: dma 64, memorymux 53 | clk_cpu to clk_cpu2x, synchronous 2:1, 10.0 ns relationship (9.841 ns today) |
| clk_1x to clk_3x: bios_download 48 | Synchronous, with hps_io and the download logic on clk_cpu |
| clk_3x to clk_1x: sdram dma_done 37, ready flags | clk_cpu2x to clk_cpu, synchronous |
| clk_2x to clk_1x: gte 39, datacache 37 | clk_cpu2x to clk_cpu, synchronous, 10.0 ns instead of 14.762 ns (tighter; risk 2 in P5) |
| clk_2x to clk_1x: gpu_vram2cpu 111 | Real crossing: C3 |
| clk_1x to clk_2x: savestates 171, psx_top 29 | Stay inside the PS1 group (needs-review: which of the 29 psx_top paths start in blocks that move, for example ce or reset_intern into the DDR3 arbiter, psx_top.vhd:875) |

SDC: derive_pll_clocks creates the new clocks. A blanket
set_clock_groups -asynchronous would hide a missing synchroniser, so I
propose set_max_delay -datapath_only of one destination period on the
named crossing registers (gray pointers, held handshake data) and false
paths only into first synchroniser stages found by a naming convention
(*_cdc_s1*), plus an extension of tools/sta/xclk_query.tcl that lists every
path between the groups and fails if one ends anywhere else. The clk_vid
false paths in GNET_LEAN.sdc:4-15 get the two new clocks.

### P3. Root counters and SIO0 at 33.8688 MHz equivalents

Generator, one instance in psx_top on clk_cpu (my design):

- acc is 14 bits holding 0 to 15624; each cycle with ce = 1 it computes
  s = acc + 10584 (15-bit sum, at most 26208). If s >= 15625 then
  acc <= s - 15625 and sys_tick = 1, else acc <= s and sys_tick = 0.
- Exactly 10,584 ticks per 15,625 cycles (312.5 us): the average rate is
  33.8688 MHz exactly, relative to the board's 50 MHz oscillator, with no
  drift.
- Jitter: since 10584 / 15625 = 0.677376 is above 1/2, ticks come 1 or 2
  cycles apart (20 or 40 ns against the ideal 29.525 ns), and each tick
  is less than one CPU cycle (20 ns) from the ideal 33.8688 MHz grid,
  peak-to-peak 20 ns, not accumulating.
- Effect on raycris's sound tick (counter 2, sysclk / 8, target 17,640 =
  141,120 ticks, Measurement 1c): each period 4.1667 ms within 20 ns
  (4.8 ppm), average 240.000 Hz.
- A binary accumulator (32-bit, increment round(0.677376 x 2^32) =
  2,909,307,767) has the same jitter and a -0.03 ppb rate error with a
  wider adder; the modulo form is exact and smaller.
- acc resets to 0; with HAS_SAVESTATES = 0 nothing is saved. Upstream
  savestate builds would shift by at most one tick on load.

Consumers, behind a generic for open decision 2 (SYSCLK_SRC: 0 = CPU
clock, sys_tick constant 1; 1 = sys_tick):

- timer.vhd:148-185: timer2_subcount (line 150) advances only on sys_tick,
  and the sysclk branches of newTick for counters 0, 1, 2 become sys_tick.
  The hblank, vblank and dot clock edge detectors keep running every
  cycle. Counter reads (up to 13,355 per second) stay in the CPU group with
  no crossing.
- zn_sio0 (zn2-layer zn_sio0.vhd:109, 162-164): tcount decrements on
  sys_tick, so a bit lasts period x 29.525 ns on average with at most 20 ns
  jitter per edge (BIOS setting 48 counts per bit, zn2_layer_design.md:202).
- Hblank, vblank and dot clock come from the GPU side through C13 to C15,
  not from the accumulator.

### P4. Steps and gates

Done: section 4 steps 0.1 to 0.4 (Measurements 1 to 4); the 2:1 strobe
generic (r1-clk-ratio, bench r2p2 18 of 18 rows and DMA phase 0 errors).
Steps 1 to 5 of section 4 are replaced by:

| Step | Work | Gate |
|---|---|---|
| 0.5 | MAME trace (Mac): VRAM to CPU use in the six games (GP0 C0h, GPUREAD reads, DMA channel 2 from the GPU) and the channel 4 direction in all six | Decides how much of C3 and C10 is needed now |
| 0.6 | r1-clk-ratio mem_lat bench at 20 / 10 ns (r2p2 at exact 50 / 100) | 18 of 18 rows, DMA phase 0 errors, same cycle counts as r2p2 |
| 1 | GTE: fit of E6 (revision GNET_F0_CPU50E6, gte-mac-100) at 10 ns, three seeds. At 100.000 MHz the target is 10.000 ns, which is what the B to E6 SDCs constrain, so their slacks apply without the 0.158 ns penalty of the 101.6064 MHz plan | No failing GTE endpoint, worst slack at least +0.2 ns on all seeds (the margin of section 4). Else (d2) with the GTE at 80.000 MHz from pll_cpu (C4: +1.392 ns at 12.5 ns) |
| 2 | Merge r1-clk-ratio after its GNET_B1R2 synthesis (not run yet) | Default build identical in totals to B1 (the F0 method, f0_budget.md 3.1) |
| 3 | CDC entities: level, pulse, handshake, dual-clock FIFO (gray pointers on dpram.vhd), each with an NVC bench | At least 1,000,000 transfers per entity with random back-pressure, at 20 against 29.5257, 14.7629 and 18.6243 ns, random start phases, and a synchroniser model that randomly adds a cycle; 0 errors; negative controls (synchroniser removed, binary instead of gray pointers) caught |
| 4 | C1 to C20 behind a psx_top generic CPU_CLK_SPLIT (default 0 = upstream wiring) at unchanged clocks | 4a: default builds identical in totals. 4b (sim): with CPU_CLK_SPLIT = 1 PS1 BIOS boot in the system bench and the zn2-layer silent test (M2 trace replay) functionally identical; sim/gte_timing counts unchanged |
| 5 | pll_cpu and the CPU group on (macro, for example GNET_CPU50): SDRAM 2:1, sys_tick, hps_io on clk_cpu, CLK_HZ 50,000,000, SDC | 5a (sim): as 4b with the real periods; accumulator gives 10,584 ticks per 15,625 cycles; FIFO overflow assertions never fire over a full DMA chain. 5b (fit): three seeds, every clock meets setup and hold (D and E4 showed seed-dependent clk_1x hold misses), crossing check clean, PLLs 5 of 6, ALM delta inside the estimate below |
| 6 | Hardware and calibration (section 4 step 4): boot loader 14.69 s, Ray Crisis demo 1 at 51.5 s, plus C2/C9 read latency and C18 card latency as calibration items | Recorded in R1/R23 |

Branches that feed in: r1-clk-ratio (CLK_FAST_RATIO generic in psx_top,
psx_mister, sdram.sv; mem_lat bench with ratio and DMA phase), gte-mac-100
(GTE_NARROW_MUL = 3, sim/gte_equiv, revisions E5/E6), zn2-layer
(zn2_board and its devices, memorymux ZN2_MAP with zn_stall for C9,
zn2_io SPU_STATUS, zn2_cardmem for C18/C19). The M2 glue is already on
main.

ALMs for the crossings and the tick (estimate):

| Item | ALMs | RAM |
|---|---|---|
| C1 GPU write FIFO | 60 to 100 | 2 MLAB or 1 M10K |
| C2 GPU read handshake | 50 to 70 | |
| C3 read-back (FIFO made dual-clock, CPU-side control) | 60 to 150 | existing |
| C8 SPU write FIFO | 50 to 80 | 1 to 2 MLAB |
| C9 SPU read handshake and memorymux wait | 50 to 80 | |
| C10 SPU DMA read handshake and DMA stall | 30 to 50 | |
| C18 card memory handshake | 70 to 100 | |
| C19 card download handshake | 50 to 70 | |
| C4 to C7, C11 to C16, C20: about 25 synchronised signals, 3 pulse synchronisers | 30 to 50 | |
| C17 reset synchronisers and CPU-side filler | 60 to 100 | |
| P3 accumulator and the timer/SIO0 gating | 30 to 45 | |
| Total | about 540 to 900 | |

That is in the range of option (b)'s +350 to +800 (section 3) plus the
G-NET card and reset paths. Added to the projection of 34,534 to 36,684
ALMs (section 3) it gives 35,074 to 37,584 (83.7 to 89.7% of 41,910),
before the GTE change (E5 seed 1 fitted at 26,805 ALMs against E4's
27,771, docs/cpu_rate_probe.md on gte-mac-100).

### P5. Risks and needs-review

| # | Risk | Status |
|---|---|---|
| 1 | GTE at 10 ns: E6 has passed simulation but has no fit; E5 seed 1 was -1.283 ns, all from the early decode E6 rewrites | Gate 1; fallback (d2) at 80.000 MHz from the same PLL |
| 2 | Paths inside the CPU group that are clk_1x to clk_2x or back today (scratchpad read, GTE command and result, datacache) get 10.0 ns instead of 14.762 ns; B to E constrained them only as 20 ns or 10 ns register groups, not as this clock pair. Measurement 4's largest clk_2x to clk_1x data delay was 8.86 ns | Gate 5b; needs-review on the first fit with real clocks |
| 3 | No cycle determinism: crossing latency varies by up to about 3 cycles per access from run to run, so MAME trace comparisons must be functional, not cycle-exact | Accepted with the decision; benches randomise phase |
| 4 | C3 semantics: GPUREAD mirror, GPUSTAT bit 27 and the direction-3 DMA request, flush on GP1 resets (gpu_vram2cpu reset is softreset or SS_reset, gpu.vhd:1146; which GP1 commands reach it: needs-review) | Step 0.5 decides the depth of work; unit bench with VRAM reads |
| 5 | C1 throughput margin: DMA channel 2 at 2:1 delivers 33.0 M words/s against the GPU side's 33.8688 M/s (2.6%); no back-pressure from GPU to DMA exists (dma.vhd:676-700) | Overflow flag into errorGPUFIFO and a sim assertion; add a DMA stall if it ever fires |
| 6 | Reset sequencer: every level in C17 must be held until seen; a source that is a single-cycle pulse (watchdog, reset_exe) must be stretched; deadlock would show as a core that never leaves reset | Bench of the reset path in step 4b, including the unstallwait fallback (savestates.vhd) |
| 7 | GPU and SPU register reads cost 7 to 12 cycles instead of 2, and the real board latency is unknown | Calibration (step 6); the 0x1fa51c00/0x1fa60000 protocol (Measurement 1a) suggests the board itself is slow there |
| 8 | hps_io and the download logic on clk_cpu: framework blocks fed from hps_io's clk_sys (gamma bus, PSX.sv:1600) then run at 50 MHz | Needs-review; the alternative is crossing ioctl to SDRAM ch3 and the loader |
| 9 | Fifth PLL reference routing (P1) | Fit report, step 5b |
| 10 | Area: the high end reaches 89.7% before further G-NET blocks | f0_budget.md 5.2 margin |
| 11 | Wait states counted in CPU cycles (memctrl delays, BIOS and EXP1 counts, DMA REP timing) run 1.476x faster in real time than at 33.8688 MHz | Already a calibration item (Measurement 3) |

### P6. Decisions for Lee

1. Root counter and SIO0 tick source default: 33.8688 MHz equivalents by
   the accumulator (my proposal, from raycris's 240 Hz sound tick) or the
   CPU clock.
2. SPU reads: plain stall handshake (C9, my baseline) or, later, a
   prefetch started by the 0x1fa51c00 window read with 0x1fa60000 bit 3
   showing its completion, which needs PLAN.md R2 evidence on what the
   board does.
3. Keep the reset zero fill of scratchpad and RAM (CPU-side filler in C17)
   or drop it (the BIOS clears what it needs; MAME's start state decides).
4. GTE fallback if gate 1 fails: (d2) at 80.000 MHz from pll_cpu.
5. Approval for the fits of steps 1, 2 and 5 on the compile PC.

## Measurement 4: crossing paths on an existing fit (2026-10-05)

`tools/sta/xclk_query.tcl` on the B1 fit (`builds/20261005_0348_b1`, normal
clocks), worst 200 setup paths per clock pair (slow model; xclk_*.rpt in
that folder):

| From, to | Paths reported | Setup relationship today | Largest data delay | Main sources |
|---|---|---|---|---|
| clk_1x to clk_2x | 200 (cap reached) | 14.762 ns | 11.54 ns | savestates 171, psx_top 29 |
| clk_2x to clk_1x | 200 (cap reached) | 14.762 ns | 8.86 ns | gpu_vram2cpu 111, gte 39, datacache 37 |
| clk_1x to clk_3x | 200 (cap reached) | 9.841 ns | 9.30 ns | dma 64, memorymux 53, bios_download 48 |
| clk_3x to clk_1x | 88 | 9.842 ns | 3.80 ns | sdram dma_done 37, ready flags |
| clk_2x and clk_3x, both ways | 0 | | | |

(Superseded 2026-10-05: the 50.8032 MHz reading below no longer applies;
at exactly 50.000 MHz every GPU and SPU interface is asynchronous. The
50.000 MHz plan, P2, maps each group of this table to its new status.)
With the CPU at 50.8032 MHz (3/2 clk_1x), my calculation of the closest
edge spacing: CPU to clk_1x and back 9.842 ns; CPU to clk_2x and back
4.921 ns. Reading: crossings between the CPU domain and the blocks that
stay on clk_1x have about the spacing that clk_1x to clk_3x paths already
meet today (data delays to 9.3 ns), but crossings into the GPU and SPU on
clk_2x get only 4.9 ns, while today's clk_1x to clk_2x paths carry up to
11.5 ns of data delay. Those interfaces need registered handshakes or FIFOs
(the crossing design in section 3), not plain synchronous paths. The
savestates paths are absent in the G-NET build only where HAS_SAVESTATES = 0
removes them; B1 keeps the reset sequencer part (needs-review: which of the
171 remain relevant).

## Measurement 1: MAME 0.288 bus trace of SPU, ZN-2 window and root counters (2026-10-05)

Tools: `tools/mame/r1_bus.lua` (taps), `tools/mame/r1_bus_run.sh` (runner),
`tools/mame/r1_mips_dis.py` (capstone disassembly of the RAM dump). Runs, one
MAME at a time under nice -n 15, 180 emulated seconds each, warm from the
post-copy NVRAM, coin at 40 s (0.1 s pulse), start at 42 s, fire and
movement from 45 s:

| Run | NVRAM source | Gameplay confirmed | Output (gitignored) |
|---|---|---|---|
| raycris | sim/oracle/postcopy/raycris | snapshot at 120 s (stage, score) | sim/r1/bus/raycris_warm/ |
| psyvaria | sim/oracle/psyvaria_cold300 | snapshot at 60 s (stage, score); ranking at 150 s | sim/r1/bus/psyvaria_warm/ |

Rates below are means over 20 to 179 s (persec.csv), counts are totals from
summary.txt. MAME times are its cost model (25 M CPU cycles/s), so spacings
are MAME spacings, not board spacings.

### 1a. The ZN-2 window 0x1fa51c00 and 0x1fa60000 (R2)

Every SPU register read by game code goes through one routine (raycris
0x8012e924, psyvaria the same code at 0x8005ea94; disassembly of ram_end.bin):

1. clear DPCR bit 19 (DMA channel 4, SPU, master enable; pointer at
   0x80188ff0 = 0x1f8010f0) and keep the old channel 4 bits;
2. set the EXP3 delay register (0x1f80100c) low half to 0x3022;
3. dummy `lhu` at 0x1fa51c00 plus the SPU register offset (the same low
   bits as 0x1f801c00 plus offset: 0x1fa51dae for SPUSTAT, 0x1fa51c0c for
   voice 0 ADSR volume);
4. poll 0x1fa60000 until bit 3 is set, at most 100 times; on timeout call
   0x801213a0 with "SPU:T/O [%s]" and "ReadStatusFlag Error" (raycris strings
   at 0x80177e54/64, the same strings in psyvaria), then continue;
5. restore EXP3 delay; set SPU delay (0x1f801014) to 0x20093127 and the low
   nibble of COM delay (0x1f801020) to 2;
6. `lhu` the real register at 0x1f801c00 plus offset;
7. restore COM delay, SPU delay and DPCR. If a flag at 0x8028fd78 changed
   during the sequence while interrupts were enabled, the routine repeats
   it (my reading of 0x8012e944-0x8012eaf8; who sets the flag:
   needs-review).

SPU writes use a second routine (raycris 0x8012eb98): same DPCR and delay
save/restore, SPU delay 0x20093127, COM low nibble 7, then `sh` to
0x1f801c00 plus offset. Writes never touch 0x1fa51c00 or 0x1fa60000.

| | raycris | psyvaria |
|---|---|---|
| reads of 0x1fa51c00-0x1fa51dff | 1,104,332, all at PC 0x8012ea0c, never written | 330,736, all at PC 0x8005eb7c |
| reads of 0x1fa60000 | 2,208,663 (2 per sequence after the first: MAME's toggle returns 0, then 8) | 661,471 |
| window read followed by the SPU read of the same offset | every one (x51c_next_spu matches offset for offset) | every one |
| window read to first status poll / SPU read | 40 ns / 1.0 to 2.0 us (MAME) | same |

What this means:

- The window is a read-request port and 0x1fa60000 bit 3 a ready flag for
  SPU register reads: the game asks the board for the register, waits for
  the flag, then reads the SPU address. This fits a CPLD (the EPM7064 next
  to the 67.73 MHz crystal) synchronising SPU reads between the CPU and SPU
  clocks. It is a protocol the game relies on, not a MAME workaround.
- The current core has no device at either address: memorymux sends only
  exactly 0x1fa00000 to the EXP3 bus (memorymux.vhd:705-713) and all other
  addresses to the internal bus, whose read data is the OR of the device
  outputs (memorymux.vhd:426), so 0x1fa60000 would read 0 (reading, not
  simulated). Every SPU read would then take the 100-poll timeout and the
  error print, 6,722 times per second in raycris. The G-NET glue must
  decode both: the window read as a no-op (or as the start of a latched SPU
  read) and bit 3 of 0x1fa60000 as 1 once the read can complete. A
  constant 1 is enough for these two games; MAME's toggle also passes.

### 1b. SPU register accesses

| | raycris | psyvaria |
|---|---|---|
| SPU reads per second | 6,722 | 1,914 |
| SPU writes per second | 1,938 | 527 |
| Registers read | voice ADSR current volume (offset 0xc) of all 24 voices, NON 0x194/0x196, EON 0x198/0x19a, rarely SPUCNT 0x1aa, transfer address 0x1a6, SPUSTAT 0x1ae | same set |
| Registers written | KON 0x188/0x18a, KOFF 0x18c/0x18e, NON, EON each tick; voice registers 0x0 to 0xa (volume, pitch, start, ADSR) per key-on; setup registers once | same |
| Driver tick | 240 per second: 28 reads and 8 writes per tick (39,407 ticks of 24 voice reads) | once per frame: 10,320 ticks from 7.4 s to 180 s (about 60 per second) |
| SPU DMA (channel 4) starts, CHCR 0x01000201 | 185 | 98 |
| Accesses closer than 1.0 us to the previous SPU access | 225 of 1,423,391 | 33 of 421,693 |
| Typical spacing | 2.0 to 8.2 us (hist buckets 11 and 12) | same |

What this means for the SPU crossing: game SPU accesses are at least about
2 us apart in MAME's model (about 100 CPU cycles at 50 MHz), the CPU disables
SPU DMA around each access, and SPU DMA is rare. A simple
request/acknowledge crossing per register access is enough; no FIFO is
needed on the register path, and a 2 to 3 cycle synchroniser per direction
is under 5% of the spacing.

### 1c. Root counters

| | raycris | psyvaria |
|---|---|---|
| Counter 0 | zeroed by the BIOS at boot only (PC 0x39e8-0x39f4) | same |
| Counter 1 mode | 0x0148 (clock source hblank, reset at target, repeat, no IRQ) set by SetRCnt-style code at 0x8011d2b0 and 0x803b6eec; 0x0100 (hblank, free-running) at 0x8012717c | 0x0148 at 0x803b6eec, 0x0100 at 0x800117b8 |
| Counter 1 reads | 13,355 per second: VSync code at 0x80126764/0x80126774 (1,052,433 each; reads the counter until two reads agree, then subtracts a base), GetRCnt at 0x8011d2dc (53,816) | 3,851 per second, the same VSync code at 0x80010e60/0x80010e70 (323,134 each) |
| Counter 1 writes | value reset to 0 at 0x8011d37c 9,673 times (about once per frame) | none after boot |
| Counter 2 | mode 0x0258 (system clock / 8, IRQ at target, reset at target, repeat), target 0x44e8 = 17,640; IRQ acknowledged 240 times per second | not used (4 timer 2 IRQ acks, all in the first 5 s) |
| IRQ mask in play | 0x0469 (vblank, DMA, timer 1, timer 2, bit 10) | 0x0409 (vblank, DMA, bit 10) |

The 0x44e8 comes from a PS1 sound library tick routine (raycris
0x80127974): it selects spec 0xf2000002 (counter 2) with target 0x44e8, or
0x89d0 for half the rate, or the vblank spec 0xf2000003. 33,868,800 / 8 /
17,640 = 240.0 Hz and / 35,280 = 120.0 Hz, so the library assumes the
33.8688 MHz system clock.

Does any game logic pace itself on a counter? No busy wait on a counter
target appears in either game. Frame pacing is the vblank interrupt; the
counter 1 polling is inside the VSync routine (hblank count since the last
vblank and its timeout), so its read count per frame follows idle time, not
the counter. The only counter-clock dependent behaviour found is raycris's
counter 2 sound tick:

| Counter 2 clock | Tick rate (target 17,640, /8) |
|---|---|
| 33.8688 MHz (PS1 system clock, MAME's IRQ timing, rcnt.cpp:220-222) | 240.0 Hz |
| 50.8032 MHz (option c2 CPU clock) | 360.0 Hz |
| 50.000 MHz | 354.3 Hz |

Consequences for open decision 2 (root counter clock):

- Counter 1 runs from hblank in both games, so its rate comes from the
  video timing and does not depend on the CPU clock choice. MAME's counter
  1 hblank divider (2150 MAME double-cycles, 23.3 kHz on ZN-2) is a MAME
  artefact the core does not copy.
- Counter 2 at the CPU clock would run raycris's SPU sound driver 1.5x fast
  (360 Hz at 50.8032 MHz). I now propose 33.8688 MHz-equivalent ticks for
  the system clock and system clock / 8 sources as the default, instead of
  the CPU clock proposed in section 5, until a board measurement says
  otherwise. With the (c2) clock this is exact and cheap: 33.8688 / 50.8032
  = 2 / 3, so the counters stay in the CPU domain with an enable on 2 of
  every 3 CPU cycles, and counter reads (up to 13,355 per second) need no
  crossing. At exactly 50.000 MHz it needs a phase accumulator (10,584 /
  15,625). (The (c2) part is superseded 2026-10-05; the accumulator is
  specified in the 50.000 MHz plan, P3.) Cheap rank-4 check: PCB audio of a raycris SPU-sequenced sound
  against MAME (needs-review: which raycris sounds are SPU-sequenced rather
  than Zoom).
- SIO0: not traced here; unchanged as an open point.

## Measurement 2: memory access latency at the 3:1 SDRAM clock ratio (2026-10-05)

Simulation, not reading: NVC 1.23 with the unmodified rtl/memorymux.vhd and
rtl/memctrl.vhd, rtl/sdram.sv through a mechanical simulation copy
(`tools/r1/mem_lat/sdram_sim_copy.py`: declarations moved before use,
altddio_out replaced by the inverted clock it produces, the inout DQ split
into in and out for NVC's mixed-language ports, an index tap, registers
starting at 0 as the FPGA powers them up), the RAM glue of
psx_top.vhd:1368-1394 and PSX.sv:1291, 1318-1337, and a cycle model of the
SDRAM chip (CAS latency 2, burst 2, data at the capture point sdram.sv's
pipeline expects; no analog margins). Testbench
`tools/r1/mem_lat/tb_r1_mem.vhd`, runner `tools/r1/mem_lat/run.sh`, results
in sim/r1/mem_lat/<variant>/mem_lat.txt. The upstream sim/system testbench
was not usable for this: it replaces sdram.sv with sdram_model3x.vhd, whose
write handshake differs (done at acceptance, sdram_model3x.vhd:304-312,
against ready in RW1 in sdram.sv:489-497).

Metric: clk_1x edges from the edge that samples mem_in_request to the edge
that samples mem_done (the memorymux interface; cpu.vhd adds its own
pipeline cycles on top, not simulated). The CPU posts writes (it stalls only
on mem_fifofull, cpu.vhd:2201, 2466), so for writes I count edges until
memorymux is idle again. 400 samples per row with random gaps, so some hit
an SDRAM refresh; the delay registers are written through the bus as the
games do. Clocks: SDRAM 101.6064 MHz, clk_1x 33.8688 MHz (3:1), rising edges
aligned.

| Access | Cycles at 3:1 (typical, max) | memorymux path |
|---|---|---|
| RAM LW or LBU, no data read started in the previous 7 cycles | 5, 7 | WAITFORRAMREAD, one extra cycle (memorymux.vhd:630-637) |
| RAM LW started within 7 cycles of the previous read's start | 4, 6 | ram_load_last bypass (memorymux.vhd:631-634) |
| Instruction cache line miss, KSEG0 RAM (4 words) | 5, 7 to mem_done; last word in the cache at 5.33 | ram_cache (memorymux.vhd:570-582) |
| Instruction fetch, KSEG1 RAM | 5, 7 | |
| Instruction fetch, BIOS | 31 or 32, 34 | waitcnt 25/26 after ram_done (memorymux.vhd:597-608) |
| BIOS data LW / LH / LB | 31 / 15 / 7, refresh +2 | waitcnt 25 / 9 / 1 (memorymux.vhd:664-669) |
| RAM SW, CPU stall | 0 (posted) | write FIFO |
| RAM SW, memorymux busy after a read / after an SW to the same 1 KB page / after an SW to another page | 4 / 3 / 7, refresh +2 | page logic (memorymux.vhd:640-653) |
| RAM LW right after an SW | 5, 7 | |
| EXP1 (flash stub) LW / LH / LB, EXP1 delay 0x201716bb, COM 0x110 (the games' values) | 29 / 15 / 15 | external bus counts (memorymux.vhd:1030-1269), 16-bit bus |
| SPU LH, SPU delay 0x20093127, COM 0x112 (the games' read setting, 1a) | 6 | external bus |
| SPU LH, SPU delay 0x00093184, COM 0x110 (the games' resting setting) | 12 | external bus |

Data check: 0 errors (LW rows, back-to-back pairs and every read-back after
a write compared against the chip model). clk3xIndex fired 238,149 times in
238,148 clk_1x cycles: once per cycle.

Reading of the table: the RAM part of an access is about 2 to 3 CPU cycles
of SDRAM work plus 2 to 3 cycles of memorymux states; a refresh adds up to 2
cycles. BIOS and EXP1 times are dominated by memorymux's own counts in CPU
cycles, not by the SDRAM. The EXP1 path is a stub today (memorymux.vhd:955,
"nothing connected"), so the flash figures are what the stub would charge
with the games' delay register, not a model of the board's flash.

## Measurement 3: sdram.sv request strobe at a 2:1 ratio (2026-10-05)

Same testbench, clk_1x at 50.8032 MHz and the SDRAM clock unchanged at
101.6064 MHz (option c2: 2:1).

| Variant | clk3xIndex pulses | Result |
|---|---|---|
| r3: 3:1, sdram.sv as is | 238,149 in 238,148 cycles | all 18 rows complete, 0 data errors |
| r2: 2:1, sdram.sv as is | 0 in 15,841 cycles | request lost at sample 228 of the first row: the CPU waited 2,000 cycles for ram_done and the controller only issued refreshes |
| r2fix: 2:1, generator `clk3xIndex <= clk1xToggle3X == clk1xToggle` (sim copy only) | 252,722 in 252,721 cycles | all 18 rows complete, 0 data errors |

Yes, a request gets lost. The trace of the lost request (DEBUG run of r2):
ram_ena was high for its two SDRAM clock edges exactly while the engine
issued AUTO REFRESH (two refresh commands, one per chip), so STATE_IDLE never
saw ch1_req (sdram.sv:441), and ch1_rq, the latch for a busy engine
(sdram.sv:238), is only set when clk3xIndex is 1, which at 2:1 it never is.
The first 228 reads worked because they found the engine idle. In the core
this is a hang: memorymux waits for ram_done forever. Any busy engine causes
it: refresh, a DMA FIFO write, or the tail of the previous access.

Why: the generator compares the clk_1x toggle with a copy two SDRAM cycles
old. At 3:1 that copy equals the current toggle on exactly one edge per
clk_1x cycle, and the registered index is 1 at the first SDRAM edge after
each clk_1x edge, where it captures the request once. (Section 1.2 placed it
on the last edge before the next clk_1x edge; the first edge after is
correct.) At 2:1 the two-cycle-old copy always differs, so the index never
fires. The one-stage compare fires on the first edge after each clk_1x edge
at 2:1, but at 3:1 it fires twice per cycle and captures requests twice
(check variant r3fix: 124,971 pulses in 62,485 cycles, 100 data errors), so
it is ratio-specific, not a drop-in for both.

| Access | 3:1 (33.8688 MHz CPU) | 2:1 with r2fix (50.8032 MHz CPU) |
|---|---|---|
| RAM LW, isolated | 5 cycles = 147.6 ns | 7 cycles = 137.8 ns |
| RAM LW right after a read | 4 | 7 |
| Cache line miss, mem_done / last word | 5 / 5.33 | 7 / 8.0 |
| BIOS fetch / LW / LH / LB | 31-32 / 31 / 15 / 7 | 33-34 / 33 / 17 / 9 |
| RAM SW busy (after read / same page / other page) | 4 / 3 / 7 | 4 / 3 / 7 |
| RAM LW right after an SW | 5 | 7 |
| EXP1 LW / LH / LB, SPU LH | 29 / 15 / 15, 6 | unchanged in cycles |
| Refresh penalty, max | +2 | +3 |

Consequences for the open decisions:

- SDRAM controller changes (step 3): at 2:1 the sdram.sv index generator
  must change, behind a ratio generic (one-stage compare at 2:1, the
  two-stage one at 3:1). The DMA FIFO write strobe uses a copy of the same
  generator (psx_top.vhd:723-734, consumed at dma.vhd:979) and would never
  write DMA data to the SDRAM at 2:1 (reading, not simulated); it needs the
  same change. Refresh constants and CAS latency stay, because the SDRAM
  clock stays at 101.6064 MHz in (c2). (Superseded 2026-10-05: the SDRAM
  clock becomes exactly 100.000 MHz, the rate sdram.sv's constants are
  written for, sdram.sv:96-102; the 2:1 cycle counts above are unchanged.)
- Calibration (step 4): at 2:1 a RAM read costs 7 CPU cycles instead of 5
  (slightly less real time, 137.8 against 147.6 ns), a cache line 7 to 8
  instead of 5, BIOS reads 2 more cycles. EXP1 (flash) and SPU accesses are
  counted by memorymux in CPU cycles, so they become 1.5x faster in real
  time at 50.8032 MHz (flash LW 571 ns instead of 856 ns). The loader
  reads flash about 500,000 times (docs/r1_speed_study.md, 2), so the
  flash wait states are a calibration item of their own once the G-NET
  flash glue replaces the stub.
- CPU rate (decision 1): none of the three measurements separates 50.8032
  from 50.000 MHz. The index change is the same at an exact 2:1 ratio for
  both (100 and 50 MHz from one PLL); 50.000 MHz needs the counter phase
  accumulator (1c) and asynchronous crossings, 50.8032 MHz needs neither.
  The SPU read protocol (1a) shows the board itself synchronises SPU reads
  in hardware, which supports building the SPU crossing async-safe as
  section 4 recommends.

## Decisions recorded (Lee, 2026-10-05)

Lee accepted the recommendations for the 50.000 MHz plan:
1. Root counters and SIO0 tick source: 33.8688 MHz equivalents from the
   phase accumulator (modulo 15625, add 10584 per 50 MHz cycle; tick_accum
   on branch r1-cdc), so raycris's counter 2 sound tick stays at 240 Hz.
2. SPU register reads: a plain stall handshake across the clock crossing
   (no prefetch until board evidence on 0x1fa60000 exists).
3. Reset zero fill of RAM and scratchpad: kept, done by a CPU-side filler.
4. GTE: 2x at 100 MHz with GTE_NARROW_MUL = 3 (E6 met 10 ns with +1.536 ns
   on seed 1; seeds 2 and 3 pending). Fallback if E6 does not hold across
   seeds: the CPU-side busy counter with the GTE at 80 MHz.

## Step: fast-clock ratio generic (2026-10-05)

Branch r1-clk-ratio. Selectable logic only: no clock, PLL or SDC changed.

What I changed:

| File | Change |
|---|---|
| PSX.sv:961-969 | macro `GNET_CLK_RATIO2` sets `GNET_CLK_FAST_RATIO` to 2, otherwise 3; passed to psx_mister (PSX.sv:980) and to the main `sdram` instance (PSX.sv:1303) |
| rtl/psx_mister.vhd:17, 318 | generic `CLK_FAST_RATIO` (default 3), passed to psx_top |
| rtl/psx_top.vhd:22, 724-743 | generic `CLK_FAST_RATIO` (default 3); the clk3xIndex generator that gates the DMA FIFO write strobe (dma.vhd:979) compares with the one-cycle-old toggle copy at 2 and the two-cycle-old copy at 3; a concurrent assert rejects other values |
| rtl/sdram.sv:22-27, 242-244 | parameter `CLK_FAST_RATIO` (default 3), the same selection for the request index |

At the default the 3 branch is the upstream statement unchanged and the 2
branch sits behind a constant-false condition, so synthesis builds the
upstream logic. dma.vhd needs no change: it only consumes the index. The
second SDRAM instance (sdram2, SPU RAM, PSX.sv:1375) keeps the default,
because its clk_base is clk_1x (PSX.sv:1392), which stays at 33.8688 MHz in
the (c2) plan. A `GNET_CLK_RATIO2` build on today's 3:1 clocks does not run
correctly (the 2:1 strobe fires twice per cycle at 3:1, see r3p2 below).

Bench (tools/r1/mem_lat): run.sh now takes variants `r<C>[p<P>][d]`, with C
the clock ratio the bench makes, P the RTL `CLK_FAST_RATIO` (default 3) and d
for the DMA phase alone. The sdram.sv copy keeps the parameter (the --fix21
patch of Measurement 3 is gone); `psx_top_index_copy.py` copies psx_top's
generator text into a small entity, so dma.vhd runs with the generator as
written. After the latency rows the bench now runs the unmodified dma.vhd:
an OTC of 2048 words (channel 6, RAM writes through the DMA output FIFO and
sdram.sv's dmafifo port), a CPU read-back of all 2048 words, and a GPU DMA
(channel 2, RAM reads through ch1 with ch1_dma) that streams the table out
and is checked word by word. It also counts RAM requests presented in a
clk_1x cycle in which the controller issued AUTO REFRESH (the case that lost
a request in Measurement 3), and compares sdram.sv's index with psx_top's on
every SDRAM edge. NREP 400 unless noted.

| Variant | Latency rows | Row data errors | DMA OTC: words into the FIFO / into the SDRAM, read-back | GPU DMA | Requests in a refresh cycle |
|---|---|---|---|---|---|
| r3 (3:1, default) | 18 of 18; mem_lat.txt identical to the run before the change, apart from the new lines | 0 | 2048 / 2048, 0 errors | 2048 words, 0 errors | 54, none lost |
| r2p2 (2:1, `CLK_FAST_RATIO` 2) | 18 of 18; rows identical to Measurement 3's r2fix | 0 | 2048 / 2048, 0 errors | 2048 words, 0 errors | 67, none lost |
| r3, NREP 2000 | 18 of 18 | 0 | 2048 / 2048, 0 errors | 2048 words, 0 errors | 170, none lost |
| r2p2, NREP 2000 | 18 of 18 | 0 | 2048 / 2048, 0 errors | 2048 words, 0 errors | 217, none lost |
| r2 (2:1, default 3) | lost at sample 228 of row 1, as in Measurement 3 | | | | |
| r2d (2:1, default 3, DMA only) | skipped | | 0 / 0: the FIFO is never written; all 26 words read before the CPU read hangs (word 26) are wrong | not reached | |
| r3p2 (3:1, `CLK_FAST_RATIO` 2) | 18 of 18 | 410 | 4096 / 4096: every word written twice; 1,983 read-back errors | 2048 words, 0 errors | |

In every run that reached the DMA phase, sdram.sv and psx_top fired on the
same SDRAM edges (0 mismatches), and with the matching setting once per
clk_1x cycle (r2p2: 274,559 pulses in 274,558 cycles). So the 2:1 setting
makes both strobes work, including requests that meet a refresh, and the
default keeps 3:1 as before. r2d confirms the reading in Measurement 3 that
the upstream DMA strobe never writes at 2:1. In CPU cycles the GPU DMA of
2048 words takes 3,102 cycles at 2:1 against 2,182 at 3:1 (the OTC takes
2,189 at both, paced by dma.vhd's REP timing counters): one more calibration
item for step 4.

Not checked here: psx_top.vhd, psx_mister.vhd and PSX.sv as a whole (only
the copied generator is compiled; the generics and the macro are plain
pass-through; Verilator lint, style warnings off, passes sdram.sv at both parameter values).
Revision GNET_B1R2 (GNET_B1 plus `GNET_CLK_RATIO2`, target b1r2 in
tools/pc_build.sh) would check synthesis and area on today's clocks; not run.

## CDC building blocks (step 3 of the 50.000 MHz plan, 2026-10-05)

Branch r1-cdc. Reusable crossing entities in VHDL, simulated with NVC 1.23;
none is connected to psx_top yet, and nothing has been through Quartus.

Files: rtl/gnet/cdc/ (cdc_pkg.vhd, cdc_sync.vhd, cdc_capture.vhd,
cdc_pulse.vhd, cdc_handshake.vhd, cdc_bus_sync.vhd, cdc_fifo.vhd,
tick_accum.vhd, cdc.qip, cdc.sdc, cdc_syn_top.vhd); benches in sim/cdc/
(tb_*.vhd, cdc_tb_pkg.vhd, run.sh, summarize.py).

| Entity | For | What it does |
|---|---|---|
| cdc_sync | C4, C5, C7, C11, C13, C14, C16, C17, C20 | WIDTH independent bits, STAGES flip-flops (default 2) in the destination clock |
| cdc_bus_sync | quasi-static groups (C16 words, C20) | Vector that always arrives whole: each change is sent through cdc_handshake; values faster than a round trip are skipped, the last value always arrives, dst_update marks each new value |
| cdc_pulse | C6, C12, C15, C19 | One destination pulse per source pulse. The source keeps a Gray event counter (CNT_W bits); the destination emits one pulse per cycle while its own count differs. CNT_W = 1 is the toggle synchroniser (source pulses at least one destination period plus the aperture apart); CNT_W > 1 queues bursts |
| cdc_handshake | C2, C9, C10, C18 | Two-phase request/acknowledge with REQ_W bits of request and RSP_W bits of response, both held by the sending side and captured by the receiving side only after the toggle has been synchronised |
| cdc_fifo | C1, C3, C8 | Dual-clock FIFO, 2**ADDR_W x DATA_W, Gray pointers through cdc_sync, inferred RAM with a RAM_STYLE generic (ramstyle "M10K, no_rw_check", "MLAB, no_rw_check", ...), FWFT or normal read, counts on both sides, overflow and underflow flags |
| tick_accum | P3 | Phase accumulator, MODULUS 15625, INCREMENT 10584 by default, tick registered, '0' while ce = '0' |

Conventions: every register whose output crosses is named cdc_tx_*, every
register that samples a crossing signal is cdc_rx_s1 (first synchroniser
stage, later stages cdc_rx_sn) or cdc_rx_hold (handshake data capture).
The chain registers carry altera_attribute "-name
SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS; -name
DONT_MERGE_REGISTER ON; -name PRESERVE_REGISTER ON" (the assignments of
Intel's altera_std_synchronizer) and preserve; cdc_tx_* and cdc_rx_hold
carry DONT_MERGE_REGISTER and PRESERVE_REGISTER. The two sides of each
entity have separate synchronous resets that must be applied together
(C17's job).

Simulation model (generic SIM_META_WINDOW, removed by translate_off for
synthesis): a cdc_rx_* register that samples a bit which changed less than
the window before the edge takes the old or the new value at random, per
bit. That is the "synchroniser that randomly adds a cycle" of gate 3, and
it turns any multi-bit skew into a visible error: a binary pointer or
unsynchronised data then reads as a mix of old and new bits. The FIFO's
RAM model returns X for a slot fetched less than the window after its
write, and for the window after a write into the slot being shown. The
benches set the window to 0.9 x the shorter period.

### Verification

Benches (sim/cdc/run.sh all, 2 runs at a time under nice -n 15): 10
directed clock pairs, both directions of 50.000/33.8688, 100.000/67.7376,
50.000/67.7376, 100.000/33.8688 and 50.000/53.693175 MHz (periods 20,
10, 29.525699, 14.762850, 18.624341 ns, jitter-free, random start phase
per run), each with the model off and on, 2 seeds, 50,000 transfers per
run. Checks per bench:

- cdc_sync: random holds of at least one destination period plus the
  window; every change seen once, in order, latency inside the bound.
- cdc_pulse: CNT_W = 1 with pulses spaced at the toggle limit up to 12
  source cycles more; CNT_W = 4 with bursts of 1 to 8 back-to-back source
  pulses. No pulse lost, none duplicated (destination count never ahead of
  the source, equal at the end).
- cdc_handshake: 32-bit request and response payloads with a check field,
  random gaps, device delay 0 (acknowledge combinational from dst_valid) to
  4 cycles; every request seen once in order with its data, every response
  returned with its data.
- cdc_bus_sync: 24-bit words (sequence plus check field) held 1 to 3
  cycles or longer than a round trip; no torn word, sequence only
  increasing, dst_data changes only with dst_update, destination equal to
  the source after every long hold.
- cdc_fifo (16 x 34, FWFT and normal): push and pop rates that change every
  20 to 400 cycles, pushes attempted while full and pops while empty, quiet
  windows of 1.5 us every 25 us. Data and order; wr_count never below and
  rd_count never above the true count; full and empty consistent with the
  counts; overflow and underflow flags; exact counts at the end of each
  quiet window. Every run reached wr_count 16, and every run had at least
  8,531 full cycles, 6,493 pushes refused, 7,694 empty cycles and 6,181
  pops refused.
- Extra (part of all, model on only): FIFO 8 x 27 and 2 x 8 in both read
  modes, cdc_sync and cdc_handshake with STAGES = 3, on 6 pairs.
- tick_accum: 1,000,000 cycles with ce always on: 677,376 ticks, every one
  of the 984,376 windows of 15,625 consecutive cycles holds exactly 10,584
  ticks, spacing 1 or 2 cycles. With random ce (about 70%): the same over
  1,000,000 ce cycles, and no tick after a cycle with ce = '0'.

Result: 318 runs, 0 errors, 0 timeouts. Transfers: cdc_sync 2,000,000
(plus 300,000 with 3 stages); cdc_pulse 2,000,000 spaced (CNT_W 1) and
2,000,000 in bursts (CNT_W 4); cdc_handshake 2,000,000 (plus 300,000
with 3 stages); cdc_bus_sync 2,000,000 source changes, of which 1,197,471
reached the destination (the rest were skipped by design); cdc_fifo
2,000,000 words per read mode at 16 deep plus 600,000 at 8 and 2 deep.
Raw lines: sim/cdc/work/results.txt; `python3 sim/cdc/summarize.py` groups
them by block, pair and model.

Negative controls (sim/cdc/run.sh neg, model on, 20,000 transfers, pairs
50/33.8688 and 100/33.8688 both ways):

| Control | Caught |
|---|---|
| FIFO with binary instead of Gray pointers | 4 of 4 pairs (5,024 to 5,960 errors) |
| FIFO without pointer synchroniser (STAGES = 0) | 4 of 4 (244 to 12,970) |
| Handshake without synchroniser | 4 of 4 (20,629 to 31,355) |
| Bus sync without synchroniser | 4 of 4 (2,273 to 22,377) |
| Toggle pulse synchroniser (CNT_W = 1) under bursts | 3 of 4 (18% to 71% of pulses lost). At 33.8688 to 100 MHz back-to-back source pulses are 29.5 ns apart, more than one destination period plus the window (19 ns), so the toggle condition holds and nothing is lost, as expected |
| FIFO normal mode releasing the slot on the pop edge (NEG_EARLY_FREE) | 100 to 33.8688 MHz: 5,629 errors (26,728 in a 50,000-word run with the model off). The other three pairs pass, as expected: the writer needs 2 to 3 of its own periods after the release before it can write, which beats the reader's next edge only when the reader period is more than about twice the writer's |

The last row is a defect I found and fixed while writing the bench: the
FIFO reads its RAM from a registered address, the form an MLAB read has,
so in normal mode a writer at 100 MHz could overwrite the slot of a word
popped at 33.8688 MHz before the reader's next edge took it. Normal mode
now releases the slot one read cycle after the pop. FWFT never had the
problem (the shown word's slot stays allocated until it is popped). For
cdc_sync a removed stage cannot be shown in RTL simulation (it costs MTBF,
not function); that is for STA (synchroniser identification and the MTBF
report) on the first fit. A binary counter in cdc_pulse is not a useful
control either: the destination consumes at most one event per cycle and
only while it lags, so a garbled sample only shifts a pulse by a cycle; I
kept Gray coding anyway.

### Latency

Counted in destination clock edges after the source clock edge that
launches the transfer, up to the edge that updates the output (a
registered consumer acts on it one edge later). "Late" is the model on.
Every pair above gave the same edge counts; only the time in ns depends on
the pair (output change between k - 1 and k destination periods after the
source edge for k edges, plus one period when late).

| Block | Output | Edges | Late |
|---|---|---|---|
| cdc_sync, STAGES 2 | q | 2 | 2 to 3 |
| cdc_sync, STAGES 3 (model on only) | q | 3 | 3 to 4 |
| cdc_pulse, CNT_W 1 or 4 (isolated pulse) | dst_pulse | 2 | 2 to 3 |
| cdc_bus_sync | dst_data, dst_update | 3 | 3 to 4 |
| cdc_handshake request | dst_valid, dst_req_data | 3 | 3 to 4 |
| cdc_handshake response (source edges after the edge that takes dst_ack) | src_done, src_rsp_data | 3 | 3 to 4 |
| cdc_handshake, STAGES 3 (model on only) | request / response | 4 / 4 | 4 to 5 |
| cdc_fifo FWFT (word written into an empty FIFO) | rd_empty low, word on rd_data | 3 | 3 to 4 |
| cdc_fifo normal | rd_empty low (data one edge after rd_en) | 2 | 2 to 3 |

Handshake round trip with the device answering at once (dst_ack
combinational from dst_valid), in source cycles from the edge that takes
src_start to the edge that raises src_done:

| Source to destination (MHz) | Plan item | Cycles | Late | ns |
|---|---|---|---|---|
| 50 to 33.8688 | C2, C9 | 7 to 8 | 7 to 10 | 140 to 200 |
| 50 to 67.7376 | C18 | 5 | 5 to 7 | 100 to 140 |
| 50 to 53.693175 | | 5 to 6 | 5 to 8 | 100 to 160 |
| 100 to 33.8688 (100 MHz cycles) | | 11 to 14 | 11 to 16 | 110 to 160 |
| 100 to 67.7376 (100 MHz cycles) | | 7 to 8 | 7 to 10 | 70 to 100 |
| 33.8688 to 50 | | 5 | 5 to 6 | 147.6 to 177.1 |
| 33.8688 to 100 | | 4 | 4 | 118.1 |
| 53.693175 to 50 | | 6 to 7 | 6 to 9 | 111.7 to 167.6 |
| 67.7376 to 50 | | 7 to 8 | 7 to 10 | 103.3 to 147.6 |
| 67.7376 to 100 | | 5 | 5 to 6 | 73.8 to 88.5 |

Against P2: a C2 or C9 read costs 7 to 10 CPU cycles plus the device time
(the plan estimated 7 to 9, 12 worst, with about 2 clk_1x cycles of device
side); a posted GPU or SPU word is readable on the clk_1x side after clk_1x
edge 3 (4 when late) from the CPU's write edge, 59 to 118 ns or 3 to 6
CPU cycles (the plan said 4 to 7).

### SDC and synthesis check

rtl/gnet/cdc/cdc.sdc is sourced after derive_pll_clocks: set_max_delay
8.0 ns and set_min_delay -100 ns on every cdc_tx_* to cdc_rx_* path, and
per instance set_max_skew 5.0 ns plus set_net_delay -max 5.0 ns on the
Gray buses (cdc_tx_wptr, cdc_tx_rptr, cdc_tx_cnt to their cdc_rx_s1). This
differs from P2 in two points: Quartus has no -datapath_only (that is a
Vivado option), so the 8 ns includes the clock tree difference; and I put
first synchroniser stages under the same max delay instead of a false path,
because in Quartus a false path overrides set_max_delay on the Gray buses.
The file has not been run through Quartus (needs-review).

GNET_CDC_FIT (top cdc_syn_top: FIFOs 16 x 34 and 8 x 27 in MLAB, 1024 x 32
in M10K, a 32/32 handshake, an 8-bit bus sync, a 4-bit level group, pulse
synchronisers with CNT_W 1 and 4, tick_accum; ports virtual, clocks 20 ns
and 29.525 ns, sources cdc.sdc) is ready as target cdcfit in
tools/pc_build.sh, not run. It answers: whether Quartus 17 infers the
two-clock MLAB and M10K FIFOs as intended, whether cdc.sdc parses and
applies, the ALM count, and the synchroniser MTBF report.

## Steps 4 and 5: CPU group at exactly 50.000 / 100.000 MHz (2026-10-05)

Branch r1-cpu50 (from main 677bfd1, with r1-clk-ratio, r1-cdc and
gte-mac-100 merged). RTL, simulation and a Quartus revision; nothing has
been through Quartus. Line numbers are this branch.

### What I built

| Item | Where |
|---|---|
| psx_top generic `CPU_CLK_SPLIT` (default 0) and clock ports clk_cpu, clk_cpu2x, clk_cpu3x | rtl/psx_top.vhd:29, 37-42 |
| CPU group moved to the new ports: memctrl, sio, irq, dma (clk_cpu3x, clk3xIndex_c), timer (sys_tick), exp2, memorymux (clk_cpu, clk_cpu2x), cpu (clk_cpu, clk_cpu2x, clk_cpu3x), gte (clk2xIndex_c); the bus, ce, error-code and RAM-glue processes | rtl/psx_top.vhd:832, 858, 918, 1382, 1478, 1500, 2132 and the port maps |
| PS1-group copies (suffix _p) of every signal that crosses, wired to gpu, spu, the savestates engine and the DDR3 arbiter | rtl/psx_top.vhd:707 onwards (signals), 971 (arbiter reset), the igpu, ispu and isavestates port maps |
| `gsplit0`: plain copies, upstream wiring | rtl/psx_top.vhd:2404 |
| `gsplit1`: rtl/gnet/cpu_split as a component (builds without the split need none of its files), asserts on the LEAN trims and CLK_FAST_RATIO = 2 | rtl/psx_top.vhd:2477-2612 |
| Crossing layer, built from cdc_sync, cdc_pulse, cdc_bus_sync, cdc_fifo, cdc_handshake and tick_accum (r1-cdc) | rtl/gnet/cpu_split/cpu_split.vhd |
| GPU bridge (C1 to C5) | rtl/gnet/cpu_split/cpu_gpu_bridge.vhd |
| SPU bridge (C8 to C11) | rtl/gnet/cpu_split/cpu_spu_bridge.vhd |
| Reset pulse ordering and the CPU-side zero fill (C17, decision 3) | rtl/gnet/cpu_split/cpu_reset_fill.vhd |
| memorymux: port `bus_spu_stall` (default '0') holds EXT_READ_NEXT | rtl/memorymux.vhd:134, 1268-1270 |
| dma.vhd: `DMA_SPU_readStall` (default '0') gates the channel 4 read, `DMA_SPU_readReq` is the ungated request | rtl/dma.vhd:78-79, 228-232 |
| timer.vhd: `sys_tick` (default '1') for the system clock sources and the /8 prescaler | rtl/timer.vhd:13, 153, 171, 179, 183, 187 |
| savestates.vhd: generic `CPU_FILL_EXT` (default 0); with 1 types 12 and 16 go to the CPU-side filler through a toggle handshake, and CPU-group state is not read | rtl/savestates.vhd:15, 91-92, 267, 327, 605-619 |
| psx_mister.vhd: `CPU_CLK_SPLIT` and the three clocks passed through | rtl/psx_mister.vhd:18, 26-30, 325, 333-335 |
| PLL: 50.000 and 100.000 MHz from CLK_50M, integer mode, direct, phase 0 on both outputs | rtl/gnet/pll_cpu.v |
| PSX.sv macro `GNET_CPU50`: pll_cpu, reset held until its lock, clocks to psx_mister, SDRAM on clk_cpu2x / clk_cpu, channel 3 (downloads, cheats) through a cdc_handshake from clk_1x | PSX.sv:68-84, 222-228, 995-999, 1019-1027, 1343-1376, 1393-1401, 1430-1446 |
| Revision GNET_CPU50_B1 (GNET_B1 with GNET_CPU50, GNET_CLK_RATIO2, GNET_GTE_NARROW_MUL=3), its SDC, pc_build target cpu50b1 (DIR gn_cpu50b1, TASK gncpu50b1) | GNET_CPU50_B1.qsf, GNET_CPU50_B1.sdc, tools/pc_build.sh |

The default build: every new generic and port defaults to the upstream
behaviour, and with `CPU_CLK_SPLIT = 0` the instantiator connects the same
signals to clk_cpu, clk_cpu2x and clk_cpu3x as to clk1x, clk2x and clk3x
(PSX.sv:1024-1026, sim/system/src/tb/tb.vhd), so every moved process and
instance is clocked by the same net as before. The _p copies are concurrent
assignments of data signals only (no clock passes through an assignment),
so simulation sees the same values at every edge. In the copy of GNET_B1.qsf
the macro `GNET_GTE_NARROW_MUL=1` is replaced by `=3`, not added, because a
second definition of the same macro would conflict; the other lines are
byte-identical apart from the header comment and the appended lines.

### Crossings as built

| # | How | Notes |
|---|---|---|
| C1, C2 | One command FIFO (cdc_fifo, 32 x 38, FWFT, M10K requested) carries GP0, GP1, DMA words and reads in order. A PS1-side proxy replays each entry for one clk1x cycle with ce on gpu.vhd's own ports. Reads: c_bus_stall from the edge after the read cycle (as gpu.vhd sets bus_stall); the answer returns through a cdc_handshake (34 bits); then one ce cycle of data and the stall drops | cpu_gpu_bridge.vhd:224, 237, 262, 289, 318 |
| C3 | Fetch on demand: while the DMA's readEna is high and no word is buffered, a fetch goes through the FIFO; the proxy pops gpu.vhd's read FIFO only if gpu_dmaRequest is high and returns the word or "empty". gpu_dmaRequest to dma.vhd is the buffer state while readEna is high, so dma.vhd's existing channel 2 readStall holds the DMA | cpu_gpu_bridge.vhd:227. Simpler than the plan (no dual-clock vram2cpu FIFO, no gpu.vhd change), one word in flight, so VRAM to CPU DMA is slow (about one word per 15 CPU cycles); step 0.5 is still open |
| C4 | GPU request through 2 FF, held low until the command FIFO has been empty for 8 CPU cycles | cpu_gpu_bridge.vhd:205, 227 |
| C5, C16 | ce, pausing, pausingSS, cpuPaused, dmaOn, DMA_GPU_waiting and the CPU-group idle flag registered on clk_cpu, 2 FF into clk1x; allowunpause, GPU and SPU idle, savestate_pause, loading_savestate, hblank, vblank, irq_VBLANK and the 7 error flags registered on clk1x, 2 FF into clk_cpu. The GPU and SPU idle flags on the CPU side and the CPU idle flag for the engine are ANDed with "bridge empty" | cpu_split.vhd:314, 340, 350 |
| C6, C12, C15 | Rising edge in the source domain (clk2x for irq_GPU, clk1x for irq_SPU and the dot clock), cdc_pulse with CNT_W 2 | cpu_split.vhd:366, 380, 384. The dot clock is gpu.vhd's clk1x copy (what the timer sees today), not the clk_vid pulse the plan proposed: no gpu.vhd change, and today's possible misses stay as they are |
| C7, C13, C14 | Levels as in C16 | |
| C8 to C11 | As C1 to C4 for the SPU, FIFO 64 x 28. The read holds memorymux in EXT_READ_NEXT through bus_spu_stall (combinational: read and no answer yet), so the data is taken in EXT_READ as today (my decision 2). Channel 4 DMA reads stall in dma.vhd until a halfword is fetched (an empty SPU FIFO answers 0, spu.vhd's value today) | cpu_spu_bridge.vhd:209-213, 299 |
| C17 | The engine stays on clk1x/clk2x and still sequences GPU, SPU RAM and VRAM. Its SS_reset and reset_out pulses reach clk_cpu through two cdc_pulse; cpu_reset_fill issues SS_reset, then reset, never in one cycle. The PSX.sv reset and pause levels are registered on clk1x and synchronised; reset_exe goes back as a pulse. Zero fill: the engine toggles ext_fill_req at type 12 and waits; the filler writes 256 scratchpad words and 524,288 RAM words through the modules' own savestate ports while ce = '0', then toggles back (decision 3) | cpu_split.vhd:238-275, cpu_reset_fill.vhd:72, 93, 122 |
| C18, C19 | Not on this branch: the card memory port and the card download are zn2-layer code | |
| C20 | Static configuration from PSX.sv: false path from the emu-level clk_1x registers to the CPU clocks; channel 3 of the SDRAM crosses in a cdc_handshake in PSX.sv | GNET_CPU50_B1.sdc, PSX.sv:1356 |
| P3 | tick_accum on clk_cpu with ce, reset by the CPU-side reset pulse; timer.vhd counts the system clock sources and the /8 prescaler on sys_tick | cpu_split.vhd:389, rtl/timer.vhd:153-187 |

`hps_io` and the download logic stay on clk_1x, unlike the plan's P1
proposal (risk 8 in P5): only channel 3 of the SDRAM had to cross, and the
framework blocks keep their 33.8688 MHz clock.

For the zn2-layer merge: zn2_board, zn_sio0 and zn2_cardmem are
instantiated there on clk1x with ce and reset_intern. With CPU_CLK_SPLIT = 1
zn2_board belongs on clk_cpu with CLK_HZ 50,000,000, zn_sio0 needs
`sys_tick` (signal in psx_top, rtl/psx_top.vhd:716), and zn2_cardmem needs
the C18 handshake. memorymux.vhd, psx_top.vhd and PSX.sv conflict where both
branches edit the same lines (the end of the generic list, the memorymux
port map, the end of the memorymux port list); each conflict is a union of
both edits. zn2-layer's `zn_stall` (in ext_done) and my `bus_spu_stall` (a
hold of EXT_READ_NEXT) do not touch the same statement.

### SDC (GNET_CPU50_B1.sdc)

It sources rtl/gnet/cdc/cdc.sdc (8 ns on cdc_tx_* to cdc_rx_* paths, Gray
skew), cuts clk_vid and the framework clocks from the two CPU clocks, and
false-paths the quasi-static emu-level registers (status bits, EXE header,
TURBO flags, BIOS region) into the CPU clocks, excluding the SDRAM
controller and the channel 3 handshake. Every crossing in rtl/gnet/cpu_split
starts at a register named cdc_tx_*, so no other path between the groups
should exist. GNET_LEAN.sdc stays in the revision for clk_vid against the
emu PLL.

### Verification (NVC 1.23, every simulation under nice -n 15, at most 2 at a time)

1. mem_lat bench at exactly 20 / 10 ns (`T_FAST=10ns tools/r1/mem_lat/run.sh
   r2p2`, new T_FAST option): 18 of 18 rows, 0 data errors, DMA OTC 2048 /
   2048 words and GPU DMA 2048 words with 0 errors, sdram.sv and psx_top
   strobes 0 mismatches; min, max and mean of every row identical to
   Measurement 3's r2fix at 9.842 ns. The default r3 run gives rows identical
   to the Measurement 2 run in the main checkout (the memorymux and dma.vhd
   edits do not change it).
2. Crossing bench `sim/cpu50/run.sh split 4000` (sim/cpu50/tb_cpu_split.vhd):
   models of memorymux, dma.vhd, gpu.vhd and spu.vhd around cpu_split; 4
   clk1x phases x 2 seeds, CDC metastability model on (9 ns) and off: 16
   runs, 0 errors. Totals: 29,575 GPU register writes; 21,851 GPU reads
   (GPUSTAT returns the number of writes issued before it, GPUREAD with random
   not-ready stalls); 51,630 DMA words to the GPU (one per cycle); 136,335 DMA
   words from the GPU; SPU 28,474 writes and 26,130 reads (each read checked
   against the last value written); 38,411 and 59,879 DMA halfwords in and
   out; 193,944 irq_GPU, 247,753 irq_SPU and 528,489 dot clock pulses, 3,748
   SS_reset and 4,835 reset pulses, none lost or added; SS_reset always
   before its reset; 10,584 ticks in the first 15,625 cycles; zero fill of
   256 + 4,096 words in order. ce pauses as psx_top makes them (bus idle).
   Read latency from the read cycle to the data cycle: GPU 15 to 51 CPU
   cycles (51 includes the model's not-ready stalls), SPU 15 to 22 (2 today).
   Without the model, phases 3 ns and 23 ns are the same alignment (23 = 3 +
   one CPU period) and give identical results.
3. Negative controls (`run.sh neg`, sim/cpu50/mutants.py): GPU proxy ignoring
   gpu.vhd's stall: 168 errors; no SPU stall: 769; no quiet window on
   gpu_dmaRequest: 9,040 (FIFO overflow, lost words); fill ignoring
   ram_done: 1,456. A fifth mutant (reset not held back behind a same-cycle
   SS_reset) has no valid stimulus: the engine's pulses are 29.5 ns apart,
   more than one CPU period plus the 9 ns window, so they cannot arrive in
   one cycle; the hold-back is defensive.
4. GPU replay through the crossing (`run.sh replay`, sim/cpu50/replay_split.py
   turns sim/m1/tb_gpu_replay.vhd into a bench whose feeder runs at 50 MHz
   against cpu_gpu_bridge with the metastability model on): ps1-tests quad
   (127 words), triangle (44), transparency (424) and lines (1,121): VRAM at
   frame 3 byte-identical to the direct replay dumps of docs/m1_gpu_zn2.md 2d.
5. System smoke test (`run.sh system`, sim/cpu50/gen_system_tb.py,
   smoke_prog.py): the full psx_top (LEAN trims, GTE_NARROW_MUL 3, 2 MB
   VRAM) with sdram.sv (simulation copy), an SDRAM chip model holding a
   67-word MIPS program as BIOS and a DDR3 model, once with CPU_CLK_SPLIT = 0
   (33.8688 MHz, SDRAM 3:1) and once with 1 (50 / 100 MHz, PS1 clocks started
   7 ns later). Reset sequence (FASTSIM), then GP1 reset, four GP0 commands
   ending in a fill rectangle, GPUSTAT, two SPU register write and read
   pairs, timer 2 around a loop, GP0 C0h with one GPUREAD, and RAM stores of
   every result. Final RAM values identical: GPUSTAT 0x14800000, SPU 0x1234
   and 0xBEEF, GPUREAD 0x001F001F (the two red pixels); done marker at 547.9
   us (split 0) and 460.2 us (split 1). Timer 2 counted 9,851 ticks over the
   loop at split 0 and 7,086 at split 1 (the loop's BIOS fetches are waits in
   CPU cycles, so it runs faster in real time at 50 MHz).
   With the split the program's first RAM store ran twice: after the engine's
   first reset the CPU kept running until 133.3 us (31 us after reset
   release), because the ce process's pause condition (memorymux idle, no
   stall, SS_idle) did not hold in one cycle while the CPU ran uncached BIOS
   code and the SPU idle flag was low; the engine's 1023-cycle retry reset
   the CPU twice before the pause took, and the final reset restarted the
   program. At split 0 the CPU paused before its first store. Timing only,
   and the same retry exists upstream (needs-review: how long the OSD pause
   and reset take with the real BIOS).
6. `run.sh top`: psx_top analysed with every RTL file and elaborated with
   CPU_CLK_SPLIT 0 (upstream generics) and 1 (LEAN, ratio 2, GTE 3, 2 MB
   VRAM). PSX.sv itself is not simulated or linted here; the GNET_CPU50 code
   is checked by reading and will be checked by Quartus on the first fit.

### Expected ALMs (estimate, mine)

GNET_B1 fitted at 27,709 ALMs with GTE_NARROW_MUL 1 (cpu_rate_probe.md). E6
(GTE_NARROW_MUL 3 on the LEAN base) fitted at 26,802 against the LEAN
probe's 27,534, so the GTE change is about -700 ALMs; B1 against M1_2MB
(27,486) puts GTE_NARROW_MUL 1 at +223. From register and multiplexer counts
the new logic is about 300 to 500 ALMs (GPU bridge 110 to 170, SPU bridge 70
to 110, channel 3 handshake 50 to 100, levels, pulses, filler, tick and index
generators 60 to 100) plus 2 M10K for the command FIFOs, below the plan's 540
to 900 because C3 and C10 are simpler and C18 and C19 are not here. Expected
total: about 27,300 to 27,800 ALMs (65 to 66% of 41,910); PLLs 5 of 6.

### Risks and needs-review (for the first fit)

| # | Item |
|---|---|
| 1 | Clock names in GNET_CPU50_B1.sdc (`emu|pll_cpu|altera_pll_i|general[0/1]...`) and the PLL settings Quartus picks: check the TimeQuest clock list and the fit report's PLL summary |
| 2 | Whether Quartus builds the command FIFOs in M10K (dual clock, registered address). In MLAB or registers their write-to-read path crosses clocks and needs the 8 ns bound (comment 4 in the SDC) |
| 3 | Unconstrained cross-group paths: any path between {clk_cpu, clk_cpu2x} and {clk_1x, clk_2x, clk_3x} that does not start at cdc_tx_* is a design error; tools/sta/xclk_query.tcl should be extended to the two CPU clocks |
| 4 | Timing inside the CPU group at 20 / 10 ns: clk_cpu to clk_cpu2x paths (scratchpad, icache fill, GTE results, DMA FIFO, SDRAM front end) have 10 ns (P5 risk 2); E6 measured the GTE at 10 ns on the old clocks through an SDC override |
| 5 | Quartus parsing of the VHDL-2008 code in rtl/gnet/cdc and rtl/gnet/cpu_split (cdcfit has not run either), and the Verilog instantiation of cdc_handshake with its time generic left at the default |
| 6 | VRAM to CPU DMA and SPU DMA reads have one word in flight: correct in the benches, slow; a DMA stopped by software with a fetched word still buffered keeps that word for the next transfer |
| 7 | GPU and SPU register reads take 15 or more CPU cycles instead of 2 (calibration, step 6) |
| 8 | Pause and reset entry with uncached BIOS code at 2:1 (verification item 5) |

### Fit 1 of GNET_CPU50_B1 (2026-10-05): PLL placement

Synthesis passed. The bridge command FIFOs were inferred as dual-clock
altsyncram, RAM_BLOCK_TYPE M10K, read address registered on the read clock,
output unregistered (compile.log, Info 276029 and 286033), as intended. The
Fitter then failed: "Error (175001): The Fitter cannot place 1 fractional
PLL" for pll_cpu, with Error 11238/11239 listing the only candidate
locations, all occupied: FRACTIONALPLL_X0_Y1_N0 (pll_hdmi),
FRACTIONALPLL_X0_Y15_N0 (emu pll) and FRACTIONALPLL_X89_Y1_N0
(pll_vid_fixed). The Fitter confined pll_cpu to the region (0, 0) to (89,
22) because its reference is the pin FPGA_CLK2_50 (PIN_Y13) over the
dedicated clock path (Info 175013/175015). The B1 fit report places the
fourth PLL, pll_audio, at FRACTIONALPLL_X0_Y74_N0 from FPGA_CLK3_50; the
device has 6 fractional PLLs, so the free ones are outside the region the
pin reaches.

Fix (PSX.sv, `GNET_CPU50` block): pll_cpu's reference now comes from
CLK_50M through a clock control block (`cyclonev_clkena`, "Global Clock",
always enabled), so it uses the global clock network and the Fitter can
take a free PLL anywhere. The reference is still the 50 MHz crystal, so the
outputs stay exactly 50.000 and 100.000 MHz; the cost is reference jitter
from the global network, which STA covers through derive_clock_uncertainty.
Needs-review on fit 2: that Quartus accepts a clock-control output as an
fPLL reference here (the report's "Reference Clock Sourced by" for pll_cpu).
If it does not, the fallbacks are FPGA_CLK3_50 into emu (a sys_top.v port
change, the pin that reaches the top PLLs) or a reference from another
PLL's output (cascade, not exact unless that output is an exact multiple of
the crystal).

### Fit 2 of GNET_CPU50_B1 (2026-10-05): placed, one clk_2x endpoint fails

`builds/20261005_1524_cpu50b1`: 26,968 ALMs, 246 RAM blocks, 83 DSP, PLLs 5
of 6 (the global-clock reference worked). One failing setup endpoint, -8.412
ns (TNS -8.412) on clk_2x; hold met everywhere. Reading of the STA report:

- The two pll_cpu clocks are missing from the setup and hold summaries
  although the transfer table lists 314,219 clk_cpu2x to clk_cpu2x and
  63,521 clk_cpu to clk_cpu2x paths. So every path ending on a CPU clock was
  cut, which means the CPU group was not timed at all. Cause: section 3 of
  GNET_CPU50_B1.sdc took `emu|*` minus `emu|psx_mister:psx|*`,
  `emu|sdram:sdram|*` and the channel 3 handshake; the exclusion patterns
  mix instance-only and entity:instance forms, so (my reading) they matched
  nothing and the false path covered every emu register, the CPU group
  included. Fix: the false path now names its sources (hps_io status bits,
  exe_*, biosregion, hasCD, TURBO_*) in the full `emu:emu|...` form that the
  cdc.sdc warnings of fit 1 show.
- The clk_cpu to clk_2x transfer has exactly one path, and the only clk_2x
  destination of the CPU group is the synchroniser of the zero-fill
  "done" toggle (cpu_split.vhd u_filldone). Its source was cpu_reset_fill's
  `done_t`, not a cdc_tx_* register, so cdc.sdc did not bound it and STA
  timed it as a synchronous transfer between two related 50 MHz-derived
  clocks: that is the -8.412 ns path (by elimination; the full path is in
  the report of tools/sta/cpu50_xclk.tcl). The clk_2x to clk_cpu "request"
  toggle had the same flaw (source: the engine's `ext_fill_req_r`), hidden
  by the over-wide false path. Fix: both toggles are copied into
  `cdc_tx_fillreq` (clk2x) and `cdc_tx_filldone` (clk_cpu) before their
  synchronisers.

After the fix, crossing bench (one configuration, 1,000 operations per
master) and the system smoke test give the same results as before (0
errors; final RAM values identical, done marker at 460.2 us). Fit 3 is the
first fit that times the CPU group at 20 / 10 ns, so new CPU-internal
failures there are expected rather than caused by the fix (risk 4).
`tools/sta/cpu50_xclk.tcl` (quartus_sta -t, STA only) lists every path
between the CPU clocks and clk_1x, clk_2x, clk_3x and clk_vid both ways, the
worst paths inside the CPU group (setup and hold) and the full detail of the
worst clk_2x path.

## ZN-2 layer in the CPU group (2026-10-05)

Branch gnet-cpu50: zn2-layer at 13b6e1d (the ZN-2 board, the M2 glue and the
read byte-enable fix of the first hardware test) with r1-cpu50 at 53ad4c3
merged, then option (a) of the zn2-layer merge note in "Crossings as built":
with CPU_CLK_SPLIT = 1 the whole ZN-2 board runs in the CPU group. RTL,
simulation and a Quartus revision; GNET_Z1_CPU50 fit 1 and its STA are
below. Line numbers are this branch at 43c9570.

### Merge

Every conflict was a union of both edits: the generic lists of psx_top and
psx_mister (CLK_FAST_RATIO, CPU_CLK_SPLIT and the four ZN2_* generics), the
PSX.sv localparams and psx_mister generic map, PSX.sv's reset_or (the
watchdog hold and the G-NET downloads with GNET_ZN2, the pll_cpu lock with
GNET_CPU50, both terms when both macros are defined), the SDRAM channel 3
port block (`ifdef GNET_CPU50` / `elsif GNET_ZN2` / `else`), .gitignore
and the pc_build.sh target list. A Verilator parse of PSX.sv with no macro,
GNET_ZN2, GNET_CPU50 and both finds no syntax error (only the missing
framework modules and defines that every configuration reports); it caught
a stray `endif in my first resolution of the channel 3 block, fixed before
the merge commit was final.

### What I built

| Item | Where |
|---|---|
| ZN2_BOARD = 1 with CPU_CLK_SPLIT = 0: the zn2-layer generate, text unchanged apart from its condition | rtl/psx_top.vhd:2897 |
| ZN2_BOARD = 1 with CPU_CLK_SPLIT = 1: zn2_board on clk_cpu with CLK_HZ 50,000,000 and the CPU group's ce, reset_intern and sys_tick; zn2_cdc (component, so builds without the split need no file); zn2_cardmem on clk2x with reset_intern_p | rtl/psx_top.vhd:2995, 3073, 3128, 3178 |
| Crossings of the board (inputs, loader, watchdog, coin, card memory port C18) | rtl/gnet/zn2_cdc.vhd |
| SDRAM channel 3 shared on clk_cpu between the download handshake and the flash port | rtl/gnet/zn2_ch3_arb.vhd; PSX.sv:1532-1584 (GNET_ZN2 inside GNET_CPU50), 618, 1466 |
| zn_sio0: input sys_tick (default '1'); the bit timer starts a bit and counts down only on it | rtl/gnet/zn_sio0.vhd:59, 114, 168 |
| zn2_board: sys_tick passed to zn_sio0 (default '1') | rtl/gnet/zn2_board.vhd:48, 321 |
| Revision GNET_Z1_CPU50, pc_build target z1cpu50 (DIR gn_z1cpu50, TASK gnz1cpu50) | GNET_Z1_CPU50.qsf, tools/pc_build.sh |
| Benches | sim/zn2cpu50/ (tb_zn2_cdc, tb_zn2_ch3_arb, tb_sio0_replay50, run.sh, mutants.py); sim/zn2/system SPLIT and read DQM; sim/zn2/cosim CLK_HZ per library |

With CPU_CLK_SPLIT = 0 nothing of this is elaborated: the zn2-layer
generate is the same text, zn_sio0's new input defaults to '1' (the
conditions reduce to the old ones), and PSX.sv without GNET_CPU50 keeps the
zn2-layer channel 3 multiplexer.

### Timing that derives from the clock

| Block | Before (clk1x) | In the CPU group (clk_cpu, CLK_HZ 50,000,000) |
|---|---|---|
| gnet_ctrl watchdog (MB3773; 5 s, 8 s from 606341a) | 169,344,000 cycles at 5 s | 250,000,000 cycles at 5 s, 400,000,000 at 8 s, both inside its 32-bit counter (WD_CYC = CLK_HZ x WD_TIMEOUT_S) |
| gnet_flash presets (program, block erase, boot block erase) | cyc_us / cyc_ns of CLK_HZ, 64-bit products | the same real times; PRESET 1 erase 50,000,000 cycles, PRESET 3 program 462 cycles |
| gnet_ata (reset detect, diagnostics, command, sector timing) | ns2cyc of CLK_HZ, rounded up | the same real times (T_NEXT 400 ns: 14 cycles before, 20 now) |
| zn2_io AT28C16 write time (200 us) | 6,773 cycles | 10,000 cycles; ee_timer is an integer range sized from the constant |
| znmcu DSR timing (50 us, 5 us) | 1,693 and 169 cycles | 2,500 and 250 cycles |
| zn_sio0 bit timer | one count per clk1x cycle | one count per sys_tick, 10,584 per 15,625 clk_cpu cycles (decision 1): each bit lasts period x 29.525 ns on average, within one clk_cpu cycle |
| zn_cat702 | strobe per bit from zn_sio0 | unchanged (no timer) |
| zn2_board EEPROM erase at power-up | 2,048 cycles | 2,048 cycles (41 us after configuration, long before any download) |
| zn2_cardmem | clk2x | unchanged, still clk2x |

What still counts CPU cycles, as everywhere in the CPU group: memorymux's
expansion bus delays (memctrl) and the glue's own request handling (about 10
cycles per access, docs/m2_glue_findings.md), so an expansion bus access is
1.476 times faster in real time than at 33.8688 MHz. That is the calibration
item P5 risk 11 already lists.

### Crossings

| Interface | Direction | How | Notes |
|---|---|---|---|
| Board inputs: P1, P2, SERVICE, SYSTEM, DSW, JP1, card present, key valid (39 bits) | clk1x to clk_cpu | registered on clk1x (cdc_tx_in, cdc_tx_flags), cdc_sync | Bits independent (switches); DSW, JP1 and the card flags change only with a download, the core held in reset |
| Loader words (CAT702 keys, card metadata, EEPROM) | clk1x to clk_cpu | cdc_fifo 16 x 29, FWFT, M10K; the CPU side issues a word every second cycle at most | zn2_board takes the low byte with ld_wr and the high byte in the next cycle, so two words may not be adjacent. The FIFO absorbs a burst of 16 words at one per clk1x cycle; hps_io's words come from the HPS bridge much more slowly. Overflow is a port (p_ld_overflow, open in psx_top) and a bench check |
| C18 card memory port, gnet_ata to zn2_cardmem | clk_cpu to clk2x and back | cdc_handshake (we, 25-bit word address, 16-bit data; 16-bit answer); the CPU side gives gnet_ata a one-cycle ack and waits for the request to drop; the clk2x side holds the request to zn2_cardmem until cm_ack, then waits for cm_ack to fall (zn2_cardmem holds it two clk2x cycles and then waits for the request to drop) | No reset on either side: an answer that arrives after a zn2_board reset (c_board_rst) for a request made before it is dropped, not acknowledged, and the next request then waits behind it, so order is kept |
| C19 card image download | clk1x to clk2x | none needed | hps_io and PSX.sv's loader stayed on clk1x in r1-cpu50 ("Crossings as built": hps_io stays on clk_1x), so the download and zn2_cardmem are both in the PS1 group, as on zn2-layer |
| Watchdog reset | clk_cpu to clk1x | cdc_pulse, CNT_W 1 (pulses 5 s apart) | PSX.sv stretches it to 256 clk_1x cycles as before |
| Coin counters and lockouts | clk_cpu to clk1x | cdc_tx_coin, cdc_sync | open in PSX.sv today |
| SDRAM channel 3 | clk1x downloads to clk_cpu | r1-cpu50's ch3 cdc_handshake, now carrying only exe, BIOS and flash downloads (src_start gated as zn2-layer's multiplexer selected them); zn2_ch3_arb on clk_cpu takes it or zn2_board's flash port, one request at a time, fields registered and held until ch3_ready, one idle cycle after each answer | The flash port itself does not cross: zn2_board and the SDRAM controller's clk_base are both clk_cpu. The flash read with all byte enables (13b6e1d) is unchanged |
| Expansion bus (memorymux zn_*), SIO0 (bus_pad), IRQ7 | inside the CPU group | synchronous | memorymux is on clk_cpu since r1-cpu50 |

Every new crossing starts at a cdc_tx_* register inside an rtl/gnet/cdc
entity or in zn2_cdc, so cdc.sdc bounds it, and GNET_CPU50_B1.sdc applies to
GNET_Z1_CPU50 unchanged: no new emu-level register reaches the CPU group (the
G-NET inputs, DIP switches and card flags go through zn2_cdc's clk1x
registers; fastboot, ram8mb and biosregion are constants in G-NET builds).

### Reset order

zn2_board takes the CPU group's reset_intern, which cpu_reset_fill issues
after SS_reset and never in the same cycle (C17), so the board resets at the
same point of the sequence as the CPU, DMA and memorymux. zn2_cardmem takes
the engine's reset_intern_p on clk1x, as the DDR3 arbiter does. The two
arrive at different times, and none of the crossings needs them to agree:
the loader FIFO is not reset because the downloads write it while they hold
the core in reset (zn2_board's loader process ignores reset for the same
reason), and the card port completes every access it has started on both
sides. A watchdog reset goes out as a pulse and comes back through PSX.sv's
reset_or and cpu_split's top-level reset path like any other reset.

### Verification (NVC 1.23, every simulation under nice -n 15, at most 2 of mine at a time)

Crossing benches (`sim/zn2cpu50/run.sh unit`, N = 20000): tb_zn2_cdc (zn2_cdc
with the real zn2_cardmem, a DDR3 arbiter model, random zn2_board resets
abandoning requests, loader bursts of up to 12 back-to-back words, the 39
input bits, coin, watchdog pulses) and tb_zn2_ch3_arb (the arbiter behind
PSX.sv's channel 3 handshake: downloads from clk1x, the flash port on
clk_cpu, a channel 3 model checking that the fields stay stable and giving
one ready in ten three cycles long). Clock pairs clk_cpu 50 MHz against
33.8688 / 67.7376 MHz, and clk_cpu at 35 ns (slower than clk1x) against
the same, 4 seeds (random start phases), synchroniser model on and off: 32
of 32 runs, 0 errors. Per tb_zn2_cdc run: 20,000 card port operations, 73
to 109 resets with 53 to 91 requests abandoned (4 to 17 of those words read
back while their write was in doubt), 20,000 loader words, 14,478 to 19,267
watchdog pulses all seen, 211,407 to 357,022 input checks. Per
tb_zn2_ch3_arb run: 4,000 downloads and 20,000 flash operations, 2,381 to
2,449 long readies.

Negative controls (`run.sh neg`), each caught: answer to a pre-reset
request acknowledged (stale_ack, 117 errors); loader word every cycle (1,051);
no wait for gnet_ata to drop its request (no_hold, 3,225); arbiter without
its idle cycle against a three-cycle ready (no_gap, 222); download answered
with the flash port's ready (ready_swap, 2,015).

SIO0 against MAME (`run.sh sio50`, the M0 oracle's sec.log, zn_sio0 after
the f8cf759 merge): nightrai 300 s, 34,367 reads, 7,193 writes, 1,079
znsecsel writes, 0 mismatches at 33.8688 MHz (the counts of
zn2_layer_design.md 16.4) and 0 at 50 MHz with tick_accum's sys_tick and
znmcu at CLK_HZ 50,000,000 (2,664 status reads matching within 1 to 4
edges of 20 ns, inside the 88.6 ns the 33.8688 MHz replay allows);
shikigam 60 s, 23,591 reads, 0 mismatches at both rates.

System bench (sim/zn2/system, read DQM modelled):

| Run | Inputs | Result |
|---|---|---|
| T1 split 0 | BIOS, keys, flash.u30, no card, to 3.83 s | zn2-layer's 3.79 s reference run (13b6e1d tree, no read DQM model) is a byte-identical prefix of every log: 37,916 progress lines, 1,320 GPU writes, 110,521 expansion bus accesses, 38,733 SIO0 lines. VRAM against MAME's oracle dumps: logo frames 40 onwards from 1.25 s with 0 differing pixels, SYSTEM ERROR (frames 169 to 175) at 3.75 s with 0. CAT702: 4,387 of 4,387 bytes equal the reference model |
| T1 split 1 (before the f8cf759 merge) | same, 50 / 100 MHz, PS1 clocks 7 ns later | logo complete by 1.0 s (0 pixels against MAME frames 40 onwards), SYSTEM ERROR at 3.5 s (0 pixels against frames 169 onwards); the first 1,146 GPU writes equal split 0's in order; CAT702 3,704 of 3,704 bytes. The selects and SIO0 traffic differ from split 0 by timing (session lengths depend on CPU speed, as zn2_layer_design.md 18.3 notes) |
| T1 split 1 (after the merge) | same | SIO0 log byte-identical to the run before the merge for its first 50,432 lines (0.46 s), GPU log identical |
| Shikigami warm, split 1, sdram.sv before and after 6cb9b78 | the full-system bench's inputs (warm shikigam.flash, Shikigami card), to 0.65 s | both runs pass the TT16 security sessions and run the sub-BIOS from RAM by 0.65 s (PC 803AAExx, 286 GPU writes, about 108,000 expansion bus accesses), with no I-cache race reported. My bench does not reach the failing fetch pattern of e4's fullsys harness and of the hardware (below), so these two runs show only that the fix changes nothing else on this path |

### Merges after the first commits

For the 50 MHz hardware RBF: zn2-layer
f8cf759 merged (c324cf5: zn_sio0 reads decoded on bus_addr(3 downto 1),
the Shikigami post-loader stall; the zn2-layer system bench with its own
read DQM model and download path model, onto which I put the SPLIT changes
again), main cfdf23f cherry-picked (e775367: GP1(10h) index 7 answers 2 in
ZN-2 mode), hw-debug-overlay 878ad18 cherry-picked (606341a: MB3773 period
8 s). 878ad18 alone does not analyse: its zn2_board generic map passes
WD_TIMEOUT_S, which the entity did not declare; 98f4c77 declares it
(default 8).

### Fit 1 of GNET_Z1_CPU50 (e775367) and the SDC

`builds/20261005_1935_z1cpu50`: 28,681 ALMs (68%), 256 M10K, 84 DSP; every
clock met except clk_cpu, -1.221 ns, TNS -23.308. tools/sta/cpu50_xclk.tcl
on it (`builds/z1cpu50_xclk`): every failing endpoint is a crossing capture,
none is logic inside the CPU group. clk_1x to clk_cpu, 47 paths: cdc_rx_s1
of independent-bit or single-bit synchronisers (cpu_split u_p2c
cdc_tx_p_lvl, -1.221; cpu_spu_bridge cdc_tx_dreq, -0.806) and cdc_rx_hold of
handshake data (cpu_spu_bridge u_rsp, from -0.75). clk_2x to clk_cpu, 9
paths, worst -0.228 (zn2_cdc u_cm cdc_tx_rsp to cdc_rx_hold, cpu_split
cdc_tx_fillreq). Inside the CPU group: clk_cpu to clk_cpu +1.268, clk_cpu
to clk_cpu2x +0.790, clk_cpu2x to clk_cpu +1.343. GNET_CPU50_B1 fit 3 had
failed the same way (-0.807 on cpu_gpu_bridge cdc_tx_req to cdc_rx_hold).

cdc.sdc (38f6bd0, 048cf9e) now bounds cdc_tx_* to cdc_rx_s1 and to
cdc_rx_hold at 14 ns instead of 8 ns; the Gray-bus skew stays at 5 ns. The
reasoning is in the file: the length of the path into a first synchroniser
stage does not change the settling time from that stage to the next (the
MTBF), and with independent bits it only moves the edge where a change is
first seen; held handshake data is captured STAGES edges after its toggle
is first sampled. 14 ns stays below the shortest crossing destination
period (clk2x, 14.76 ns), so the cdc_handshake and cdc_fifo latency counts
hold. The STA-only re-check with the new cdc.sdc was queued and had not
reported when I wrote this.

### The I-cache refill race at CLK_FAST_RATIO = 2 (fixed in 6cb9b78)

On hardware the e775367 RBF (Shikigami, warm) showed the BIOS POST bars and
a reset loop; the full-system Verilator harness of the same tree at
50 MHz stopped the same way, at PC BFC0B530, the BIOS's A0 stub for
function 40h (SystemErrorUnresolvedException). e4 traced it to a BREAK
(Cause 0x24, EPC 0x316C) in the RAM security routine: at 0x316C the CPU
executed 0x0007000D, the old contents of I-cache line 16h word 3 (from
0x216C), instead of 0x00E02021 from RAM. The fetch came two instructions
after the line miss at 0x3160, through a taken branch to word 3.

Cause, in sdram.sv: for a cache line fill ch1_ready is raised after the
second word (data_ready_delay1[4]) and the last two words reach the I-cache
2 and 4 fast clock edges later. The r1 mem_lat bench measures it
(ifetch_ram_cached_line, 400 samples, CPU cycles from the request):

| Ratio, sdram.sv | ram_done | Last refill word written |
|---|---|---|
| 3:1, upstream | 5 | 5.33 mean (5.33 to 7.00) |
| 2:1, before 6cb9b78 | 7 | 8.01 mean (8.00 to 10.00) |
| 2:1, 6cb9b78 | 9 (9: 398, 12: 2) | 8.02 mean (8.00 to 11.00) |

So upstream also releases the CPU a third of a cycle before word 3 is in,
safe only because the CPU cannot fetch it within a third of a cycle; at 2:1
the margin became minus one cycle. 6cb9b78 raises ready for a fill at 2:1 on
cache_done_3, the edge that writes the last word; the CPU is stalled on the
miss until then. At 3:1 the condition is the upstream one (constant
parameter). Cost at 2:1: a cached-line miss takes 9 CPU cycles instead of 7.
Every other mem_lat row, the data checks and the DMA phase are unchanged.
None of my system bench runs reached the failing pattern, and my bench's
new I-cache checker (85c06e7) did not fire in them, so the end-to-end check
of the fix is e4's harness and the next hardware test.

### Risks and needs-review

| # | Item |
|---|---|
| 1 | The STA re-check of 048cf9e's cdc.sdc, and a full refit, are pending; the CPU-group logic paths themselves met on fit 1 |
| 2 | The I-cache fix is verified by the mem_lat measurement and the root-cause trace, not yet by a full run past the failing fetch (e4's harness, hardware) |
| 3 | My system bench did not reproduce the 2:1 refill race that e4's harness and the hardware hit, so it under-tests clock-phase-dependent paths inside the CPU group; the crossing benches randomise phases, the system bench uses one fixed phase |
| 4 | The loader FIFO has no back-pressure to hps_io (16 words, popped at up to 25 M words/s); fine for the HPS bridge rate, not measured |
| 5 | Expansion bus, flash and card latency in real time drop by 1.476 at 50 MHz (waits count CPU cycles), and the card port adds 5 to 7 clk_cpu cycles of handshake per DDR3 access: calibration items |
| 6 | PSX.sv's download path through the channel 3 handshake and zn2_ch3_arb is simulated in tb_zn2_ch3_arb only, not in the system bench |
| 7 | SIO0 keeps 33.8688 MHz-equivalent bit timing (decision 1). The halt that first looked like an SIO0 timeout was the I-cache race; the SIO0 MAME replays at 50 MHz match |

### Follow-up: loader back-pressure, clock phase sweep, bus latency proposal (2026-10-05)

**Loader back-pressure (72dccbc).** With the split the key, metadata and
EEPROM words cross through zn2_cdc's 16-word FIFO. zn2_cdc now raises
p_ld_busy (a clk1x register) while the write side counts 12 words or more;
psx_top exports it as zn_ld_busy (constant 0 in every other configuration)
and PSX.sv holds ioctl_wait on it during downloads 2, 4 and 6, the
mechanism it already uses for the card. So no HPS write rate can overrun
the FIFO, and I did not need to bound the rate from Main_MiSTer's source.
tb_zn2_cdc LD_STRESS=1 offers a word on every clk1x cycle and stops only on
p_ld_busy seen two cycles late (ioctl_wait through PSX.sv and hps_io): 8
runs, 20,000 words each, 7,083 to 27,396 held cycles, every word delivered
in order, no overflow. The negative control (LD_STRESS=2, busy ignored)
overflows.

**Clock phase sweep (9e54733, 26cdad6).** PHASE and CPU_PHASE delay the PS1
and the CPU clocks of the system bench; sim/zn2/system/sweep.sh runs one
test once per pair (default eight pairs, including 7ns:0ns, the bench so
far, and 0ns:5ns, about the full-system harness) and lists per pair the last
progress line, the GPU write count and whether the sequence equals the
first pair's, I-cache races and watchdog resets.
Result on the refill race: with sdram.sv from before 6cb9b78 and e4's
inputs (warm shikigam.flash, Shikigami card), pairs 0ns:5ns and 0ns:0ns to
539 ms, both runs pass the security routine (PC 31D4 onwards after the last
84h session at 518.9 ms, the path e4 saw at 33.87 MHz), with identical GPU
sequences, no I-cache race reported and no watchdog reset. So the clock
phase alone does not bring my bench to the failing fetch. What else differs
from e4's harness is still open: its SDRAM chip model and refresh
alignment, its own channel 3 arbiter copy, its loader timing, the DDR3
latency of its card model. Each moves where a refill lands relative to the
CPU. Next step, if wanted: run e4's exact trace window in both benches and
compare the cycle of the 0x3160 miss and its ready.

**Expansion bus and card latency at 50 MHz (proposal, nothing changed).**

What the core does: memorymux counts every expansion bus step in CPU
cycles from the delay registers the software writes (memctrl, COM_DELAY),
as PSX_MiSTer does for the PS1. For a ZN-2 read step it waits the
programmed read delay first and only then issues the zn request
(EXT_READ_NEXT, memorymux.vhd), and EXT_READ waits for zn_ack; for a write
step the request goes out at the start of the step and the programmed
delay runs alongside it. So a read costs the programmed delay plus the
whole device latency of the glue, a write about the larger of the two.

What the evidence says:
- MAME 0.288 (taitogn.cpp, zn.cpp) charges no wait states for these regions
  at all; it is no evidence for the length of a bus cycle.
- The FC PCB parts set lower bounds only: U30 and U29 28F160S5-100 (100 ns),
  U27 28F400B5-80 (80 ns) (docs/board_evidence.md S2, S9). The delay values
  Taito's software programs are far longer. The flash window setting
  0x201716BB has a read delay of 11; mem_lat measures a 16-bit read of it as
  15 CPU cycles (Measurements 2 and 3, both ratios), 443 ns at 33.8688 MHz
  and 300 ns at 50 MHz. Both cover a 100 ns part with room to spare, so the
  real bus is not limited by the parts.
- The bus controller is inside the CXD8661R, as on the PS1, where it counts
  the CPU's own clock. If the CXD8661R does the same at 50 MHz (my
  inference; post-0.288 MAME clocking the ZN-2 GPU from 100 MHz / 2 points
  the same way, board_evidence.md M1), then counting the programmed delays
  in 50 MHz cycles, as the core now does, is the hardware behaviour, and the
  1.476x shorter real time compared with the 33.8688 MHz build is a
  correction, not an error.
- What no board has is the glue's own latency. gnet_fc needs about 10 clock
  cycles per access before its storage (docs/m2_glue_findings.md 1, 5),
  plus the storage itself (zn2_board's flash adapter, zn2_ch3_arb, the SDRAM
  at 2:1: about 8 CPU cycles, my estimate from the mem_lat row
  ram_lw_isolated 7 plus the adapter and arbiter registers). For a 16-bit
  flash read that is about 15 + 18 = 33 CPU cycles, against 15 on a board
  where the part answers inside the strobe (my estimate; the FC PCB wait
  behaviour, board_evidence.md M4, is open). The card data port adds the
  C18 handshake (5 to 7 CPU cycles) and a DDR3 line read on each line miss.

Proposal (for Lee; I changed nothing):
1. Keep the programmed delays in CPU cycles (no CLK_HZ scaling): it is the
   CXD8661R behaviour as far as the evidence goes.
2. A memorymux generic for ZN2_MAP, for example ZN2_READ_OVERLAP (default
   0, today's behaviour): with 1 the read step issues its zn request when
   the read delay starts and leaves EXT_READ at the later of the delay's
   end and zn_ack, as writes already do. A flash or ATA read then costs the
   programmed delay whenever the glue answers within it, the behaviour of a
   board whose parts answer inside the strobe. It changes no data and no
   order. Verification: memorymux's equivalence bench at ZN2_MAP = 0 is
   unchanged; with ZN2_MAP = 1 the directed zn tests plus a latency row per
   delay setting.
3. No CLK_HZ-derived wait constant until a board measurement exists: the
   R1 timing program (a tight loop of 16-bit reads of 0x1F000000 timed
   with root counter 2) on a real FC PCB gives the real bus cycle per
   setting, and the same program in the system bench gives the core's.
   Load-screen footage (M7) gives the card side.

### CPU and memory throughput at 50 MHz: Ray Crisis prepare bar (2026-10-06)

Question (from full-system runs of 98f4c77): the
"Prepares the start." bar takes 12.3 s in MAME, 16.9 s in the 50 MHz core,
20.7 s in the 33.87 MHz core and 14.69 s on the PCB
(docs/r1_speed_study.md). Where do the core's cycles go, and what would the
real CXD8661R spend? Nothing changed; this is a measurement and a proposal.

Method: a6's 50 MHz full-system build (gnet-mister-a6fs work/a6c50,
98f4c77, Verilator), Ray Crisis warm flash with card, run read-only into my
scratchpad: a checkpoint at 5 s, then pc.log (every new fetch-stage PC with
its time) and io.log with every CPU data access (-iolog_all) over 50 ms
windows; opcodes from main RAM taken out of the checkpoint's SDRAM image
(the run's own ram dump covers only 64 KB). tools/r1/cpu_breakdown.py
counts the cycles each fetch-stage PC is held and gives every extra cycle
one cause: a data access requested within it or in the 3 cycles before
(by region), else a store among the last 4 instructions (stores are posted
and have no done pulse, so io.log does not list them), else an I-cache
miss of a model of the 4 KB cache, else MFHI/MFLO, else a COP2 opcode.

Window 6.000 to 6.050 s (inside the bar; 2,500,000 CPU cycles, 856,289
instructions, CPI 2.92):

| Cause | Cycles | Share | Events | Mean extra cycles |
|---|---|---|---|---|
| Base, 1 per instruction | 856,289 | 34.3% | | |
| Main RAM load | 1,501,317 | 60.1% | 174,468 | 8.61 (8: 90,470; 9: 36,606; 10: 20,325) |
| Store followed by a stall | 76,119 | 3.0% | 10,886 | 6.99 |
| Expansion bus load (flash) | 55,698 | 2.2% | 1,518 | 36.7 |
| Other loads (I/O, BIOS, other) | 10,185 | 0.4% | 966 | |
| I-cache miss | 18 | 0.0% | 12 | 1.5 |
| Other | 373 | 0.0% | 173 | |

No GTE command and no MFHI/MFLO stall appears in the window.

A second window at 12.000 to 12.050 s (restored from the 5 s checkpoint)
gives the same mix: 849,150 instructions, CPI 2.94; RAM loads 60.5% of
cycles (175,715 loads, 8.60 extra cycles each), stores 3.0% (7.03),
expansion 2.2% (36.7), base 34.0%, I-cache misses 11. So the estimates
below hold across the bar.

Findings:
1. The bar is RAM-load bound. Each main RAM load holds the pipeline 8.6
   cycles on average (mostly 8 to 10), so a load costs about 9.6 cycles at
   50 MHz. I-cache misses are negligible (the unpack loop stays in cache),
   GTE and mult/div do not appear, the expansion bus (flash reads) is about
   2%.
2. SDRAM latency in CPU cycles grew at 2:1. The r1 mem_lat bench (Measurements
   2 and 3, rows at 100 / 50 MHz): an isolated RAM word read takes 5 CPU
   cycles from request to done at 3:1 and 7 at 2:1. In real time that is
   148 ns and 140 ns: the SDRAM path costs the same nanoseconds, so at 50 MHz
   it costs 2 more CPU cycles per load. With about 2.6 cycles of pipeline
   around it, a load is about 7.6 cycles at 33.87 MHz and 9.6 at 50 MHz. That
   is why 1.48x the clock gives about 1.22x on the bar (a6: 20.7 / 16.9 s =
   1.225; my estimate from this window's mix: 1.26).
3. The real chip: psx-spx (CPU Specifications, Load Timing) gives a PS1
   main RAM load as 7 CPU cycles (plus occasional refresh stalls), scratchpad
   1, on-die I/O 5, BIOS ROM 27 to 33. PSX_MiSTer at 33.87 MHz matches the 7
   (7.6 above). For the ZN-2 the question is whether the CXD8661R's DRAM
   interface keeps that count in its own cycles at 50 MHz. The board's RAM
   is LC321664AM-80, fast page mode, 80 ns (docs/board_evidence.md P4), which
   allows a 7-cycle (140 ns) random read at 50 MHz. The PCB's bar time
   points the same way: holding this window's mix fixed and solving for the
   load cost that turns 16.9 s into the PCB's 14.69 s gives about 7.7
   cycles per load, close to 7 plus refresh. So the core probably spends
   about 2 cycles per RAM load that the real chip does not (inference,
   rank 5 at best: no CXD8661R timing document, one game's bar, one window
   mix).
4. Stores: a store followed by a load waits for the write to reach memory
   (about 7 cycles here). That is real R3000 behaviour: the R3051 bus unit
   serves pending writes before data reads (IDT R3051/R3052 Hardware
   User's Manual, chapter 6, "Multiple operations"), so it is not core
   overhead in itself; its length also follows the SDRAM write path.
5. Expansion bus: flash reads cost about 37 cycles each, against the
   programmed delay of about 15; see the bus latency proposal above (read
   overlap).

Options (for Lee; none applied):
A. SDRAM at 3:1 to the CPU clock again: clk_cpu3x = 150 MHz from pll_cpu
   (VCO 300 MHz: C 6 / 2 already gives 50 and 150 MHz exactly), CLK_FAST_RATIO
   3, so a load is 5 + 2.6 cycles as at 33.87 MHz. sdram.sv's constants are
   for 100 MHz (CAS 2 "for < 100MHz", refresh count "@ 100MHz"); 150 MHz needs
   CAS 3 and new refresh and tRCD/tRP counts, and the MiSTer SDRAM module's
   rating and the board trace timing at 150 MHz are needs-review. Fit risk:
   the SDRAM controller at 6.67 ns.
B. Keep 100 MHz and shorten the fixed part of a CPU read at 2:1: count the
   request strobe, ACTIVE, READ, the CAS latency, the data register and the
   ready crossing back to clk_cpu edge by edge and remove what is not needed
   at 2:1 (for example the first-word ready one fast edge earlier, or a
   bypass of the clk_base ready register). Smaller gain (probably 1 cycle),
   lower risk, verified with the mem_lat bench rows.
C. Calibrate to the PCB instead of to the DRAM: the bar time measured on
   hardware is the target (14.69 s). Option A or B plus the read-overlap
   proposal for the expansion bus would bring the core to about 14.5 to
   15.5 s by this window's mix (my estimate); a second game's CPU-bound
   section (Night Raid's NOTICE phase, 4.8 s core against 3.1 s MAME) and a
   PCB capture of it would check it.

### Option B prototype: EARLY_READY (branch cpu50-loadpath, 2026-10-06)

Change (rtl/sdram.sv, parameter EARLY_READY, default 0; PSX.sv macro
GNET_EARLY_READY): at CLK_FAST_RATIO = 2 a plain channel 1 read (not a
cache line, not DMA) sets ch1_ready_ramclock on the fast edge that stores
its first halfword (data_ready_delay1[7]) instead of the next one, and the
clk_base register that hands the word to the CPU (ch1_dout32) takes the
second halfword straight from dq_reg when it arrives on that same edge
(data_ready_delay1[6]); otherwise it takes ch1_dout as before. Why it saves
a cycle: at 2:1 the second halfword lands on a clk_base edge, one fast
edge too late for that edge's ready register, so the word waited a whole
clk_base cycle. Nothing else moves: the SDRAM command sequence, cache line
fills (still the 6cb9b78 timing), DMA, writes and refresh are unchanged,
and at 3:1 or with EARLY_READY = 0 the conditions are constant false.

mem_lat (100 / 50 MHz, 400 samples per row, request to done in CPU cycles):

| Row | Before | EARLY_READY = 1 |
|---|---|---|
| RAM LW isolated | 7 | 6 |
| RAM LW back to back | 7 | 5 |
| RAM LW, gap of 2 | 7 | 6 |
| RAM LBU | 7 | 6 |
| Instruction fetch, uncached RAM | 7 | 6 |
| Instruction fetch, cached line | 9 | 9 |
| BIOS LW / LH / LB | 33 / 17 / 9 | 32 / 16 / 8 |
| RAM read-back after a write | 7 | 6 |

Data errors 0, DMA OTC 2,048 / 2,048 and GPU DMA 2,048 words with 0
errors, strobe mismatches 0. EARLY_READY = 0 at 2:1 and the 3:1 run are
byte-identical to the bench output before the change (mem_lat.txt diffed,
the 3:1 one against sdram.sv from gnet-cpu50).

System bench (sim/zn2/system, SPLIT 1, EARLY_READY=1, T1: BIOS, keys,
flash.u30, no card, to 1.135 s): the logo is complete at 1.0 s with 0
differing pixels against MAME frames 40 onwards, all 4,140 CAT702 bytes
equal the reference model, and the first 455 GPU writes equal MAME's in
order (the earlier split-1 run had the known extra E1h write at position
242; the timing change happens to remove it). No watchdog reset.
The crossing benches (sim/zn2cpu50, sim/cpu50 split) do not compile
sdram.sv, so this change cannot affect them; I did not rerun them.

Bar estimate from the 6.0 s window mix (174,468 RAM loads in 2,500,000
cycles, my estimate): with 1 cycle saved per RAM load the window takes
2,326,000 cycles, so the bar would take about 15.7 s (from 16.9); with the
back-to-back case (2 cycles) dominating it would be about 15.0 s. The PCB's
14.69 s is still lower: option B alone does not reach it.

### Option A on paper: SDRAM at 150 MHz (3:1 to the 50 MHz CPU)

- Clocks: pll_cpu already runs its VCO at 300 MHz (fit report, divider 6
  for 50 MHz and 3 for 100 MHz), so 150 MHz is divider 2, exact and
  phase-aligned with clk_cpu. CLK_FAST_RATIO 3 then uses the upstream
  strobe logic, and every request, cache and DMA path keeps the 3:1 timing
  PSX_MiSTer was written and tuned for (the 7.6-cycle load).
- sdram.sv as written assumes about 100 MHz: CAS_LATENCY 2 with the
  comment "2 for < 100MHz, 3 for >100MHz"; one WAIT state between ACTIVE
  and READ (tRCD 20 ns at 100 MHz, 13.3 ns at 150); the refresh count "@
  100MHz"; tRFC covered by the idle states counted at 100 MHz. At 150 MHz:
  CAS 3 (data_ready_delay positions and the CAS_LATENCY+BURST_LENGTH
  index move by one), tRCD and tRP of 15 to 20 ns need 3 fast cycles at
  6.67 ns where 2 sufficed at 10 ns (the exact AS4C32M16SB values are
  needs-review), the refresh interval and tRFC counts scale by 1.5, and the
  write recovery before precharge must be rechecked. The cache-fill ready
  of 6cb9b78 and the channel 2/3 timings would need their own mem_lat
  rows at 3:1 / 150 MHz.
- The chips: the official XS-D v3 128 MB module uses Alliance AS4C32M16SB-7TCN
  (misterfpga.co.uk product page); the AS4C32M16SB comes in 166 MHz (-6)
  and 143 MHz (-7) grades (LCSC part listing: "Fast clock rate: 166/143
  MHz"). 150 MHz is above the -7 rating at CAS 3. MiSTer's MemTest asks a
  board to pass 130 MHz ("Board should pass at least 130 MHz clock test",
  MemTest_MiSTer README); a module vendor states its boards pass 140 to 150
  MHz and that "126 MHz is the fastest any current core needs"
  (misterfpga.co.uk). So option A runs the SDRAM beyond its datasheet and
  beyond any shipping MiSTer core: a board that passes MemTest at 130 MHz
  is not guaranteed at 150 MHz. I found no MiSTer core that runs SDRAM at
  133 MHz or more (vendor statement; not an exhaustive survey of core
  sources).
- Fit: the SDRAM controller and its I/O at 6.67 ns, plus the clk_cpu to
  150 MHz paths (DMA FIFO strobe, icache fill port, SDRAM front end), which
  today have 10 ns.
- Verdict on paper: feasible as an experiment, out of spec for -7 chips;
  I would not choose it for a release without board testing across
  modules. A 133 MHz variant (8:3 to 50 MHz) is within spec but not an
  integer ratio, which the strobe logic and the 2:1/3:1 index generators
  do not support.

### Source of the PCB bar time

14.69 s is the "Prepares the start." loader screen measured frame by frame
in westtrade's video "TAITO G NET Arcade Board with Ray Crisis"
(YouTube zIpQM4xNWdY, 2022-01-10, camera on a CRT, board shown on camera):
loader screen on at video 57.78 s (frame 1065/1066), off at 72.47 s (frame
1946), 880.5 frames at 59.94 fps = 14.690 s; MAME 0.288 gives 738 frames at
59.826 Hz = 12.336 s (docs/r1_speed_study.md sections 1 and 3.1). Caveats
from that study: one recording, rank 4 evidence; the board runs the MB2011
sub-BIOS; the notice screen (timer paced) lasts 2.019 s on the PCB against
2.006 s in MAME, which confirms the two time bases agree.

### Night Raid NOTICE phase at 50 MHz (2026-10-06)

Full-system runs on 98f4c77 put Night Raid's NOTICE screen at 9.86 s to
14.66 s on the 50 MHz core (4.8 s) against 8.07 s to 11.17 s in MAME
(3.1 s). I asked whether that phase is paced by a timer or vblank, which
would make the 1.7 s something other than CPU speed. I ran a6's binary
read-only (checkpoint at 10.0 s, output in my scratch directory) with
-pctrace and -iolog_all over 11.00 s to 11.05 s and ran
tools/r1/cpu_breakdown.py on it (BIOS image from a6's work/data, opcodes
from the 10.0 s checkpoint's SDRAM).

Window: 716,105 instructions in 2,499,998 cycles, CPI 3.49.

| cause | cycles | share | events | mean extra |
|---|---|---|---|---|
| base (1 per instruction) | 716,105 | 28.6% | | |
| load RAM | 943,429 | 37.7% | 115,115 | 8.20 |
| load expansion RF5C296/ATA (1FB00000) | 702,004 | 28.1% | 38,715 | 18.13 (21, 23, 25 typical) |
| store | 61,312 | 2.5% | 8,779 | 6.98 |
| load I/O other (memctrl delay regs) | 24,134 | 1.0% | 5,702 | 4.23 |
| load 1FA60000 (sound status) | 13,272 | 0.5% | 768 | 17.28 |
| load I/O DMA | 9,559 | 0.4% | 1,927 | 4.96 |
| load I_STAT/I_MASK | 3,647 | 0.1% | 414 | 8.81 |
| I-cache misses | 53 | 0.0% | 20 | |

It is not timer or vblank paced. I_STAT and I_MASK are read 438 times in
50 ms and no code waits on them; the timers do not appear; the ATA status
register (1FB00007) is read 153 times against about 100 sectors, so the
CPU is not waiting on the card either. The phase is the game copying card
data at CPU speed, in two routines:

- 80095454, a halfword copy loop (lhu from the ATA data port, sh to RAM,
  4.5 instructions per halfword): 20,194 data port reads, 23.1% of the
  cycles, CPI 6.31, about 28.7 cycles per halfword.
- 8008D4E0 calling 8008CAF0, a byte reader (one lbu from the data port per
  call, then counters and sector bookkeeping kept in RAM globals, about 40
  instructions per byte): 8,733 bytes, 44.6% of the cycles, about 128
  cycles per byte. This path is RAM load bound, not card bound.

The rest is a sound command routine at 80084B20 (switches exp3 delay to
0x3022, polls 1FA6xxxx bit 3 up to 100 times, restores the delay; 384
calls in the window, about 8% of the cycles) and code at 800904xx that
compares the loaded bytes.

MAME runs the CXD8661R at 100 MHz input with execute_clocks_to_cycles =
clocks / 4 and one icount per instruction (src/devices/cpu/psx/psx.cpp and
psx.h, MAME 0.288): a flat 25 million instructions per second with no
memory or bus wait states, which is CPI 2 in 50 MHz cycles. The same
716,105 instructions take 28.6 ms there against 50 ms here (ratio 1.75).
Over the whole phase the ratio is 4.8 / 3.1 = 1.55, so other parts of
NOTICE are lighter than this window, but the direction and most of the
size of the gap are the per-instruction cost. Here CPI 3.49 is 1 base plus
1.32 for RAM load stalls, 0.98 for ATA data port stalls and 0.19 for the
rest, against MAME's flat 2.

If the window mix holds across the 4.8 s, the phase spends about 1.8 s in
RAM load stalls and 1.35 s in ATA data port stalls. Option B (EARLY_READY)
saves one cycle per RAM load, about 4.6% of this window or 0.2 s of
NOTICE. The ATA stall (21 to 25 cycles per halfword at exp3 0x1EBB or
0x2EBB) is the place where the read-overlap proposal in the bus latency
section applies. Whether the PCB is closer to MAME or to the core here is
unmeasured; the Ray Crisis bar (PCB 14.69 s between MAME 12.3 s and core
16.9 s) suggests the real board also pays wait states MAME does not model.

### Read overlap prototype: ZN2_READ_OVERLAP (branch cpu50-loadpath, 2026-10-06)

What it does. memorymux has a generic ZN2_READ_OVERLAP (default 0, the
behaviour before it). It is passed through psx_mister and psx_top, and
PSX.sv sets it from the macro GNET_READ_OVERLAP. With 1, a ZN-2 read step
(expansion 1 or 3, ZN2_MAP = 1) issues its zn request when its read delay
starts: the first step from EXT_IDLE, every later step from EXT_READ as it
moves to the next step. EXT_READ_NEXT then sends nothing, and EXT_READ
leaves at the later of the delay's end and zn_ack, which is what writes
already do. The number of requests, their order, addresses and byte
enables do not change, and neither does the data.

A posted-write address bug, now fixed on every path. While testing I found
that memorymux took the word address of a ZN-2 write step from
addressData_buf when the step started. A write is posted: the main state
machine returns to IDLE, and IDLE copies the CPU's current address into
addressData_buf every cycle. So any later step of a posted write (a 32-bit
store on the 16-bit bus, a halfword on the 8-bit bus, or a step after a
recovery prewait) went to the address of the CPU's next access if that
access arrived first. A directed test shows it (tb_memorymux_zn 5b: sw to
0x1FB40110 at 0x36BB, then a RAM read 2 cycles later; the second halfword
went to word address 0x012344). In a6's runs it never happened: none of
the 6,741 second steps in the Night Raid and Ray Crisis zn.logs went to
another address, because the CPU is slower to issue its next data access
than the bus is to finish. Read overlap makes it likelier, because a read
can now end while its recovery count is still running and a write right
after it waits in the prewait. I ruled it a correctness bug,
so every ZN-2 write step now takes the word address latched with the
access in EXT_IDLE (zn_waddr), whatever ZN2_READ_OVERLAP is. The fix sits
inside the ZN2_MAP = 1 branch of EXT_WRITE; ZN2_MAP = 0 does not use
zn_waddr.

Verification of the fix (NVC, nice -n 15, one at a time):
- tb_memorymux_zn 5b now runs at both generic values and passes: both
  halfwords reach word 0xB40110, and the device holds 0xC0DE1234 there.
  The other directed tests pass (seeds 1 to 4 at 0, 1 and 2 at 1).
- ZN2_MAP = 0 against upstream main (eq, seeds 1 to 3): no output differs
  in any cycle.
- 3a3fefa against the fixed memorymux (prev, both ZN2_MAP = 1, overlap 0,
  20,000 random accesses that do not wait for posted writes, seeds 1 to
  4). The bench splits the differences:

| seed | cycles with any output differing | cycles differing outside read data and zn_addr | write requests differing in the address only | other request differences | reads returning different data |
|---|---|---|---|---|---|
| 1 | 133,464 | 0 | 3,378 | 0 | 1,384 |
| 2 | 131,810 | 0 | 3,421 | 0 | 1,460 |
| 3 | 134,806 | 0 | 3,298 | 0 | 1,390 |
| 4 | 141,181 | 0 | 3,570 | 0 | 1,461 |

  The only differences are the addresses of the write steps the old code
  misdirected (in the examples the bench prints, the old address is that
  of the next access, for example 0x801CAC in the SPU registers) and the
  read data of device bytes those writes reached or missed. Timing,
  request order, byte enables, write data and every other output are
  equal in every cycle.
- The transaction check with the bench waiting for posted writes (ovl,
  seed 1, overlap 0 and 1) still passes.
- System bench (SPLIT = 1, Night Raid card, overlap 0, 915 ms, through the
  BIOS flash phase and the first card phase) against the run before the
  fix: zn.log (128,322 requests), zlat.log, gpu.log (335 writes), sio.log
  (54,890 lines) and progress.log are identical line for line, timestamps
  included. The boot path never hit the bug, so the fix changes nothing
  there.

Verification (NVC 1.23, every run under nice -n 15, one at a time;
sim/zn2/run_memorymux.sh):
- eq: ZN2_MAP = 0 against upstream main, 20,000 random accesses, seeds 1
  to 3: no output differs in any cycle.
- prev (new): the ZN-2 memorymux before this change (3a3fefa) against this
  one, both ZN2_MAP = 1. Every memorymux output and the zn_* port are
  compared every cycle, with the same device model and latency sequence.
  With ZN2_READ_OVERLAP = 0, seeds 1 to 4: no difference in any cycle. With
  1 (a sensitivity check): 239,345 cycles differ, as they should.
- zn (directed): with 0, seeds 1 to 4: pass. With 1, seeds 1 to 4: pass,
  including 5b.
- ovl (new, tb_memorymux_ovl): the previous memorymux against this one
  with ZN2_READ_OVERLAP = 1. Both get 20,000 random accesses (exp1 and exp3
  at Taito's settings and at random ones, random COM delays and sizes, RAM
  accesses between, ce gaps during stalled reads), one access at a time.
  Seeds 1 to 4: no read data differs, and the device request sequence
  (about 30,000 requests, with write data) is identical. Read wait cycles
  fall from 367,443 to 257,209 (seed 1). With 0 the cycle counts are
  identical.
- lat (new, tb_memorymux_lat): per-access cycles against a device that
  acknowledges after exactly L cycles, with COM_DELAY 0x2110 (what the
  games read back from 1F801020). Every read is checked against the device
  data.

| access | delay setting | before: done after | overlap: done after |
|---|---|---|---|
| flash lhu | exp1 0x201736BB | 16 + L | max(14, L + 4) |
| flash lhu | exp1 0x201716BB | 17 + L | max(15, L + 4) |
| flash lw (2 steps) | exp1 0x201736BB | 33 + 2L | max(29, 2L + 7) |
| ATA lhu | exp3 0x20151EBB | 17 + L | max(15, L + 4) |
| ATA lbu | exp3 0x20152EBB | 17 + L | max(15, L + 4) |
| ATA lhu, 8-bit bus | exp3 0x20152EBB | 35 + 2L | max(31, 2L + 7) (32 at L = 12) |
| 1FA60000 lw | exp3 0x20153022 | 14 + 2L | 7 + 2L |

(cycles from the CPU request to mem_done for an isolated access; back to
back is the same except at 0x201736BB, one cycle more.) Without overlap the zn request goes out 15 or 16 cycles
after the CPU request (7 at 0x3022). With overlap it goes out after 3.

L in the real system. a6's 98f4c77 traces (io.log request time, zn.log
zn_req time, pc.log end of the stall):
- ATA data port: the CPU request to zn_req is 14 (16 on every second
  read), and zn_req to the end of the stall is 11.
- Flash (Ray Crisis): 17 and 22.
- 1FA60000 lw: 6 and 13.

The bench gives zn_req to done as L + 1 for a single step and 11 + 2L for
the 1FA60000 lw. The lw then fits L = 1 with done and the next PC on the
same cycle, which gives L of about 10 for the ATA data port and about 21
for flash. My system bench measures it directly (zlat.log, below): flash
reads ack after 18 cycles (105,437 of 107,712).

Gain per access at those latencies:
- ATA data port (L 7 in my bench, about 10 in a6's): 24 to 27 cycles drop
  to 15, 9 to 12 saved per halfword or byte. The read now costs the
  programmed delay.
- Flash (L 18 to 21): 35 to 38 cycles drop to 22 to 25, 12 to 13 saved per
  step. The glue still adds about 7 to 11 cycles beyond the programmed
  delay.
- 1FA60000 lw: 7 saved.

System bench (sim/zn2/system, SPLIT = 1, Night Raid card, 1517 ms with
READ_OVERLAP 0 and 1529 ms with 1; run.sh READ_OVERLAP, new zlat.log):
- Both runs make the same 551 GPU writes, in the same order and with the
  same data.
- The 127,216 expansion bus requests are identical in order, address, byte
  enables and data, with two exceptions that depend on timing. The BIOS
  orders its security chip selects (0x84 and 0x88 to 1FA10300) by timing,
  as the clock phase sweep already showed. And the number of ATA status
  polls (1FB00007) while the card is busy changes with when the CPU asks.
- No watchdog reset and no I-cache race report in either run.
- Latency in this bench: flash reads ack after 18 cycles (105,437 of
  107,712) and card data port reads after 7 (18,432 of 19,033). a6's
  harness has its own channel 3 arbiter and card model, and there the card
  comes out at about 10.
- The BIOS flash phase (107,852 requests) takes 219.5 ms without overlap
  and 192.8 ms with it, 26.7 ms less: 12.4 cycles per request, as the
  bench table predicts at L = 18.
- The first card read phase (19,240 byte reads of the data port) takes
  48.9 ms and 45.9 ms, 3.0 ms less: 7.8 cycles per read, against 9 from
  the table at L = 7 (the phase also holds other work).
- With overlap the run starts the flash phase 21.7 ms later, because the
  security select order differs. It finishes it 4.9 ms ahead and stays
  4.8 ms ahead to the end. The 3.0 ms from the card phase does not carry
  over: the next stage waits for a frame.

Effect on Night Raid's NOTICE window (11.00 to 11.05 s):
- 29,978 ATA data port reads at 9 to 12 cycles saved, plus 384 1FA60000
  reads at 7: 272,000 to 362,000 of 2,499,998 cycles (10.9 to 14.5%). The
  window would take about 42.8 to 44.6 ms instead of 50.
- The window is a busy one, though. a6's zn.log has 336,000, 122,000,
  86,000, 246,000 and 35,000 data port reads in the half seconds from
  9.0 s to 11.06 s, about 333,000 a second averaged over 9.86 to 11.06 s.
  At that rate the saving is 3.0 to 4.0 million cycles a second, 6 to 8%
  of the time.
- Over the 4.8 s of NOTICE that is 0.3 to 0.7 s (my estimate, depending on
  which rate and which latency hold), so NOTICE comes to about 4.1 to
  4.5 s. If NOTICE has frame-paced stretches, as the BIOS card stage does
  in the system bench, part of that gain is absorbed.
- Option B takes off about 0.2 s more. MAME is 3.1 s; the PCB is
  unmeasured.
- The loading before NOTICE gains too: 981,000 data port reads between
  8.0 and 9.0 s, 0.18 to 0.24 s.

Effect on Ray Crisis's flash reads: during the bar, a6's zn.log has about
36,000 flash read steps a second. At 12.5 cycles each that is 0.45 million
cycles a second, 0.9% of the time, or about 0.15 s off the 16.9 s bar (my
estimate). The bar is RAM-load bound (60%), so read overlap barely moves
it; option B is the lever there.

### SDRAM address timing at 2:1 (z1fullb STA, 2026-10-06)

The GNET_Z1FULLB fit (gnet-full 936690a) failed setup on clk_cpu2x by
-0.129 ns at one endpoint. tools/sta/cpu2x_worst.tcl (6808a6a) on it
(builds/z1fullb_cpu2x) shows the paths. They are not the EARLY_READY data
path. All of them run from memorymux ram_ena (clk_cpu) into the SDRAM
address I/O registers on clk_cpu2x, with a 10 ns relationship (Slow
1100 mV 100C):

| endpoint | slack |
|---|---|
| SDRAM_A[7] | -0.129 |
| SDRAM_A[8] | +0.127 |
| SDRAM_A[11] | +0.618 |
| SDRAM_A[12] | +0.826 |

The next ones are the GTE result registers from ce (+0.84 and up).

The worst path:
- ram_ena q to the request decode (always1~0, fanout 47);
- then three more LUT levels (SDRAM_A[12]~3, Selector5~0, Selector5~1);
- then a 4.92 ns route to the DDIO output cell of A[7];
- 10.05 ns of data delay in all, 5.29 ns of it routing.

The cause is in sdram.sv's IDLE state. ch1_req (sdram_req & sdram_rnw) and
ch2_req (sdram_req & ~sdram_rnw) are both strobes from the CPU domain, and
they decide at the top of the request priority chain (refresh, DMA FIFO,
ch1, ch2, ch3). Every row address bit then passes the whole chain on its
way to the pin. The command pins are not in the list.

The fix (CLK_FAST_RATIO = 2 only; 3:1 keeps the upstream code):
- The IDLE state loads SDRAM_A and SDRAM_BA from idle_ab_rest. That is the
  same chain built from this domain's registers only: the DMA FIFO, ch1_rq,
  ch2_rq, ch3_rq, or hold.
- After the case statement, ch1_take_req and then ch2_take_req override
  the value with the ch1 or the ch2 row address. ch1_take_req is IDLE, no
  refresh due, the DMA FIFO empty, and ch1_req. ch2_take_req is the same
  with ch2_req, and with neither ch1_req nor ch1_rq.
- So a strobe reaches the I/O register through the last mux levels only.
- The function is the same edge for edge, with the same priority, so no
  CPU cycle changes. All other registers of the IDLE branches (cas_addr,
  chip, command, state and the rest) are as before.

Checks (NVC, nice -n 15):
- mem_lat at T_FAST 10 ns, r2p2 and r2p2e: mem_lat.txt is identical to the
  run before the change, line for line. That covers every latency row (RAM
  reads, writes, cache lines, BIOS, expansion) and the DMA phase.
- System bench (SPLIT = 1, Night Raid card, 915 ms, through the BIOS flash
  phase on ch3 and the first card phase) against the run before the change
  (62c7cce): zn.log (128,322 requests), zlat.log, gpu.log, sio.log and
  progress.log, with its DDR3 counts, are identical line for line,
  timestamps included.

Whether the restructured path meets 10 ns needs a fit. I can't run that
here. tools/sta/cpu2x_worst.tcl on the next fit shows it.
