# ZSG-2 and TMS57002 (Taito Zoom) design study

Status: DESIGN STUDY (2026-10-05). No RTL. Targets: the Zoom ZSG-2 wavetable
chip and the TI TMS57002 effects DSP on the FC PCB, written in-house for the
G-NET core (PLAN.md 3.1, decision 2026-10-04) on the 5CSEBA6. Companion to
docs/mn10200_design.md (the Zoom CPU). The F0 budget counts XelaNotPu's
measured FX-1B figures for these two chips: zsg2 1,388.9 ALMs, 13 M10K,
1 DSP; tms57002 with its delay RAM 1,318.5 ALMs, 68 M10K, 2 DSP
(docs/f0_budget.md 2.1).

## Summary

- **Estimates.** ZSG-2 710 to 1,250 ALMs, 5 to 7 M10K, 1 DSP. TMS57002
  710 to 1,240 ALMs, 67 M10K (64 of them the delay RAM), 2 DSP. Output path
  and time base 60 to 140 ALMs. All three are paper figures (method in
  6.5). The two chips together (1,420 to 2,490) come in about 220 to 1,290
  ALMs under the measured FX-1B pair (2,707.4). With the output path added,
  the F0 projection becomes 33,307 to 36,607 ALMs (79.5 to 87.3%).
- **R8 answered (delay RAM).** The firmware programs ST0 = 0x0084AA in all
  six games: M = 0 (64K address space), SEL = 1 (8-bit port), WORD = 0
  (16-bit data), SRAM = 0 (DRAM) (TMS57002 User's Guide Table 3-15
  p.3-64, Figure 3-24 p.3-31). In that mode the DSP addresses 64 KB, which
  is 32K words of 16 bits and 1.007 s of delay at 32.552 kHz (Table 3-17
  p.3-68, Figure 3-57 p.3-69). The LC321664 (128 KB) is half used and
  MAME's 256 KB map is masked to 0xFFFF (tms57002.cpp:244). Cost: 64 M10K,
  as in FX-1B.
- **R11 answered (input scaling).** ST0 bit 3 is SIM = 1: 16-bit serial
  input, extended to 24 bits by appending 8 zero LSBs (p.3-60). MAME already
  applies exactly this (tms57002.cpp:927). The "range really low" TODO
  (taito_zm.cpp:25-27) is therefore about ZSG-2 levels, not the DSP input.
- **R12, new reading (needs-review).** The main CPU's Zoom "register" port
  looks like the MB87078 electronic volume programming protocol. The address
  writes 0x04 and 0x05 decode as MB87078 control words (channel 0 or 1,
  EN = 1). The data writes are 6-bit gains with 0.5 dB steps, where 63 is
  0 dB (MB87078 data sheet p.4). The games write 0x3F, 0x36 (xiistag) and
  0x30 (nightrai, shikigam). Under the data sheet's law that is 0, -4.5
  and -7.5 dB. MAME's linear (data & 0x3F) / 63 (taito_zm.cpp:159, 166)
  gives 0, -1.3 and -2.4 dB, so Night Raid and Shikigami are 5.1 dB louder
  in MAME than this reading predicts.
- **R26 (61c7940).** I disassembled the firmware's voice poll myself
  (raycris image, 0x0810A1 to 0x0810BC). It reads channel register 0xB,
  shifts it right 7 bits and ORs it into a byte whose bits 6 and 7 it
  preserves as flags. The driver can only work if the register stays below
  0x2000, so the chip returns at most 13 bits. MAME 0.288 returns the full
  16-bit volume (zsg2.cpp:477-480); 61c7940 returns vol >> 3
  (mame_61c7940/zsg2.cpp:477-479). The core follows 61c7940. The exact
  scale (>> 3) is MAME's choice and is marked needs-review (Z1).
