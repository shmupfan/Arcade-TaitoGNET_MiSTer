# ZSG-2 RTL: status

Status: M3, ZSG-2 wavetable chip in RTL, verified against MAME 0.288 and
against MAME 0.288 with the 61c7940 fix, sample by sample and read by read
(2026-10-05). Not yet fitted; not yet connected to the MN10200 or the
TMS57002. Design: docs/zoom_zsg2_tms57002_design.md (the design study).
Own code throughout: I wrote it from the design study and MAME's
behaviour (zsg2.cpp, rank 5); nothing is taken from XelaNotPu's FX-1B core
(I did not open it).

## 1. Summary

- `rtl/zoom/zsg2*.sv`: SystemVerilog, 3 modules, 798 lines. One shared
  engine renders the 48 channels in turn, one 18 x 18 multiplier, three
  RAMs (registers, channel state, line buffers), a 64-bit prefetch line per
  channel for DDR3, a CPU write FIFO and the readback port.
- Verification: a Verilator replay of MAME traces of every ZSG-2 access
  with its sample position, comparing all four ZSG-2 outputs of every
  sample (taken from the TMS57002 serial inputs in MAME) and every CPU
  read.
- Result: 23.4 million samples and 1.38 million reads equal to MAME over
  six 120 s runs (raycris and psyvaria under both binaries, shikigam and
  nightrai under 61c7940), plus a 25 s canary under three memory timings.
  No divergence in any run (section 4.3).
- Directed tests against a Python model transcribed from the 61c7940
  zsg2.cpp (itself checked against MAME on 4.7 million samples): key-on at
  start address 0, wave addresses past 6 MB, gain bit 7, the output
  clamp, a Zoom reset with fetches outstanding, and a random fuzz; 460,026
  samples, all equal (section 4.6). They found one RTL bug, a line buffer
  valid-bit race at long memory latency, now fixed; every game replay was
  rerun after the fix with the same result.
- Register 0xB: the core returns vol >> 3 (`READB_SHIFT` = 3), as 61c7940
  does. Against 61c7940 traces it matches directly; against 0.288 traces it
  matches the 0.288 value shifted right by 3 in every read (section 4.4).
- Timing: the longest pass in the game runs is 769 clocks of the 1,040.45
  available per sample at 33.8688 MHz; a synthetic worst case (48 channels
  at the maximum pitch) takes 866. At that load the engine stays in real
  time up to about 40 clocks of memory latency per outstanding request
  (160 clocks with the default 4), section 5.
- Area: the first fit (my run of `ZSG2_FIT`, before 57c267d) met
  timing but built the register RAM from flip-flops (7,909 ALMs). I split
  it into four 16-bit RAMs; the rest of that fit projects to about 1,550
  ALMs, 9 M10K, 1 DSP, just over the 1,500 ALM checkpoint (section 6).
  Refit pending.

## 2. Files

| File | Content |
|---|---|
| `rtl/zoom/zsg2.sv` | Top: CPU interface, write FIFO, sequencer (reset sweep, register writes, key on/off, reads, the channel pass), datapath, RAMs |
| `rtl/zoom/zsg2_fetch.sv` | Prefetch request queue, memory port, readback fetch, line buffer fill |
| `rtl/zoom/zsg2_ram.sv` | Simple dual-port RAM, plain write enable (M10K template) |
| `tools/zsg2/zsg2_trace.lua`, `zsg2_trace.sh` | MAME oracle: ZSG-2 accesses with time and sample count, per-sample TMS57002 inputs, channel snapshots |
| `tools/zsg2/zsg2_events.py` | Trace to replay stream (sample positions, Zoom resets, expected outputs) |
| `tools/zsg2/zsg2_model.py`, `zsg2_model_check.py` | Python reference model transcribed from the 61c7940 zsg2.cpp, and its check against a MAME trace |
| `tools/zsg2/zsg2_directed.py` | Directed and random tests with a synthetic wave set (no game data) and the model's expected outputs and reads |
| `tools/zsg2/zsg2_stress.py`, `zsg2_latency_sweep.py` | Worst-case load with model outputs; memory latency sweep per `INFL` |
| `sim/zsg2/tb.cpp`, `build.sh`, `run.sh` | Verilator replay testbench with a DDR3 latency model and optional coverage counters |
| `ZSG2_FIT.qpf`, `.qsf`, `.sdc` | Area-check project for Quartus 17 (run by Lee, section 6) |

Game-derived files (flash images from tools/build_flash.py, traces, event
streams, logs) stay in `sim/zsg2/work/`, gitignored.

## 3. What is implemented

### 3.1 Interface

- CPU: `cpu_rd`/`cpu_wr` held until `cpu_ack`, word offset `cpu_addr[9:0]`
  (byte address bits 10:1 of 0x800000-0x8007FF), 16-bit data only, as the
  firmware uses it (design study 3.1). A write is queued and acknowledged
  in the next clock unless the FIFO is full (`zsg2.sv:191`, `:394`). A
  read waits until the pass for every tick already seen and every earlier
  write are done (`zsg2.sv:416-431`), so it returns what MAME returns at
  the same sample position.
- Time base: `sample_tick`, one pulse per output sample. Each write
  carries the count of ticks seen when it arrived (2 bits) and is applied
  only after those passes (`zsg2.sv:192`). Up to 3 ticks may be pending;
  a fourth sets `dbg_overrun` (`zsg2.sv:368`).
- Outputs: `out_send0..3` (reverb, chorus, left direct, right direct,
  clamped to 16 bits) and `out_si0..3`, the TMS57002 serial input words as
  taito_zm.cpp:205-208 routes them (sends 0 and 1 at 0.5) with SIM = 1
  (tms57002.cpp:927-931): si0/si1 = send x 128, si2/si3 = send x 256, 24
  bits (`zsg2.sv:632-635`). `out_valid` pulses once per pass.
- Wave memory: `mem_req`/`mem_addr[22:0]` (64-bit line index, held until
  `mem_ready`), `mem_rvalid`/`mem_rdata[63:0]` in request order, up to
  `INFL` (default 4, 1 to 8) outstanding. Line L is bytes 8L to 8L+7 of the three wave
  flashes stored contiguously as little-endian 16-bit words, so block 2L is
  `rdata[31:0]` (taitogn.cpp:578-592, design study 3.3). Blocks at or above
  `MEM_BLOCKS` (0x180000) read as 0 without a fetch, as MAME's read_memory
  does (zsg2.cpp:227-228).

### 3.2 Engine (one pass per tick)

Per active channel (`zsg2.sv:518-614`): read the state (3 words of 80
bits) and register words 0, 1 and 3 (4 registers each); step and advance
with MAME's 32-bit cur_pos wrap modelled in 17 bits (`nextpos`,
`zsg2.sv:112`); on an advance take the block from the line buffer and
decode four samples with the emphasis filter (one per clock); linear
interpolation, output filter with 32-bit wrap and the discharge at cutoff
0, volume, four sends with the gain ROM, each a product of the shared
multiplier (`zsg2.sv:304`); ramps on odd sample counts; write back; queue
the prefetch of the line the next advance needs. Inactive channels cost
one clock. All arithmetic follows zsg2.cpp:286-361 bit for bit; each MAME
guess listed in design study 3.8 is kept as MAME has it.

### 3.3 Prefetch and memory

- Each channel's state holds the line it last requested; the line buffer
  RAM holds the line last delivered with its tag. After each slot (and at
  key-on) the engine computes the block of the next advance, including the
  loop point, and queues a fetch when that line was not yet requested
  (`zsg2.sv:289`).
- If a block is not there when needed (late DDR3, or the CPU moved the
  loop or end), the pass waits for it (`P_MISS`, `zsg2.sv:562`) and sets
  the sticky `dbg_late`. I chose waiting over holding the last sample
  (design study 5.2) because it keeps the output exact whenever the pass
  still ends before the next tick; the replay with 1,500 clocks of latency
  stays bit-exact (sections 4.3 and 4.6).
- A line counts as present one clock after its write into the line
  buffer RAM, when the registered read port returns the new word
  (`zsg2.sv:389-393`). Before the fix the valid bit and the read data were
  one clock apart; the directed tests caught it (section 4.6).
- Readback (0x638/0x63A): each address write starts a fetch; a read of
  0x63C/0x63E waits for it (`zsg2.sv:511`). 0x628 reads 0, as in MAME
  (zsg2.cpp:588-591).
- A Zoom reset drops responses still owed by the memory (`drop`,
  `zsg2_fetch.sv:63-76`), checked in section 4.6.