- **ZSG-2 firmware use (raycris and psyvaria traces; the other four games
  share psyvaria's code variant, mn10200_design.md 3.2).** Every ZSG-2
  access is 16-bit. Channel register 0xB is the only channel register the
  firmware reads. All 48 channels are used. Key-on rewrites all 16
  registers of a channel. Pitch, filter target, both ramps and the volume
  target are updated about 820 to 1,230 times a second each. The firmware
  reads sample headers through the readback port (0x638 to 0x63E) and
  polls 0x628 before each read.
- **Two DSP programs exist across the six games** (byte-identical across
  games): program A (232 words) in all six, and program B (234 words) loaded
  later by both Psyvariar sets. A uses 26 mnemonics, B 21, 27 in all. They
  use no branch other than IDLE, no RPTK, no REF, no LPC/LPD host reads
  and no other serial output. They output only on SO1
  (domh so1_l/so1_r), the pair MAME routes to the speaker
  (taito_zm.cpp:201-202).
- **One crystal, one time base.** 25 MHz / 768 = 32,552.083 Hz per sample
  is exactly 192 MN10200 machine cycles and 384 TMS57002 instruction cycles.
  I propose to drive both chips from the MN10200's virtual cycle counter
  (mn10200_design.md 5.2). Sample boundaries then fall at fixed CPU cycle
  counts, which is how MAME places ZSG-2 register writes.
- **Bandwidth.** One 32-bit block (4 samples) per channel per output sample
  at most: 192 bytes per sample, 6.25 MB/s worst case. MAME measurements
  (frame-sampled, attract plus one credit) give 1.4 (raycris) and 3.7
  (psyvaria) blocks per sample on average, with peaks of 4.8 and 12.0. The
  wave data stays in DDR3 behind a per-channel 64-bit prefetch buffer.
- **MAME ramp cadence checked.** zsg2.cpp:360 increments m_sample_count once
  per stream update call, not once per sample. A probe of MAME 0.288 over
  30 s of raycris reads 32,551 to 32,552 increments per second, so in
  practice every call renders exactly one sample. The once-per-two-samples
  ramp is therefore deterministic, and the RTL can match it.

## 1. Sources and evidence

| Rank (evidence_sources.md) | Source | Settles |
|---|---|---|
| 3 | TMS57002 User's Guide (TI, 1992), `mister-arcade-survey/datasheets/tms57002/`, read from the page images; the OCR text is unreliable | Memories, status register layout (Fig. 3-24 p.3-31, Table 3-4 pp.3-32/33), host interface modes (Table 3-6 p.3-37) and protocols (pp.3-39 to 3-43), serial formats (pp.3-55 to 3-62), external RAM (pp.3-63 to 3-71), pins and CLKSEL (Table 2-2 pp.2-9 to 2-11), features (p.1-2) |
| 3 | Fujitsu MB87078 data sheet, Edition 2.0A (`datasheets/mb87078/`) | Control word layout, 0.5 dB gain law, reset to 0 dB (pp.3-4) |
| n/a (firmware) | Zoom program images (`zoomprog` from MAME NVRAM, six games) and MAME 0.288 traces of what they do: the MN10200 I/O traces of docs/mn10200_design.md 3.1 (raycris, psyvaria, 90 s), four new 120 s runs logging port 1 and the TMS57002 data port (psyvarrv, shikigam, nightrai, xiistag) and two 150 s runs sampling ZSG-2 channel state. Statistics only; images, listings and logs stay outside the repository | Which registers, values, rates, programs and modes the games use (sections 2.2, 3.2, 4.2, 4.3); the voice poll (3.7) |
| 4 | None found | PCB audio is the only evidence above MAME for the ZSG-2 (evidence_sources.md 2) |
| 5 | MAME 0.288 `src/devices/sound/zsg2.cpp/.h`, `src/devices/cpu/tms57002/*`, `src/mame/sony/taito_zm.cpp`, `taitogn.cpp`, and commit 61c794064422682db7a1f8b3d58c21563333a9c8 (links and md5s in docs/mame_sources.md) | ZSG-2 behaviour (no datasheet exists); the TMS57002 instruction semantics; board wiring as MAME models it |
| 6 | XelaNotPu `rtl/zsg2.sv`, `tms57002.sv`, `tms_delay_m10k.sv`, `taito_zoom_top.sv` (FX-1B core, https://github.com/XelaNotPu, read only, nothing copied) | Architecture and resource comparison only |

There is no ZSG-2 datasheet, no decap and no PCB audio in hand. For the
ZSG-2 the core follows MAME except where firmware evidence contradicts it
(3.7). Each MAME guess is listed in 3.8 with the evidence that would settle
it.

## 2. Board context

### 2.1 Signal flow (MAME's model, taito_zm.cpp:186-209)

```
MN10200 --16-bit bus 0x800000--> ZSG-2 --4 x 16-bit, 32.552 kHz--> TMS57002 --SO1 L/R--> MB87078? --> uPD6379 DAC --> analogue mix with ZN-2 SPU
   |  \--8-bit port 0xC00000 + port 1 PLOAD/CLOAD ------------------> TMS57002 host interface
   |  <--IRQ1 pin = TMS57002 EMPTY, inverted (polled through FC57)
main CPU --0x1FB80000 port--> volume (MAME: TMS output gain; 2.4: MB87078?)
```

- ZSG-2 outputs 0 (reverb send) and 1 (chorus send) feed TMS57002 inputs 0
  and 1 at a route gain of 0.5; outputs 2 and 3 (left and right direct)
  feed inputs 2 and 3 at 1.0 (taito_zm.cpp:205-208). The 0.5 is a MAME
  choice with no comment (Z7).
- The dry path therefore also passes through the DSP: program A reads all
  four inputs (dis si0_r, si0_l, si1_l, si1_r at PMEM 2 to 5) and writes
  only so1_l and so1_r (PMEM 132 and 151; 134 and 153 in program B). The
  Zoom output is the DSP output.
- MAME mixes the Zoom output at 1.0 and the SPU at 0.3
  (taitogn.cpp:441-448). R13 remains open.

### 2.2 Clocks

| Signal | Value | Source |
|---|---|---|
| ZSG-2 clock | 25 MHz, pin 99 | taito_zm.cpp:13 |
| Sample rate | 25 MHz / 768 = 32,552.083 Hz | zsg2.cpp:137 |
| TMS57002 CLKIN | 12.5 MHz (25/2), pin 11 | taito_zm.cpp:16; pin 11 = CLKIN on the QFP (Table 2-2 p.2-10) |
| LRCK | 32.5525 kHz, pins 5 (LRCKO) and 76 (LRCKI) | taito_zm.cpp:17 |
| BCK | 1.5625 MHz (25/16), pins 75 (BCKI) and 2 (BCKO) | taito_zm.cpp:18 |
| MN10200 | 12.5 MHz OSCI, 6.25 MHz machine cycle | mn10200_design.md 6.1 |

Cross-checks:

- BCK / LRCK = 48. That is SOM = 2 (16-bit words, 48 BCKO per LRCKO,
  Table 3-14 p.3-61), and the firmware's ST0 has SOM = 2. The board
  measurement and the firmware agree.
- The manual gives an 80 ns instruction cycle (p.1-2), which is 12.5 MHz.
  CLKSEL = 0 halves CLKIN, CLKSEL = 1 uses it directly (Table 2-2 p.2-10).
  Program A runs 231 instructions before IDLE. Under CLKSEL = 0 only 192
  machine cycles fit in a sample (6.25 MHz / 32,552 Hz), so 231 could not
  run. CLKSEL must therefore be 1 (inference, Z8). 384 instruction slots
  per sample, as in MAME (tms57002.cpp:894, one icount per instruction at
  12.5 MHz).
- Per sample: 768 ZSG-2 clocks, 384 TMS57002 cycles, 192 MN10200 machine
  cycles. 768 / 48 channels is 16 clocks per channel. That suggests a
  16-clock channel slot inside the ZSG-2, but it is inference only.

### 2.3 MN10200 interface (taito_zm.cpp:114-125; firmware use from the traces)

| Address | Device | Firmware use |
|---|---|---|
| 0x800000-0x8007FF | ZSG-2, 16-bit | raycris 90 s: 489,155 writes, 133,038 reads, all with mask 0xFFFF; psyvaria 724,716 and 235,276 |
| 0xC00000 | TMS57002 data port, 8-bit | Writes only (no reads in either trace) |
| Port 1 (0xFE64) bits 0, 1 | TMS57002 PLOAD, CLOAD (active low, taito_zm.cpp:104-112) | 4.2 |
| Port 1 bits 2, 4, 5 | unknown (MAME: "0x9F at most games") | Bit 2 goes from 0 to 1 about 1 s after reset release. About 11 times in 90 s, near music changes, the port goes to 0x0F (bit 4 low) and then 0x3F (bit 5 high) before returning to 0x1F. Candidates are the TMS57002 MUTE or RS pins (Z16) |
| IRQ1 pin | TMS57002 EMPTY, inverted (taito_zm.cpp:198) | Polled through FC57 (mn10200_design.md 4.1); never enabled as an interrupt |

The ZSG-2 and TMS57002 raise no interrupts in MAME. The Zoom reset
(main-CPU control bit 4, taitogn.cpp:519-533) resets both
(taito_zm.cpp:73-79). The release also writes 0xFF (read array) to U27 and
the three wave flashes. MAME's comment calls that an assumption.

### 2.4 Output level: MB87078 reading of the volume port (R12)

The main CPU writes the port as address 0x04, data, address 0x05, data
(zoom.log in sim/oracle, all six games). MAME's reg_address_w keeps the low
byte (taito_zm.cpp:174-177), so the 16-bit writes 0x0404 and 0x0505 select
4 and 5. The data words are 0x3F3F everywhere, plus 0x3636 in xiistag
(133.11 s) and 0x3030 in nightrai and shikigam.

MB87078 protocol (p.4): with DSEL high, D0-D1 select the channel, D2 = EN,
D3 = C0 and D4 = C32. With DSEL low, D0-D5 carry the gain GD0-GD5, in
0.5 dB steps from 63 = 0 dB down to 0 = -31.5 dB. EN = 0 mutes. Reset gives
0 dB.

Read as MB87078 words, 0x04 is channel 0 with EN = 1 and 0x05 is channel 1
with EN = 1. The data are 6-bit gains, consistent with MAME's popmessage on
bits 0xC0C0 (taito_zm.cpp:157, 164). The address/data pairing matches the
DSEL high then DSEL low sequence in Figure 2 (p.6). What I have not
established:

- which address line drives DSEL;
- whether channels 0 and 1 attenuate the Zoom output alone or the final
  mix (Z10).

Proposal: implement the gain as the data sheet law (a 64-entry table of
0.5 dB steps), with MAME's linear law as an OSD or debug option for oracle
comparison. Both are parameters until PCB audio settles it.

## 3. ZSG-2

### 3.1 Register map (zsg2.cpp:13-48, 365-465, 514-607)

Channel registers: 48 channels x 16 words at byte offset ch x 0x20.
Register r is at byte 2r.

| Reg | Bits (MAME) | Firmware writes (raycris, 90 s) |
|---|---|---|
| 0 | hi: start address low; lo: unknown | At key-on only (1,120), low byte always 0 |
| 1 | hi: page (address bits 23:16 of the 32-bit word index); lo: start address high | At key-on; pages up to 23 used (raycris), so all three flashes |
| 2 | none | Always 0 |
| 3 | status (bit 15 = active, read-only to the CPU) | Always 0x0400 ("unknown bit, always set") |
| 4 | frequency: step = data + 1, in 1/65,536 of a 4-sample block per output sample | 60,316 (up to 0xF7A0, about 3.9x) |
| 5 | hi: right direct gain (send 3); lo: loop address low | At key-on |
| 6 | end address | At key-on |
| 7 | hi: left direct gain (send 2); lo: loop address high | At key-on |
| 8 | filter cutoff, initial (latched at key-on) | At key-on |
| 9 | filter cutoff, current | 0 at key-on |
| A | volume, initial (MAME ignores it, 3.5) | At key-on (up to 0x6802; psyvaria 0xBDA1) |
| B | volume, current; the only register read (3.7) | 0 at key-on; read 119,598 times |
| C | filter cutoff target | 60,316 |
| D | hi: chorus send gain (send 1); lo: filter ramp | 60,316 |
| E | volume target | 61,706 (up to 0x9A5B; psyvaria 0xBDA1) |
| F | hi: reverb send gain (send 0); lo: volume ramp | 61,706 |

Every gain byte written has bits 7:5 clear (send gains 0x00 to 0x1F). So
MAME's guessed bit 7 phase inversion (zsg2.cpp:342-343) is never exercised
by these games.

Control registers (byte offset from 0x600):

| Offset | Function (MAME) | Firmware use (raycris) |
|---|---|---|
| 0x600-0x604 | key on, one bit per channel, 16 channels per word | 1,120 writes each |
| 0x608-0x60C | key off | 155,670 writes, each with exactly one bit set: the driver keys off channel by channel, often channels already stopped |
| 0x618, 0x61A, 0x620, 0x628 | unknown; MAME stores them (zsg2.cpp:576-579) | Written once per Zoom reset: 0x5CBC, 0x5CBC, 0x0128, 0x0066 |
| 0x628 (read) | "memory bus busy?"; MAME returns 0 (zsg2.cpp:588-591) | Polled before each readback: 4,480 reads |
| 0x630 | unknown | 0x0001 about every 16 ms (4,477 writes); one of the writers is the end of the voice poll loop (3.7). Z6 |
| 0x638 / 0x63A | readback word address bits 13:0 (from data >> 2) and 29:14 (zsg2.cpp:566-574) | 4,480 each |
| 0x63C / 0x63E (read) | readback data low and high 16 bits | 4,480 each; sample headers (max word 0x17001F, that is byte 0x5C007C, within the third flash) |

MAME rejects accesses that are not 16-bit (zsg2.cpp:614-618). The firmware
makes none, so the RTL decodes only full words.

### 3.2 What the firmware does

- **Key-on.** It writes all 16 registers of a channel, then the key-on
  bit. Registers 9 and B are written 0, register 3 0x0400 and register 2
  0. Raycris does this 1,120 times in 74 s of Zoom run time; psyvaria
  3,061 times.
- **Continuous updates per active channel.** Pitch (4), filter target (C)
  with filter ramp and chorus gain (D), and volume target (E) with volume
  ramp and reverb gain (F). Ramp bytes are mostly 0x17. 0x78 and 0xF8
  appear at key-on.
- **Voice allocation.** A loop over all 48 channels reads register B twice
  per channel (3.7). Raycris runs it about 1,250 times in 74 s.
- **Sample headers.** It reads them through the readback port after
  polling 0x628.
- **Channels.** Raycris used 46 and psyvaria all 48. Measured activity
  (sampled every frame from 20 s to 150 s, 5.2): raycris 8.2 active channels
  on average, peak 27; psyvaria 12.2, peak 30.

### 3.3 Sample memory and format

- Address. A channel's sample word address is page | cur_pos, with page in
  bits 23:16 and cur_pos in 15:0 (zsg2.cpp:270, 379). Units are 32-bit
  blocks of 4 samples, so one page is 256 KB.
- G-NET mapping (taitogn.cpp:578-592). Word index W reads flash
  W >> 19 (U56, U55, U29 for 0, 1, 2) at 16-bit index (2W) & 0xFFFFF
  (low half) and +1 (high half). Chip 3 returns 0, and W >= 0x180000
  returns 0 (zsg2.cpp:227-228). With the three 2 MB images stored
  contiguously in DDR3 as little-endian 16-bit words, block W is the 32-bit
  little-endian word at byte 4W. The MAME NVRAM files store each word
  byte-swapped (mn10200_design.md 3.1), so the loader swaps them.
- MAME reads through the flash device (intelfsh read), so a flash left in
  ID or status mode would feed status bytes to the ZSG-2. In the oracle
  runs the wave flashes see commands only during the first-boot copy (for
  example psyvaria: last wave write 126.25 s, Zoom volume set 133.79 s).
  The RTL reads the array directly (Z14).
- Decode (zsg2.cpp:74-83, 249-262). The 32-bit little-endian block is
  `42222222 51111111 60000000 ssss3333`. Samples 0 to 2 are the 7-bit
  fields; sample 3 is assembled from bits 31, 23, 15 and 3:0. Each 7-bit
  value is placed in bits 15:9 of a 16-bit word, then arithmetic-shifted
  right by s. That is the 2:1 compression. A block of 0 decodes to four
  zeros, the same as the zero block MAME substitutes (zsg2.cpp:240-241).

### 3.4 Per-sample voice pipeline (MAME 0.288, zsg2.cpp:286-361)

For each active channel, per output sample:

1. **Step.** step_ptr += step (17-bit). On a carry out of bit 15:
   cur_pos += 1. If cur_pos >= end, then cur_pos = loop. If loop + 1 >=
   end at that point, the voice stops: vol = 0, active cleared, no output.
   If cur_pos == start, the emphasis state resets to 0. Then step_ptr &=
   0xFFFF and the new block is decoded (zsg2.cpp:298-319). At most one block
   advance per sample, because step <= 0x10000.
2. **Emphasis filter**, per decoded sample at block load (zsg2.cpp:268-280):
   state += raw - ((state + 0x20) >> 6); out = clamp16(state >> 1). Four
   outputs go to samples[1..4]; samples[0] keeps the previous block's last
   sample. The constants are MAME tuning ("-6 dB at 81.5 Hz", zsg2.cpp:102-111).
3. **Interpolation** (zsg2.cpp:321-325). pos = step_ptr[15:14];
   s = samples[pos] + ((step_ptr << 2 & 0xFFFF) x int16(samples[pos+1] -
   samples[pos])) >> 16. The difference is truncated to int16 before the
   multiply, so it wraps when the two samples differ by more than 32,767.
4. **Output filter** (zsg2.cpp:328-333). f += (s - (f >> 16)) x cutoff, in
   int32 with wraparound; s = f >> 16. If cutoff == 0, then f >>= 1.
5. **Volume** (zsg2.cpp:335). s = (s x vol) >> 16.
6. **Sends** (zsg2.cpp:337-346). For each send n: mix[n] += (+/-s x
   gain_tab[g & 0x1F]) >> 16, where gain_tab[i] = 65,535 x 10^(-(31 - i)/20)
   and gain_tab[0] = 0 (zsg2.cpp:148-154). That is MAME's "-1 dB per step"
   assumption.
7. **Ramps.** On odd m_sample_count (zsg2.cpp:350-354): vol and cutoff
   step toward their targets with clamping (zsg2.cpp:501-510).
   get_ramp(byte) = ((sext4(byte) ^ 8) << (byte >> 4)) >> 4
   (zsg2.cpp:494-499). MAME describes it as an approximate inverse of a
   CPU lookup table.

After all channels, each send is clamped to 16 bits (zsg2.cpp:358).

Ramp cadence check. m_sample_count is incremented once per
sound_stream_update call (zsg2.cpp:360, outside the per-sample loop). That
matches per-sample parity only if every call renders one sample. I read
m_sample_count through the MAME Lua save-item interface every 6 frames
over 30 s of raycris. It advances 32,551 to 32,552 per second, the sample
rate, in every 1 s window. It is reset to 0 at the Zoom reset (16.15 s), as
zsg2.cpp:205 does. The synchronous TMS57002 consumer
(tms57002.cpp:925, 971) pulls one sample per call. So MAME 0.288's cadence
is "ramp on every odd sample since the last Zoom reset". The RTL keeps a
parity bit cleared by the Zoom reset.

### 3.5 Key-on and key-off (zsg2.cpp:518-554)

- **Key-on.** active = 1, cur_pos = start - 1, step_ptr = 0x10000 (so the
  first sample loads the start block), vol = 0, vol_delta = 0x0400,
  cutoff = cutoff_initial, output filter state = 0.
- The initial volume register (A) is ignored, "because it causes lots of
  clicking" (zsg2.cpp:530-531). vol_delta is forced to 0x0400 until the
  next register F write. Both are MAME guesses (Z2).
- **Key-off.** vol = 0, active = 0. This is immediate, with no release.
  The firmware ramps the volume target down itself through registers E/F
  before keying off. The trace shows the target updates; whether they reach
  0 before each key-off was not checked.

### 3.6 Output word and the TMS57002 input

- The ZSG-2 delivers four 16-bit words per sample. MAME scales sends 0 and
  1 by 0.5 at the route (2.1).
- The TMS57002 takes 16-bit serial words (SIM = 1). With the
  << 8 alignment, a ZSG-2 value v reaches the DSP as v x 128 (sends 0, 1)
  or v x 256 (sends 2, 3) in 24-bit fixed point. MAME computes this
  through float, exactly, since every factor is a power of two
  (tms57002.cpp:927-931).
- RTL: an arithmetic shift right by 1 on sends 0 and 1 (MAME default),
  kept as a parameter (Z7).

### 3.7 The 61c7940 fix (R26)

What the commit does. It changes channel register 0xB reads from `return
m_chan[ch].vol` (0.288, zsg2.cpp:477-480) to `return m_chan[ch].vol >> 3`
(mame_61c7940/zsg2.cpp:477-479). The commit message (GitHub API, author
superctr, 2026-09-14, PR #16134) says:

- the G-NET driver polls register 0xB every tick and stores value >> 7 in a
  per-channel byte;
- bits 6 and 7 of that byte are "held" and "priority" flags used by the
  voice stealer;
- with 16-bit values, every note at volume 0x4000 or more set the priority
  flag, and the stealer cut audible notes in Shikigami sound test 05.

What I verified in the firmware (raycris zoomprog, private listing,
0x081090 to 0x0810D7). The loop walks 48 channels from a0 = 0x800000 in
steps of 0x20. At 0x08109D it reads (22,a0), which is register 0xB, into a
work slot. At 0x0810A1 to 0x0810A5 it masks the channel's state byte with
0xC0, keeping bits 7:6. At 0x0810A9 it reads register 0xB again. It shifts
right 2 + 5 = 7 bits, ORs into the byte and stores it with movb at
0x0810BC. After the loop it writes 1 to 0x800630.

- The read PCs match the trace exactly: 0x08109E/0x0810AA in raycris;
  psyvaria's variant at 0x081096/0x0810A1.
- The code keeps the flags by masking and then ORs the level into the same
  byte. It is only correct if value >> 7 < 0x40, that is, value < 0x2000.

Evidence on the volume values themselves:

- The firmware writes 16-bit targets (register E up to 0x9A5B in raycris
  and 0xBDA1 in psyvaria), so the internal volume is wider than 13 bits on
  the write side.
- In the raycris trace, 36% of 0.288's register 0xB reads are 0x2000 or
  more, which sets the "held" bit (43,466 of 119,598), and 13% are 0x4000
  or more, which sets the "priority" bit (15,368). The corruption happens
  in every game, not only in Shikigami.

Decision: the core returns a 13-bit value. Whether the chip returns the
top 13 bits of a 16-bit volume (vol >> 3, as 61c7940 does) or keeps a
13-bit internal volume with some other relation to the targets is not
settled by firmware. The level only ranks voices, so >> 3 is the working
choice. It is a classified divergence from 0.288 (Z1; PCB audio of the
Shikigami intro would show whether the stealing happens).

Consequence for the oracle: the MN10200 consumes the value, so firmware
behaviour diverges from 0.288 at the first nonzero register 0xB read.
Board-level comparison therefore needs a MAME with 61c7940 (7.1).

### 3.8 MAME guesses the core follows by default (R10)

Each item is a MAME default parameter in the RTL until PCB audio exists:

- emphasis filter constants (zsg2.cpp:102-111, 275-278);
- linear interpolation (zsg2.cpp:324: "hardware certainly does something
  similar");
- the output filter form and the discharge at cutoff 0 (zsg2.cpp:327-333);
- the gain table law (-1 dB per step) and bit 7 inversion
  (zsg2.cpp:148-154, 342);
- key-on volume handling (3.5);
- ramp every other sample and get_ramp (zsg2.cpp:348-354, 488-499; the
  source table is in the sound CPU ROM, Z4);
- send scaling (Z7);
- immediate key-off.

Making each a switch costs a few ALMs each. Most are constants inside the
datapath.

## 4. TMS57002

### 4.1 Programming model (manual chapter 3; MAME tms57002.h)

| Resource | Size | Notes |
|---|---|---|
| PMEM | 256 x 24 | Program; loaded by the host (p.3-39) |
| CMEM | 256 x 32 | Coefficients; host download or live update through 16 UPDATE registers (pp.3-41 to 3-43) |
| DMEM0 / DMEM1 | 256 x 24 / 32 x 24 | Data, circular through BA0/BA1 (decremented and incremented at sync, p.3-36) |
| ST0, ST1 | 24 bits each | Fig. 3-24 p.3-31 |
| ALU | 32-bit AACC | |
| MAC | 25 x 32 multiplier, MACC accumulator (MAME masks 52 bits, tms57002.cpp:954) | p.1-2 |
| External RAM | 64K/256K/1M address space, 4- or 8-bit port, 16- or 24-bit words, DRAM or SRAM; ring buffer with XBA (decremented at sync) + XOA (from CMEM bits 18:0) | pp.3-63 to 3-71 |
| Serial | SI0/SI1 and SO0/SO1, stereo each | pp.3-48 to 3-62 |

Sync, from SYNC pin 80 (Table 2-2 p.2-11), sets PC = CA = ID = 0. If
INCS = 0 it also does BA0-- and BA1++, and it clears AOV and MOV
(p.3-36), and XBA is decremented (p.3-66; tms57002.cpp:218-235). What drives SYNC on the
FC PCB is unknown (Z8). MAME syncs once per sample.

### 4.2 Host interface use

The manual's modes (Table 3-6 p.3-37) are PLOAD/CLOAD = 1/1 normal, 0/1
ST0/ST1/PMEM download, 0/0 CMEM download, 1/0 CMEM update. Port 1 values in
the traces:

| Port 1 | PLOAD, CLOAD | Use |
|---|---|---|
| 0x1B, 0x1F | 1, 1 | Idle |
| 0x1A | 0, 1 | ST0, ST1, then PMEM, 3 bytes each, MSB first (p.3-40) |
| 0x18 | 0, 0 | CMEM, 4 bytes each (p.3-41) |
| 0x19, 0x1D | 1, 0 | CMEM update |

The sequence at every Zoom reset and song or program change is: PMEM
download (702 bytes = ST0, ST1, 232 words), CMEM download (340 bytes = 85
words), then updates. Downloads happen 3 times in 90 s of raycris and
psyvaria. Every update episode is exactly 5 bytes, one SA byte and one
32-bit word (raycris 1,486,955 bytes in 297,391 episodes, about 4,000 per
second). The manual allows up to 16 words per episode (p.3-42). MAME
accepts only one per SA byte (tms57002.cpp:136-157). The difference never
matters for these games.

Update timing differs between the two:

- The manual applies UPDATE0 at the first CMEM read of address SA after
  CLOAD returns high (p.3-43).
- MAME queues the word as soon as its fourth byte arrives, with the comment
  "the write shouldn't really happen until CLOAD is high though"
  (tms57002.cpp:146). It applies it at the next CMEM read of SA
  (tms57002.cpp:683-697).

The RTL follows the manual: the word is held until CLOAD rises. The
difference is at most the few MN10200 instructions between the fourth
byte and the port write. It changes which sample an update lands in only
rarely (Z9; verification 7.3 aligns on MAME's point).

EMPTY is high when all 16 UPDATE registers are empty (Table 2-2 p.2-11).
The firmware polls it, through the inverted IRQ1 pin, before each update.

### 4.3 The microcode

Two programs across the six games, byte-identical within each game:

| Program | Games | ST0 | ST1 | PMEM | First IDLE | CMEM | External accesses per sample |
|---|---|---|---|---|---|---|---|
| A | all six (raycris, psyvaria, psyvarrv, shikigam, nightrai, xiistag) | 0x0084AA | 0x008020 | 232 | 231 | 85 | 19 RDE, 8 WRE |
| B | psyvaria, psyvarrv (loaded later; psyvaria at 9.94 s) | 0x0084AA | 0x000020 | 234 | 233 | 108 | 19 RDE, 8 WRE |

ST0 = 0x0084AA (Fig. 3-24, Table 3-4):

- DIRI = 1 and DIRO = 1 (MSB first in and out);
- SIM = 1 (16-bit input);
- PLRI = 1;
- SOM = 2 (16-bit output, 48 BCK);
- SEL = 1 (8-bit external port);
- M = 0, WORD = 0, SRAM = 0, INCS = 0, FI = 0, FO = 0, CNS = 0.

ST1 = 0x008020: MOVM = 1 (MACC saturates), RND = 1 (MAME: round at 32
bits); program B has RND = 0. SFAI, SFAO, SFMA, SFMO, CRM, DBP and CAS are
all 0.

Mnemonics in program A, with counts (cat 2 secondary instructions marked
(2)):

- MAC and data moves: mac 36, mpy 26, smhd(2) 25, rde 19, srbd(2) 19,
  sacc(2) 11, add 10, lacd 10, lmhd 8, wre 8, sfmo(2) 7, lcak 6, lacc 5;
- serial: dis(2) 4, domh(2) 2;
- the rest: abs 2, sub 2, sacd(2) 2, slmh(2) 2, sfmr 2, slml(2) 2, and 2,
  lirk 1, saom(2) 1, raom(2) 1, idle 1.

Program B adds smhc(2) and drops sub, sacd, slmh, sfmr, slml and and.
No branch instruction except IDLE. No RPTK, REF, LPC/LPD, host reads,
DIM, DOS or DOML.

I classified the instructions with a script that reads MAME's tmsinstr.lst
categories (tms57kdec.cpp: cat 3 when bits 23:18 are all 1, otherwise cat 1
from bits 23:18 and cat 2 from bits 17:11). The microcode itself is not
stored or committed.

### 4.4 External delay RAM (R8)

- Mode M = 0, SEL = 1, WORD = 0. That is case 1 of Figure 3-57 (p.3-69):
  16-bit data in 2 fetches of 8 bits. The 16-bit address is XBA + XOA
  (15 bits) plus one fetch bit, output as row and column on EA7-EA0
  (Table 3-17 p.3-68; EA9 and EA8 stay 0).
- Capacity: 32,768 words of 16 bits = 64 KB = 1.007 s at 32,552 Hz.
- MAME masks the byte address with 0xFFFF (tms57002.cpp:242-256) and reads
  2 bytes per word, taking the high byte first and padding the 24-bit XRD
  low byte with 0 (tms57002.cpp:279-296).
- The LC321664 is 64K x 16. With an 8-bit port only one byte lane carries
  data per fetch, so at most 64 KB of it is used, whatever the wiring.
  MAME's 256 KB map (taito_zm.cpp:127-130) is never reached.

Access cost on the chip: a 16-bit word through an 8-bit DRAM port takes 6
machine cycles, and up to 42 words fit per sample at 48 kHz
(Table 3-18 p.3-71). At 32.55 kHz, 384 / 6 = 64 words fit. The program
uses 27. REF is unused: a program that walks 256 rows within 4 ms needs no
refresh (p.3-70).

Initial contents are DRAM noise on the PCB. MAME's data space is RAM that
starts at 0, as far as I can tell (needs-review, Z13). XelaNotPu's file
mentions captures with a "TMS_ZEROINIT" option
(tms_delay_m10k.sv:38-41), which suggests a patched MAME. The RTL clears
the M10K at reset (it is configured to 0 anyway).

### 4.5 Output word

- SOM = 2 sends 16-bit words (Table 3-14 p.3-61) to the uPD6379 16-bit DAC
  (hardware_inventory.md 2).
- MAME's domh writes (MACC >> 24) & 0xFFFFFF, 24 bits, into so[]
  (tmsinstr.lst:129-131), and the stream carries all 24 bits
  (tms57002.cpp:933-936).
- The RTL emits 16 bits: the top 16 of the 24 that MAME carries, truncated.
  Whether the chip rounds there is unknown. The difference is below 1 LSB
  of 16 bits, a classified divergence (Z15).

### 4.6 MAME details the RTL must reproduce

- **Pipeline.** MACC results are visible two instructions later:
  macc_read and macc_write lag by one each (tms57002.cpp:860-861;
  manual p.3-28 note).
- **Status bit 3.** ST1 bit 3 is AOVM in MAME, marked "undocumented!"
  (tms57002.h:81), and reserved in Fig. 3-24. Both programs leave it 0, so
  it does not matter here.
- **CRM.** crm() returns 0 while the UPDATE FIFO is not empty
  (tms57kdec.cpp:43-47). CRM is 0 in both programs anyway.
- **External RAM sequencing.** One byte per instruction (xm_step_read and
  xm_step_write once per executed instruction, tms57002.cpp:852-858). A
  word needs 2 instructions, against 6 machine cycles on the chip.
  Whether the programs leave enough instructions between each rde and its
  srbd for the chip's timing is not yet checked; the replay (7.3) reports
  the spacing. A faster or slower completion only matters if an srbd comes
  too early.

## 5. Memory and bandwidth

### 5.1 Placement

| Item | Size | Place | Reason |
|---|---|---|---|
| Wave flashes U56, U55, U29 | 6 MB | DDR3, shared with the main CPU's flash bank window (gnet_glue_design.md 3) | Too large for anything else |
| ZSG-2 CPU registers | 768 x 16 | 2 M10K (true dual port: CPU and engine) | |
| ZSG-2 channel state | 48 x about 290 bits | 2 M10K (384 x 40) | Flops would cost several thousand ALMs (XelaNotPu's estimate is about 4,800 ALMs, zsg2.sv:20-24) |
| ZSG-2 prefetch lines | 48 x 2 x 64 bits | 1 to 2 M10K | 5.2 |
| TMS57002 PMEM, CMEM, DMEM0 | 256 x 24, 256 x 32, 256 x 24 | 3 M10K | |
| TMS57002 DMEM1, UPDATE FIFO, serial registers | 32 x 24, 16 x 32, 8 x 24 | MLAB | |
| TMS57002 delay RAM | 32K x 16 | 64 M10K (512 x 16 mode) | 27 accesses per sample; DDR3 latency would need a cache, which XelaNotPu built and then removed (tms_delay_m10k.sv:13-19) |

### 5.2 Bandwidth per output sample

Each channel advances at most one block per output sample (step <=
0x10000, 3.4). A DDR3 read on MiSTer returns 64 bits, which is 2 blocks.

| Case | Blocks per sample | Bytes per sample | DDR3 64-bit reads per second |
|---|---|---|---|
| Worst case (48 channels at maximum pitch) | 48 | 192 | 0.78 M (one line per channel every 2 samples) |
| Firmware maximum written pitch 0xFA8A (0.98 block per sample) on 30 channels (measured peak) | 29 | 117 | 0.48 M |
| Measured peak (psyvaria) | 12.0 | 48 | 0.20 M |
| Measured average (raycris / psyvaria) | 1.4 / 3.7 | 6 / 15 | 0.02 M / 0.06 M |

Measured averages and peaks come from MAME 0.288 runs of 150 s with a
coin at 40 s. A Lua frame notifier read every channel's status and step
(save items). I summed step / 65,536 over active channels and sampled each
frame from 20 s on (7,778 frames).

Readback adds 4,480 single reads in 74 s (raycris), which is negligible.

Latency budget. With a per-channel 2-line buffer (current and next 64-bit
line), the engine requests line n + 1 when a channel enters line n. At the
maximum pitch a line lasts 2 samples (61 us), so the request has at least
one full sample period (30.7 us) to complete. That is far above a DDR3
round trip on MiSTer: a few hundred ns, needs-review against the arbiter
the glue uses. Worst case 24 requests per sample serialised at 300 ns
take 7.2 us of every 30.7 us.

Loops and key-on break the sequential pattern:

- On key-on, the start line is fetched at the channel's next slot. MAME
  plays the first block in the first sample, so the request must complete
  within one sample period: the same budget.
- On a loop, the next line is the loop line. The prefetcher computes it
  from end/loop when the channel enters the last line before end.

If a fetch is late, the engine holds the channel's previous sample and
sets a sticky debug flag, like XelaNotPu's overrun flag (zsg2.sv:31-33).
It never stalls the pass.

TMS57002: 27 word accesses per sample to M10K, no external bandwidth.

## 6. Microarchitecture proposal

### 6.1 Time base

- One virtual clock for the whole Zoom board: the MN10200's machine-cycle
  counter, paced to real time (mn10200_design.md 5.2). It keeps counting
  while the MN10200 is held in reset.
- Sample boundary B_k every 192 machine cycles. TMS57002 instruction slot
  j of a sample at B_k + j/2 cycles.
- The ZSG-2 pass for sample k starts when virtual time reaches B_k.
  - CPU writes with an earlier virtual time are applied before the pass.
    They sit in a 16-entry write FIFO (MLAB) and drain at the boundary.
  - A CPU access to the ZSG-2 with virtual time >= B_k waits until pass k
    has finished, so a register 0xB read sees the post-sample state, as MAME
    does after its m_stream->update().
  - The firmware reads the ZSG-2 about 1,800 times a second, so stalls are
    rare and the pacer credit absorbs them.
- The TMS57002 executes slot j of sample k only when virtual time has
  reached it. A host byte from the MN10200 therefore lands at the same
  instruction position it would on the PCB.
- The TMS57002 runs the program for sample k on the ZSG-2 output of sample
  k - 1. The hardware's serial link needs at least that much: the ZSG-2
  shifts sample k out during period k + 1. MAME uses the same sample
  (2.1). The result is a constant one-sample offset against MAME, which
  the verification removes (7.4).
- The TMS57002's SO1 pair is latched at each sync into a 4-entry FIFO. The
  mixer reads the FIFO at a real-time 32,552.083 Hz tick: a fractional
  accumulator on clk_1x, 1,040.45 clocks per sample. The FIFO absorbs the
  pacer's lead or lag of up to 64 machine cycles (10 us).
- Why: in MAME, a ZSG-2 write lands at the MN10200's local time
  (m_stream->update() at the access, zsg2.cpp:620), which is exact in CPU
  cycles. Tying the boundaries to the CPU's virtual cycles reproduces the
  sample index of every write, given MAME-equal cycle counts (the
  MN10200's baseline). Only the phase at reset release remains. It depends
  on main-CPU timing and is forced from the log in replay.

### 6.2 ZSG-2 engine

Time-multiplexed: one channel at a time, 48 slots per pass, clk_1x.

| Step (clocks) | Work |
|---|---|
| 0-1 | Read the channel state words (2 M10K, 40 bits per clock) and the registers it needs: step, end, loop, start, page, gains, ramp bytes |
| 2 | Step add (17-bit); compare with end; loop or stop; decide on a block load |
| 3-6 | On a block load: take the block from the line buffer, decode one sample per clock (16-bit barrel shift by s), emphasis update (24-bit add; the state stays inside +/-2^21), clamp |
| 7-14 | One shared 18 x 18 multiplier (1 DSP), one product per clock: interpolation, output filter (17 x 16; 32-bit wrap accumulate, a 2-cycle partial product if the operands exceed 18 bits), volume, 4 sends with the gain ROM (32 x 16 MLAB). Four send accumulators of 22 bits |
| 15-16 | Ramp (vol, cutoff) on odd samples; write the state back; issue a prefetch request if needed |

- About 17 clocks per channel, so a pass takes 48 x 17 = 816 clocks
  (24 us) of the 1,040 per sample. The multiplier is busy 8 of 17 clocks.
  If timing is tight, the pass can run on clk_2x.
- Key-on and key-off: two 48-bit pending masks, set by control writes in
  the write FIFO and applied in the channel's slot. Key-on initialises the
  state as in 3.5.
- get_ramp is evaluated when register D or F is written. The result is
  stored in the state RAM, so the pass needs no shifter for it.
- Readback port: the 0x638/0x63A address and a busy flag shown at 0x628.
  The flag is set by the access that triggers the fetch and cleared when
  DDR3 returns. MAME returns 0 at once. The firmware polls until the low
  8 bits are 0, so a short busy is invisible to it apart from timing.
  Which access starts the fetch (the high-address write, by MAME's order)
  is Z6.
- Outputs: four 16-bit words per pass to the TMS57002 input registers.

### 6.3 TMS57002 core

A single-issue core at clk_1x with an enable from the time base. It
executes one instruction per enabled clock and repeats MAME's two-stage
MACC visibility exactly.

| Unit | Content |
|---|---|
| Host interface | Byte assembler (24/32-bit), mode decode from PLOAD/CLOAD, PC/CA load counters, SA, 16 x 32 UPDATE FIFO (MLAB) with EMPTY; update held until CLOAD rises (4.2) |
| Sequencer | PC (8-bit), RPTC, conditional branches, IDLE, sync actions (4.1), PC0 |
| Decode | Combinational decode of cat 1, 2 and 3 fields. The full instruction set is implemented (130 entries in tmsinstr.lst), so other firmware revisions and the ZFX-2 question (R9) do not need a rebuild. Unused instructions are counted on a debug flag |
| Address unit | DMEM0 (param + BA0) & 0xFF or (ID + BA0); DMEM1 & 0x1F; CMEM by param or CA; increments of CA and ID |
| ALU | 32-bit AACC; SFAI (<< 8 extension) and SFAO (<< 7) shifts; AOV and saturation |
| MAC | 25 x 32 product in 2 DSP blocks (27 x 27 plus an 18 x 18 for the high bits), MACC 52-bit with SFMA shifts (0, +2, +4, -16), output conversion: SFMO shift, RND rounding mask, MOVM saturation, MOV detection (tms57002.cpp:353-681) |
| Serial | si[4], so[4] as 24-bit registers; dis reads the input words; domh writes so |
| External RAM | XBA (19-bit, decremented at sync), XOA from CMEM, address mask per M, one 16-bit M10K access per word, XRD/XWR; byte sequencing collapsed but completion timed as MAME's (one byte per instruction) |

A primary and a secondary instruction in one word may read and write data
memory in the same instruction (to confirm against tmsinstr.lst per pair
the programs use). DMEM0 is therefore one M10K in simple dual port mode and
DMEM1 an MLAB.

### 6.4 Output and mix

- Zoom L/R from the FIFO times the MB87078 gain (64-entry table; MAME's
  linear law as an option), then summed with the PSX SPU output at the
  MAME balance (SPU 0.3, Zoom 1.0) as a parameter (R13).
- The SPU runs at 44.1 kHz in PSX_MiSTer. Both values are held between
  their own ticks and summed in clk_1x. The MiSTer audio_out resamples the
  sum, a zero-order hold for both sources. The quality of the hold is a
  later listening check, not an accuracy question.
- One DSP block, or a shift-add, for the two gains, time-shared.

### 6.5 Estimates

Method as mn10200_design.md 5.9: I counted ALUTs per bit from operand
width and mux depth, adders at 2 bits per ALM, about 1.6 ALUTs per ALM,
and 1 ALM per 3 flip-flops that cannot pack with logic. These are paper
figures.

ZSG-2:

| Unit | ALMs low | ALMs high | M10K | DSP |
|---|---|---|---|---|
| CPU interface, register file control, read mux, control registers, write FIFO | 90 | 160 | 2 | |
| Key-on/off masks and apply | 40 | 70 | | |
| Sequencer and slot timing | 40 | 80 | | |
| State RAM interface and about 290 working flops | 100 | 170 | 2 | |
| Step, end, loop unit | 50 | 90 | | |
| Prefetch buffers, request queue, DDR3 port, readback | 120 | 200 | 1 to 3 | |
| Decode shifter, emphasis filter, clamp | 70 | 120 | | |
| Shared multiplier datapath, output filter, sends, accumulators, gain ROM | 160 | 270 | | 1 |
| Ramp units (get_ramp at write, clamp step) | 40 | 90 | | |
| **ZSG-2 total** | **710** | **1,250** | **5 to 7** | **1** |

TMS57002:

| Unit | ALMs low | ALMs high | M10K | DSP |
|---|---|---|---|---|
| Host interface and UPDATE FIFO | 70 | 120 | | |
| Sequencer, sync, repeat | 40 | 70 | | |
| Decode (full set; the used subset alone saves about 80 to 120) | 120 | 250 | | |
| Address unit and memory muxes | 100 | 170 | 3 | |
| ALU | 90 | 150 | | |
| MAC, MACC, output conversion | 200 | 330 | | 2 |
| Serial registers | 40 | 70 | | |
| External RAM unit | 50 | 80 | 64 | |
| **TMS57002 total** | **710** | **1,240** | **67** | **2** |

Output path, time base and mixer: 60 to 140 ALMs, 0 to 1 DSP.

Against the F0 budget (docs/f0_budget.md 5.1, line "Zoom without
MN10200", 3,202 measured):

| | Low | High |
|---|---|---|
| ZSG-2 + TMS57002 + output path (this study) | 1,480 | 2,630 |
| Plus FX-1B glue line as measured (work RAM, cache, mailbox) | 494.6 | 494.6 |
| Zoom without MN10200 | 1,975 | 3,125 |
| Change against 3,202 | -1,227 | -77 |
| F0 total (with the own MN10200) | 33,307 | 36,607 |
| % of 41,910 | 79.5 | 87.3 |

M10K: 72 to 74 against FX-1B's 81 for the two chips. DSP: 3 to 4 against 3.
Neither is a constraint (f0_budget.md 5.1: 407 M10K and 93 DSP projected).

Checkpoint: as for the MN10200 (mn10200_design.md 5.10), each chip is
synthesised alone after its first RTL milestone. If either exceeds
1,500 ALMs, I stop and review before integration.

## 7. Verification plan

### 7.1 What to capture from MAME

The main-CPU side is in the existing oracle: zoom.log in
tools/mame/oracle.lua (register port, IRQ, mailbox, lines 246-250) and
ctrl.log for the Zoom reset bit. That is the stimulus. The chips' own
traffic is on the MN10200 side, so I would extend tools/mn102/mn102_trace.lua
(or add a Zoom section to oracle.lua that taps `:taito_zoom:mn10200`):

1. `zsg2.log`: t (9 decimals), R/W, register, data, MN10200 PC, for every
   ZSG-2 access. The derived sample index is
   ceil(t x 25e6 / 768) relative to power-on. Check that rule first on a
   canary of 10 accesses against m_sample_count read at the next access,
   and the reset offset, because MAME's stream boundary rounding is not
   documented in the files I have.
2. `tms.log`: t, port 1 value, data byte, plus `:taito_zoom:tms57002`
   state PC and the ZSG-2 m_sample_count at each byte. This gives the
   (sample, PC) position where each host byte lands in MAME.
3. State snapshots every frame, through device save items (the probe in
   3.4 shows they are readable):
   - ZSG-2: m_sample_count and per channel status, cur_pos, step_ptr,
     vol, vol_delta, output_cutoff, emphasis and output filter states,
     samples[5];
   - TMS57002: macc, aacc, st0, st1, xba, si, so, dmem0, dmem1, cmem;
   - the 64 KB delay RAM once a second, through its data space.
4. Audio: MAME's wavwrite records the final mix (SPU included). For a
   Zoom-only WAV, either mute the SPU in MAME's per-device mixer settings
   (needs-review for 0.288's new sound system) or use the snapshots alone.

Oracle versions:

- MAME 0.288 for everything except register 0xB reads.
- A MAME with 61c7940 (a release that contains it, or 0.288 with that
  one-line change built locally) for board-level runs (3.7). That is a
  decision for Lee, since it means building MAME.

All logs are game-derived data and go under gitignored sim/.

### 7.2 ZSG-2 unit replay (Verilator)

Drive the RTL with zsg2.log at its derived sample indices, with the
readback data from the wave images. Compare the full channel state at every
snapshot sample index, and the four send words when a per-sample capture
exists. Expected: bit-exact except register 0xB reads (>> 3, 3.7).

Sets: all six games, attract plus a credit, 300 s each. Shikigami's sound
test 05 intro (the voice stealing case) runs against the 61c7940 oracle.

### 7.3 TMS57002 unit replay

Download the logged programs and coefficients. Feed the ZSG-2 send words
(from 7.2) with the one-sample offset of 6.1. Insert host update bytes at
the logged (sample, PC). Compare TMS state at snapshots and the SO1 words.
Expected: bit-exact except the 16-bit output truncation (4.5).

Directed tests from the manual: each instruction in tmsinstr.lst, with the
ST1 modes the programs use (MOVM, RND 0 and 1) and the remaining modes,
against MAME through a small host build of MAME's tms57002 files. MAME is
BSD-3; nothing from it goes into the RTL.

### 7.4 Board level (M3 gate, PLAN.md 4)

The MN10200, ZSG-2 and TMS57002 together in Verilator from a Zoom reset:

- the ZSG-2 write stream (register, data, sample index) and the TMS57002
  byte stream equal the 61c7940 oracle's;
- SO1 equals it with the constant one-sample offset;
- coefficient update landings within one sample of MAME's (MAME's 60 kHz
  quantum, taito_zm.cpp:194, makes its own landing point coarse); each
  difference is listed with the sample it moved.

Then levels with the MB87078 law against MAME's linear law, and PCB audio
when available (R10, R12, R13, R26).

### 7.5 Classified divergences (planned)

| Divergence | Cause | Evidence |
|---|---|---|
| Register 0xB reads >> 3 | Firmware needs 13 bits | 3.7, MAME 61c7940 |
| MB87078 gain law instead of linear | Data sheet; port protocol match | 2.4 (needs-review wiring) |
| 16-bit DSP output | SOM = 2 and a 16-bit DAC | 4.5 |
| One-sample DSP input latency | Serial link on the PCB | 6.1 |
| CMEM update after CLOAD rises | Manual p.3-43 | 4.2 |

## 8. Open questions

| # | Question | Evidence that would settle it |
|---|---|---|
| Z1 | ZSG-2 register 0xB: the exact 13-bit mapping (vol >> 3 or other) and whether the internal volume is 16 bits | PCB audio of the Shikigami intro (R26); a logic analyser on the MN10200 bus reading register 0xB during a known ramp |
| Z2 | Key-on: initial volume (register A) and attack ramp; MAME ignores A and forces delta 0x400 | PCB audio of isolated note starts (sound test) |
| Z3 | Gain law of the 5-bit sends (MAME -1 dB per step) and the meaning of bits 7:5 (never set by these games) | PCB audio at known gain values; a gain sweep in the sound test |
| Z4 | Ramp rate law: the firmware's ramp table (MAME cites a table in the gdarius sound ROM at 0x6332) could be inverted exactly | Find the same table in the G-NET zoomprog and derive the register-to-rate law from how the driver uses it (firmware analysis, no hardware needed) |
| Z5 | Emphasis and output filter constants, interpolation method | PCB audio; a decap |
| Z6 | Control registers 0x618/0x61A/0x620/0x628 (init values 0x5CBC, 0x5CBC, 0x0128, 0x0066), 0x630 (written with 1 about every 16 ms), 0x628 busy semantics and which access starts a readback | Firmware analysis of the writers; bus logic analyser |
| Z7 | Scaling of the reverb and chorus sends into the DSP (MAME 0.5) | PCB audio of reverb level; the serial word on a scope |
| Z8 | TMS57002 CLKSEL strap (inferred 1 from the program length) and the SYNC source (LRCK edge or ZSG-2 signal), so the ZSG-2 to DSP latency | FC PCB trace of pins 10 and 80 |
| Z9 | CMEM update landing point: manual (after CLOAD high) against MAME (at the 4th byte) | Manual p.3-43 is rank 3; accept it unless a PCB measurement contradicts it |
| Z10 | MB87078: what DSEL is wired to, which signals channels 0 and 1 attenuate (Zoom only or the final mix, and in which order with the SPU), and whether channels 2 and 3 are used | FC PCB trace; PCB audio comparing nightrai (0x30) against raycris (0x3F) |
| Z11 | SPU against Zoom balance (R13) | PCB line-out recordings |
| Z12 | ZFX-2 on later boards (R9): if a target game shipped with it, does it run the same microcode | Board photos per game |
| Z13 | Delay RAM initial contents in MAME 0.288 (zero or not) and on the PCB (DRAM noise, inaudible after 1 s) | MAME source of the data space default; PCB audio of the first second after reset |
| Z14 | ZSG-2 reads while a wave flash is not in read-array mode (none seen after reset release) | Oracle flash.log over longer runs |
| Z15 | DSP output: truncation or rounding to 16 bits at the serial port | Manual SOM section (not stated); PCB capture of the DAC input |
| Z16 | Port 1 bits 2, 4 and 5 (TMS57002 MUTE, RS or something else) | FC PCB trace |

## 9. Files

- [MAME 0.288 zsg2.cpp](https://github.com/mamedev/mame/blob/mame0288/src/devices/sound/zsg2.cpp), `zsg2.h`; [MAME 0.288 tms57002](https://github.com/mamedev/mame/tree/mame0288/src/devices/cpu/tms57002)
  (`tms57002.cpp`, `.h`, `tms57kdec.cpp`, `tmsinstr.lst`, `tmsmake.py`);
  [MAME 61c7940 zsg2.cpp](https://github.com/mamedev/mame/blob/61c794064422682db7a1f8b3d58c21563333a9c8/src/devices/sound/zsg2.cpp), `zsg2.h` (md5s in
  `docs/mame_sources.md`).
- The trace scripts used here were scratch tools: Lua taps on port 1 and
  0xC00000, a Lua sampler of ZSG-2 save items, and Python statistics over
  the logs. They are not committed. 7.1 specifies the permanent versions
  for the oracle.

## Patched MAME with the 61c7940 fix (2026-10-05)

I rebuilt the patched MAME 0.288 tree (a local
source tree outside this repository; recipe in
docs/r1_speed_study.md 6.1) with `src/devices/sound/zsg2.cpp` replaced by
the 61c7940 version ([MAME 61c7940 zsg2.cpp](https://github.com/mamedev/mame/blob/61c794064422682db7a1f8b3d58c21563333a9c8/src/devices/sound/zsg2.cpp); the only difference
from 0.288 is register 0xB returning `vol >> 3`). Incremental build, rc 0.
Binaries: `gnet_61c7940` (ZN2_CPU_HZ patch plus the ZSG-2 fix; with
ZN2_CPU_HZ unset the CPU runs at MAME's default) and `gnet_0288_cpuhz`
(previous build, ZN2_CPU_HZ only). Smoke test: raycris 15 s, no errors.
Board-level sound comparisons use `gnet_61c7940`.