### 3.4 Registers, key on/off, reset

- Channel registers live in four 256 x 16 RAMs, one per register lane
  with its own write enable, read together as one 64-bit word of 4
  registers (`zsg2.sv:139-150`), plus the 32 control registers MAME keeps in m_reg. Reads of
  registers 3, 9 and B return status, current cutoff and volume
  (zsg2.cpp:467-486); register B is shifted by `READB_SHIFT`
  (`zsg2.sv:504`).
- Key on and key off are applied channel by channel when the write is
  applied (`S_KEY`, `zsg2.sv:456`), with MAME's key-on state: cur_pos =
  start - 1, step_ptr = 0x10000, vol = 0, vol_delta forced to 0x400 until
  the next register F write, cutoff = register 8, filter state 0
  (zsg2.cpp:518-537).
- `rst` follows MAME's device_reset (zsg2.cpp:193-205): all channels off,
  all channel registers 0, vol, cutoff and the sample parity 0, readback
  address 0. Like MAME it keeps samples[], the emphasis state and the
  control registers; MAME plays the first block after a key-on against the
  previous note's last sample, so this matters for exactness.

## 4. Verification

### 4.1 Oracle and sample positions

`tools/zsg2/zsg2_trace.lua` taps the MN10200's 0x800000-0x8007FF window
(time, data, PC and the ZSG-2 m_sample_count from the save items) and the
TMS57002 data space, where the DSP program reads its delay RAM 19 times
per sample (design study 4.3). On the first read of each sample it logs
the TMS57002 `si` registers, which hold the four ZSG-2 outputs of that
sample scaled by the route gains (tms57002.cpp:928-931): every logged
value divides back to an integer.

I checked the position rule on a 25 s raycris canary (MAME 0.288,
811,028 logged samples) before scaling:

- TMS57002 sample k = floor(t x 32,552) and the ZSG-2 count differ by a
  constant per Zoom reset segment: 2,513 before the reset at 16.15 s,
  525,811 after it, in all 811,028 samples.
- Every read (2,970) satisfies floor(t x 32,552) - count = the same
  offset: an access at time t follows sample floor(t x 32,552) and
  precedes the next one.
- 252 of 29,817 writes in the second segment show a count one lower,
  because a write tap runs before the handler's stream update
  (zsg2.cpp:620). `zsg2_events.py` therefore places accesses by time and
  uses the count only to assign the reset segment.

The stream rate is 32,552 Hz, not 32,552.083: MAME computes it as
clock() / 768 in integers (zsg2.cpp:137).

### 4.2 Runs

Binaries: `/opt/homebrew/bin/mame` (0.288, register 0xB returns vol) and
`gnet_61c7940` (0.288 plus the one-line 61c7940 change, reports 0.288
(mame0288-dirty), built in the same patched tree, docs/r1_speed_study.md
6.1). 120 s
each, coin at 40 s, start, then fire and left/right; flash images from
tools/build_flash.py, identical to the MAME NVRAM in all four games.

### 4.3 Results

| Run | MAME | RTL READB_SHIFT | Samples compared | Output mismatches | Reads (reg B) | Read mismatches | Writes | Longest pass |
|---|---|---|---|---|---|---|---|---|
| raycris | 0.288 | 0 | 3,903,751 | 0 | 203,162 (183,494) | 0 | 721,145 | 694 |
| raycris | 0.288 | 3, compared with value >> 3, memory jitter | 3,903,751 | 0 | 203,162 (183,494) | 0 | 721,145 | 694 |
| raycris | 61c7940 | 3 | 3,903,751 | 0 | 203,040 (183,372) | 0 | 721,053 | 694 |
| psyvaria | 0.288 | 0 | 3,903,738 | 0 | 320,160 (279,144) | 0 | 986,516 | 769 |
| psyvaria | 61c7940 | 3 | 3,903,738 | 0 | 320,182 (279,166) | 0 | 986,599 | 765 |
| shikigam | 61c7940 | 3, memory jitter | 3,903,768 | 0 | 250,942 (244,582) | 0 | 849,019 | 319 |
| nightrai | 61c7940 | 3 | 3,903,767 | 0 | 82,856 (67,160) | 0 | 514,360 | 303 |
| raycris canary 25 s | 0.288 | 0, latency 24 / 1,500, and 3 with jitter | 811,028 | 0 | 2,970 | 0 | 29,824 | 221 / 998 |

After the register RAM split (section 6.1) I reran every row of this
table, every directed and fuzz run of section 4.6 and the two stress
loads at their tolerated latency (96 burst, 160 steady): all equal, same
longest passes. All rows were also run again after the line buffer fix of section 4.6
(raycris 61c7940 with jitter, psyvaria 61c7940 at 200 clocks latency):
identical results. Default memory model: 24 clocks latency, always ready. Jitter: 8 to 63
clocks and `mem_ready` low one clock in four. Each run covers the BIOS
segment, the Zoom reset from the main CPU, attract and play.

Coverage (61c7940, coverage build): psyvaria 22.8 million block advances,
22,406 loops, 785 end-of-sample stops, 3,418 key-ons with emphasis reset,
87,641 filter passes at cutoff 0, 36.9 million ramp steps; nightrai 49
loops, all of them stops. Output peaks: 21,551 (psyvaria), 20,516
(nightrai), no sample at the clamp. Channels keyed: 46 (raycris), 48 in
the other three games.

Not exercised by any trace: key-on with start address 0 (the 17-bit
wrap), blocks at or above 0x180000, gain bit 7 (inversion; the design
study found no game that sets it, 3.1), a 16-bit output clamp, and a
Zoom reset with fetches outstanding. Section 4.6 covers them.

First divergence: none. No output sample and no read differs in any run.

### 4.4 Register 0xB and the two MAME versions

- Against a 0.288 trace, the RTL with `READB_SHIFT` = 0 returns the logged
  value in all reads; with 3 it returns the logged value >> 3 in all reads.
  That is the patched-model comparison: 61c7940 changes only what the read
  returns ([MAME 61c7940 zsg2.cpp:477-479](https://github.com/mamedev/mame/blob/61c794064422682db7a1f8b3d58c21563333a9c8/src/devices/sound/zsg2.cpp#L477-L479)), not the chip state,
  so the expected 61c7940 value at the same state is the 0.288 value >> 3.
- Against 61c7940 traces, the RTL with 3 matches directly, and the
  firmware then sees what the core gives it.
- In the 0.288 traces, 48,743 of 183,494 register 0xB reads (raycris) and
  165,370 of 279,144 (psyvaria) are 0x2000 or more, which corrupts the
  driver's flag bits (design study 3.7). Under 61c7940 the largest values
  are 0x134B and 0x17B4, all below 0x2000.
- Firmware behaviour forks where the read values differ: raycris first
  reads a different value at sample 737,143 (22.6 s; 0x044F against
  0x0089) and first writes differently at sample 1,298,480 (39.9 s), where
  0.288 updates channel 5 register F and 61c7940 channel 39: the voice
  allocator picks another channel. Psyvaria first reads differently at
  sample 552,563 (17.0 s) and first writes differently at sample 637,994,
  where 61c7940 makes the write that 0.288 makes at 637,995. The 61c7940
  traces are therefore the board-level reference for the core.

### 4.5 Directed tests: reference model

`tools/zsg2/zsg2_model.py` is a line-by-line Python transcription of
[MAME 61c7940 zsg2.cpp](https://github.com/mamedev/mame/blob/61c794064422682db7a1f8b3d58c21563333a9c8/src/devices/sound/zsg2.cpp) with C integer behaviour (32-bit wrap,
int16 truncation, arithmetic shifts) and the 0.288 output clamp to
[-32768, 32767] (`put_int_clamp`, src/emu/sound.h:247 in my 0.288
tree). Test infrastructure only. I checked it against MAME before using
it: raycris canary (0.288 rule, 811,028 samples, 2,970 reads) and nightrai
120 s (61c7940 binary, 3,903,767 samples, 82,856 reads), all equal.

### 4.6 Directed tests: results

`tools/zsg2/zsg2_directed.py` writes a synthetic wave set (seeded random
blocks, plus a page of maximum positive and one of maximum negative
samples) and an event stream with the model's outputs and reads:

| Case | Stimulus |
|---|---|
| Key-on at start 0 | start 0 (cur_pos 0xFFFFFFFF in MAME), start 0 with end 0 and with end 1, positions near 0xFFFF, loop 0xFFFF, start past end, step 1; status, cutoff and volume polled every 5 samples |
| Past 6 MB | page 0x17 (last in range), 0x18 and 0xFF; page moved across 0x180000 and end moved under the playing position while playing; readback at 0x17FFFF, 0x180000, 0x3FFFFFFF and others, with 0x628 |
| Gain bits | bit 7 (inversion) on each send, bits 6:5 set, changed while playing |
| Clamp | 8 channels at full volume and gain on the loud pages, positive then negative saturation |
| Reset with fetches outstanding | 8 key-ons immediately followed by a Zoom reset, new voices on the same channels; a reset while playing |
| Fuzz | random channel and control register writes (including start, page and step corner values, cutoff 0), key on/off masks, reads of all 0x400 words, random gaps, occasional resets |

| Run | Samples | Writes | Reads | Resets | Mismatches | Notes |
|---|---|---|---|---|---|---|
| directed + 60,000 fuzz, latency 24 | 60,017 | 8,084 | 2,411 | 10 | 0 | |
| same, latency 1,500 | 60,017 | 8,084 | 2,411 | 10 | 0 | 4 resets with 9 requests outstanding |
| same, jitter | 60,017 | 8,084 | 2,411 | 10 | 0 | |
| directed + 400,000 fuzz, jitter | 400,009 | 49,664 | 11,135 | 37 | 0 | 4 resets with 4 requests outstanding |
| same, latency 300 | 400,009 | 49,664 | 11,135 | 37 | 0 | 18 resets with 29 requests outstanding |

Coverage of the 60,000 run (coverage build): 507 key-ons at start 0,
71,551 block advances past 0x180000, 928 stops, 1,088 loops; the model
reports 350 samples at the clamp (1,348 in the 400,000 run).

Bug found and fixed: at 1,500 clocks latency the first run failed from
sample 3. A channel waiting in `P_MISS` saw its valid bit set in the same
clock as the line buffer write, while the registered read still returned
the old word; with the RAM's initial tag 0 the wait ended on stale data
for a line 0 fetch. The game traces never hit it (no channel there waits
for line 0 of a never-filled buffer). Fix in `zsg2.sv:389-393`.

### 4.7 Which side is right

Where the RTL could differ from MAME it follows MAME, except register 0xB,
where 61c7940 is right on firmware evidence (design study 3.7) and the
core follows it. The remaining questions are about the hardware against
MAME (design study Z1 to Z7), not the RTL against MAME.

## 5. Timing

- Clocks per active channel: 14 without a block advance, 18 with one;
  inactive channels 1 (`P_SCAN`).
- Game runs: longest pass 769 clocks (psyvaria).
- Memory latency the engine tolerates (`zsg2_latency_sweep.py`): worst
  load of `zsg2_stress.py`, 48 channels at step 0x10000, 24 line fetches
  per sample, fixed latency, memory always ready, clocks at 33.8688 MHz.
  Tolerated means the longest pass stays within one sample period (1,040
  clocks). The output stayed exact in every run of the sweep (latency up
  to 512), because a late block makes the pass wait.

| `INFL` (requests outstanding) | Tolerated latency, steady state (key-ons one per sample) | Tolerated latency, burst (48 key-ons at once) | First failing latency tested (steady, burst) |
|---|---|---|---|
| 1 | 40 | 24 | 48, 32 |
| 2 | 80 | 48 | 96, 64 |
| 4 (default) | 160 | 96 | 192, 128 |
| 8 | 256 | 192 | 384, 256 |

- The steady-state limit follows the fetch rate: 24 lines per 1,040
  clocks with `INFL` in flight allows about 43 x `INFL` clocks. At game
  load (design study 5.2: 12 blocks per sample at the measured peak, 6
  lines) the limit is about 4 times higher.
- A key-on just before a tick makes the first pass wait for its block
  (the fetch starts at key-on). That costs latency clocks inside the pass,
  not exactness.
- Beyond the limit the passes overrun the sample period; the RTL holds up
  to 3 pending ticks before `dbg_overrun`. In the core that would lose
  real time.
- CPU reads wait for a running pass. Writes do not wait.

## 6. Area

### 6.1 First fit (Quartus 17, `ZSG2_FIT`, built from f7e0d25 and 2f7d391)

Reports: builds/20261005_1148_zsg2/ (my run, not committed),
per entity with tools/fit_entities.py:

| Entity | ALMs | Registers | M10K | DSP |
|---|---|---|---|---|
| zsg2 (own logic) | 1,326.5 | 919 | | 1 |
| zsg2_ram:u_regs (register RAM) | 7,909.0 | 16,448 | 0 | |
| zsg2_fetch:u_fetch | 204.2 | 343 | | |
| write FIFO (altdpram, MLAB) | 21.3 | 5 | | |
| u_state, u_lbuf | 0 | 0 | 2, 3 | |
| total | 9,461.0 | 17,715 | 5 | 1 |

Timing met at 33.8688 MHz: setup slack 11.035 ns, hold 0.258 ns, Fmax
54.08 MHz (slow 1100 mV 100 C model). The request queue was inferred as
altdpram as well.

The register RAM was not inferred: the map report lists no RAM message
for it at all, so Quartus 17 did not recognise the byte-lane write loop of
the old zsg2_ram (64 bits as 8 lanes of 8) and built 16,384 bits of
flip-flops. The fix (commit after 57c267d) uses four plain 16-bit RAMs
with one write enable each, the template already inferred for u_state and
u_lbuf. Behaviour is unchanged (a write touches one register, so one
lane); the full verification was rerun (section 4). The first refit
(from ca19cae) stopped in Analysis: Quartus 17 rejects the inline
`for (genvar ...)` loop (Error 10170 at zsg2.sv line 141), so the four
instances now sit in an explicit `genvar` and `generate` block
(`zsg2.sv:139-150`), and the verification was rerun again.

### 6.2 Projection after the fix

- Without the register RAM the first fit is 1,326.5 + 204.2 + 21.3 =
  1,552 ALMs, 919 + 343 + 5 = 1,267 registers, plus 4 M10K for the lanes:
  9 M10K, 1 DSP. That is over the design study's 1,500 ALM checkpoint
  (design study 6.5) by about 50 ALMs and over its 710 to 1,250 estimate.
  The refit will settle it.
- Trims available without changing behaviour: read the register fields
  straight from the RAM outputs instead of holding three 64-bit register
  words (192 flops and their load muxes), one shared mix adder instead of
  four, a combinational line buffer write register (87 flops in
  zsg2_fetch).

### 6.3 Paper figures before the fit

Method as design study 6.5:

- About 1,600 flip-flops: channel working registers and the three
  register words (about 560), mixer and output registers (160), masks
  (active, line valid, request valid: 144), fetch unit including the
  outstanding list and line buffer write register (about 360), CPU side,
  FIFO pointers and sequencer (about 150), and other datapath registers.
- Logic: decode shifter, emphasis, interpolation and filter adders,
  four 24-bit mix adders, two ramp units with get_ramp shifters, two
  nextpos comparators (the two uses share inputs), operand muxes, RAM
  address and data muxes, the sequencer.
- Estimate 950 to 1,400 ALMs, 7 M10K (registers 2 planned, now 4; state
  2, line buffers 3), 1 DSP, write FIFO (32 x 28) and request queue (64 x 29) in MLAB.
  The design study range was 710 to 1,250. Under the 1,500 ALM
  checkpoint either way.

## 7. Open items

1. Refit with the split register RAM (`tools/pc_build.sh zsg2`), then
   `tools/fit_entities.py output_files/ZSG2_FIT.fit.rpt --node 'zsg2$'`;
   check the map report's RAM summary for four u_regs instances. If the
   total stays above 1,500 ALMs, review the trims in 6.2 before
   integration.
2. Integration with the MN10200 (decision at the Zoom integration step):
   a read can wait up to one pass (769 clocks seen, 866 worst). The
   MN10200 pacer absorbs 64 machine cycles, about 347 clocks (`PACE_CAP`
   in rtl/zoom/mn10200.sv on branch mn10200-rtl). Whether the firmware's
   read rate loses real time needs the board-level run (M3 gate).
3. `sample_tick` from the MN10200 virtual cycle counter, 192 machine
   cycles per sample (design study 6.1), and the reset phase.
4. DDR3: the arbiter's latency and outstanding-request budget against
   the table in section 5 (decision at the Zoom integration step).
5. Design study questions Z1 to Z7 stand; all MAME guesses are kept.
