# MN10200 (Panasonic MN1020012A) design study

Status: DESIGN STUDY (2026-10-04). No RTL yet. Target: the Taito Zoom sound
CPU for the G-NET core (PLAN.md 3.1, own implementation), at 2,800 ALMs or
less on the 5CSEBA6 (f0_budget.md 5.1 counts 1,800 to 2,800; XelaNotPu's
literal MAME port measures 3,944.5 ALMs, 6,034 ALUTs, 1,628 registers and
1 DSP in the FX-1B reference fit, f0_budget.md 2.1).

## Summary

- My estimate for the proposed design is 930 to 1,670 ALMs, 0 DSP and 4 to
  6 M10K. That leaves at least 1,130 ALMs under the 2,800 cap. These are
  paper figures (method in 5.9); the first RTL milestone measures them.
- The Zoom firmware (six G-NET images, two code variants) uses
  129 of the 159 MN10200 instruction forms, and two 90 s MAME traces
  executed 116 of them. No MN102H-only instruction appears. The instruction
  length is a pure function of the first byte, which keeps fetch and
  decode simple.
- The firmware uses the older MN10200 peripheral map that MAME implements,
  not the MN102H map in the manual I have. The MN102H manual is therefore
  evidence for the CPU core, bus cycle and instruction timing only. For the
  peripherals, the evidence is the firmware's own register use plus MAME.
- The firmware needs very little of the chip: the CPU, the interrupt
  controller (timer 3 at 1 kHz and the IRQ0 doorbell from the main CPU), the
  8-bit timers and one prescaler, IRQ pin readback (it polls the TMS57002
  FIFO line through it), port 1 (TMS57002 load strobes) and a read of
  port 3. Serial, A/D, DMA and the 16-bit timers are only initialised.
- In MAME the CPU never idles: 222 M instructions in 73.9 s of Ray Crisis
  (3.01 M instructions/s, 2.08 cycles per instruction at 6.25 M cycles/s).
  At 33.8688 MHz that leaves 11.2 FPGA clocks per instruction on average, so
  a small multi-cycle design is fast enough.
- Timing approach: the design counts the manual's cycle counts in a
  virtual cycle domain (the same counts MAME charges, at the same
  clock/2 = 6.25 MHz machine cycle), with timers stepped in that domain and
  the whole domain paced to real time. Wait states and pipeline penalties
  stay parameters, off by default, until there is evidence for them
  (section 6).

## 1. Sources and evidence

| Rank (evidence_sources.md) | Source | Settles |
|---|---|---|
| 3 | MN102L Series Instruction Manual 12250-030E, appendix "Instruction set" pp.145-151 | Encodings, sizes, minimum cycle counts, flags |
| 3 | MN102H60G LSI User's Manual 22360-014E (MN102H, linear-addressing high-speed member) | Machine cycle = 2 OSCI periods (Table 1-2-1 p.9, p.53); external bus cycle 1 machine cycle at 0 waits, +0.5 per wait step (pp.67-70); 3-stage pipeline with a 4-byte queue (p.12); interrupt acceptance up to 6 cycles to finish or abort the current instruction (MUL and DIVU aborted and re-executed) then 7 cycles of hardware processing, 6-byte stack frame (pp.84, 87, 281); CPUM layout (p.323). Its appendix instruction table matches the MN102L table for all 161 L entries in size, cycles and encoding (script comparison of the two extracted tables), plus MN102H-only instructions |
| n/a (firmware) | The six Zoom program images (U27, `zoomprog`), statically scanned and traced in MAME 0.288 (section 3) | Which instructions, modes and peripherals the target games use; the peripheral register layout (section 4.1); the MOVB erratum (1.1); the 16-bit timer cascade (4.3) |
| 5 | MAME 0.288 `src/devices/cpu/mn10200/mn10200.cpp`, `.h`, `mn102dis.cpp` ([MAME 0.288 mn10200](https://github.com/mamedev/mame/tree/mame0288/src/devices/cpu/mn10200)) and `src/mame/sony/taito_zm.cpp` | Peripheral behaviour where the manual is silent or describes a different chip; the oracle for verification |
| 6 | XelaNotPu `rtl/mn10200.sv` (FX-1B core, literal MAME port) | Read for what the firmware needs and what costs area; no code taken |

What the manuals do not cover: the MN1020012A itself. The MN102H60G has a
different interrupt controller (one vector per group, 56 groups, Table 3-1-1
p.84 contrasts it with the older "4 vectors per group" parts), a different
memory control block (EXWMD/MEMMD at 0xFF80), different timer clock sources
and no prescaler registers. The Zoom firmware programs MAME's layout in all
of these places (section 4.1), so the MN1020012A belongs to the older
MN10200 peripheral generation. The manual for that generation (Japanese
22399-031, English MN102H 22360-011E/-013E per SOURCES.md) is not in the
library.

### 1.1 MOVB Dm,(An) erratum

Both manuals give MOVB Dm,(An) as 10 + Dm<<2 + An. MAME decodes it as
10 + An<<2 + Dm, like every other (An) form, with the comment "error in
manual" (also Pokechu22/ghidra-mn102-lang). The firmware settles it: at
0x08216a in the psyvaria image the code is `movbu (a0),d1 ; and
0xff7f,d1 ; 0x11`. MAME's order reads 0x11 as `movb d1,(a0)`, a
read-modify-write of the same byte. The manual's order reads it as
`movb d0,(a1)`, which makes no sense there. A copy loop at 0x080735 (`movbu
(a0),d0 ; 0x14`) agrees: MAME's order gives a0 to a1. I follow MAME.

### 1.2 Two forms missing from both manual tables

F1:00 `MOV (Di,An),Am` and F1:80 `MOV Am,(Di,An)` are absent from the
MN102L table, and the MN102H errata (unnumbered errata page, PDF p.558)
deleted them from an earlier H edition. The firmware's interrupt dispatcher
at 0x08001e executes F1:00 on every interrupt, so the MN1020012A has it.
Cycle count: MAME charges 3; no manual figure (open question O9).

## 2. Instruction set summary

### 2.1 Programming model

- D0 to D3 (24-bit data), A0 to A3 (24-bit address; A3 is the stack
  pointer), PC (24-bit), MDR (16-bit multiply/divide high word), PSW
  (16-bit).
- PSW: bit 0 ZF, 1 NF, 2 CF, 3 VF (flags on the low 16 bits), 4 ZX, 5 NX,
  6 CX, 7 VX (flags on the full 24 bits), 10:8 IM (interrupt mask level),
  11 IE, 13:12 S1:S0 (software bits).
- Little-endian, 24-bit address space. 16 and 24-bit accesses must be at
  even addresses (manual note); MAME forces them even.
- Reset: PC = 0x080000. Interrupts (all maskable groups and NMI) enter at
  0x080008; software reads IAGR and dispatches.

### 2.2 Formats and lengths

The length is a function of the first byte only (checked over all 65,536
two-byte combinations with my decoder):

| First byte | Length | Contents |
|---|---|---|
| 00-3F | 1 | MOV/MOVB/MOVBU between Dm and (An) |
| 40-7F | 2 | MOV Dm/Am to and from (d8,An) |
| 80-8F | 1 or 2 by opcode | MOV Dn,Dm (1 byte); when Dn = Dm (80, 85, 8A, 8F) MOV imm8,Dn (2 bytes) |
| 90-BF | 1 | ADD/SUB Dn,Dm; EXTX, EXTXU, EXTXB, EXTXBU |
| C0-CF | 3 | MOV/MOVB/MOVBU with (abs16) |
| D0-DB | 2 | ADD imm8,An; ADD imm8,Dn; CMP imm8,Dn |
| DC-DF | 3 | MOV imm16,An |
| E0-EA | 2 | Bcc label8 (10 conditions), BRA |
| EB | 1 | RTI |
| EC-EF | 3 | CMP imm16,An |
| F0-F3 | 2 | Prefix pages: F0 JMP/JSR (An), BSET/BCLR, MOVB/MOVBU (Di,An); F1 MOV (Di,An) 16 and 24-bit; F2 register-register ADD/SUB/CMP/MOV across D and A, ADDC/SUBC; F3 AND/OR/XOR/CMP Dn,Dm, ROL/ROR/ASR/LSR, MUL/MULU/DIVU, MDR and PSW moves, EXT, NOT |
| F4 | 5 | 24-bit page: (d24,An), (abs24), imm24, JMP/JSR label24 |
| F5 | 3 | imm8 logic, ADDNF, MOVB/MOVBU/MOVX (d8,An), Bccx (24-bit flag) and BVC/BVS/BNC/BNS |
| F6 | 1 | NOP |
| F7 | 4 | 16-bit page: imm16 logic and arithmetic, AND/OR imm16,PSW, (d16,An), (abs16) for An |
| F8-FB | 3 | MOV imm16,Dn |
| FC, FD | 3 | JMP label16, JSR label16 |
| FE | 1 | RTS |
| FF | n/a | Undefined (MAME raises NMI) |

Register fields sit in the low bits of the opcode byte (or the byte after a
prefix): bits 1:0 Dm/Am/Dn, bits 3:2 An (or the source register), bits 5:4
Di in the (Di,An) forms.

### 2.3 Addressing modes

Register direct; immediate 8 (sign or zero extended per instruction), 16,
24; (An); (d8,An), (d16,An), (d24,An) with sign-extended 8 and 16-bit
displacements; (Di,An); (abs16) (zero-extended, so 0x0000 to 0xFFFF,
including the internal I/O at 0xFC00); (abs24). Data widths: byte (MOVB
sign-extends, MOVBU zero-extends), word (16-bit, sign-extended into Dn),
24-bit (MOVX for Dn, MOV for An).

### 2.4 Cycle counts

Minimum counts in machine cycles, from the MN102L table, identical in the
MN102H table. One machine cycle is 2 OSCI periods, so 6.25 MHz on the Zoom
board (OSCI 12.5 MHz, taito_zm.cpp header). The manual states these are
minimums with the instruction already in the queue; register dependence,
an empty queue, memory waits and an 8-bit bus add cycles (MN102L manual
p.22). It gives no table of those penalties.

| Group | Cycles |
|---|---|
| Register moves and 1-byte ALU, (An) loads and stores, (d8,An) word loads and stores with Dn, abs16 with Dn, MOV imm8/imm16 to Dn and imm16 to An, ADD imm8, CMP imm8,Dn and imm16,An | 1 |
| F2 register-register (incl. ADDC/SUBC), most F3 (AND/OR/XOR/CMP/shifts/MDR moves/NOT), (Di,An) with Dm, MOV An to and from (d8,An), F5 imm8 logic and byte (d8,An), F7 imm16 arithmetic and logic on Dn and An, F7 (d16,An) with Dm, JMP label16 | 2 |
| MOVX (d8,An) and (d16,An), F7 forms moving An ((d16,An) and (abs16)), AND/OR imm16,PSW, MOV Dn,PSW, EXT, F4 word and byte forms with Dn, the imm24 forms, (Di,An) with Am (MAME, 1.2), JMP (An) | 3 |
| F4 forms moving An to or from memory, F4 MOVX, JMP label24, JSR label16 | 4 |
| JSR (An), JSR label24, RTS, BSET, BCLR | 5 |
| RTI | 6 |
| MUL, MULU | 12 |
| DIVU | 13 |
| Bcc label8 / Bccx, BVC, BVS, BNC, BNS label8 | 2/1 and 3/2 (taken/not taken) |
| Interrupt acceptance (MAME, and MN102H p.87) | +7 |

Over the 159 forms (branches at their taken count): 25 take 1 cycle, 66
take 2, 51 take 3, 8 take 4, 5 take 5, 1 takes 6, 2 take 12, 1 takes 13.

MAME charges exactly these counts: one cycle for the first opcode byte, one
more per prefix or extra operand stage, and the documented extras. I
spot-checked 26 forms, including every multi-cycle class and the branch
rules, against MAME's `m_cycles` charges. The verification plan (7.1)
checks all of them mechanically.

### 2.5 Flag rules that matter for the datapath

- Arithmetic (ADD, SUB, CMP, ADDC, SUBC) sets all eight flags from one
  24-bit operation: the 16-bit set from bit 15/16 and the low 16 bits, the
  24-bit set from bit 23/24 and all 24 bits. ADDC/SUBC set ZF only if ZF
  was already 1 and the low 16 bits are 0 (MN102L manual p.71, for
  zero-checking a 32-bit sum); ZX is computed normally. MAME does the same.
- Logic and shifts operate on the low 16 bits and leave bits 23:16 of Dn
  unchanged (AND masks with 0xFF0000 | operand). They set NF and ZF, clear
  VF and CF (shifts set CF), and leave the X flags alone.
- MUL/MULU: 16 x 16 to 32; low 16 bits to Dm (24-bit, MAME keeps result
  bits 23:16 too), high 16 bits to MDR. DIVU: (MDR:Dm) / Dn, quotient to Dm,
  remainder to MDR; VF on divide by zero or quotient overflow.

## 3. What the Zoom program uses

### 3.1 Method

- Images: `zoomprog` (flash U27, 512 KB, mapped at 0x080000) from the MAME
  NVRAM of raycris, psyvaria, psyvarrv, shikigam, nightrai and xiistag. The
  NVRAM stores each 16-bit flash word byte-swapped; the tools swap it back.
  The images are game data and are never committed. The tools print
  statistics only and write any listing outside the repository.
- Static: `tools/mn102/mn102_scan.py` disassembles by recursive descent
  from 0x080000 and 0x080008. It resolves jump tables behind the three
  indirect jumps (the interrupt dispatch table, a 10-entry switch table
  and a 16-entry 6-byte key and handler table). Decoder:
  `tools/mn102/mn102_isa.py`, built from the manual table with the
  corrections in 1.1 and 1.2.
- Dynamic: `tools/mn102/mn102_trace.sh` runs MAME 0.288 with the debugger
  trace of `:taito_zoom:mn10200` (noloop) streamed through a FIFO into a PC
  histogram (`mn102_cover.py`), plus `mn102_trace.lua`, which logs every
  access to the internal registers, ZSG-2, TMS57002 and mailbox with the PC,
  and drives coin, start, fire and left/right from 20 s. Runs: raycris and
  psyvaria, 90 s each, warm NVRAM from `sim/r18/nv_<set>`. The main CPU
  releases the Zoom reset at 16.15 s (raycris) and 5.52 s (psyvaria), after
  a 48 ms run at power-on, so the CPU ran 73.9 s and 84.5 s.

### 3.2 Code

| Image | Used bytes | Instructions reached | Code bytes | Code variant |
|---|---|---|---|---|
| raycris | 505,862 | 11,819 | 28,456 | A |
| psyvaria, psyvarrv, shikigam, nightrai, xiistag | 396,720 / 391,795 / 339,688 / 163,518 / 128,151 | 11,738 | 28,271 | B |

Variant B is byte-identical in all reached code across its five images;
only the data differs. The code is about 28 KB; the rest of each image is
sound data that the CPU reads. No undecodable path, and no MN102H-only
opcode (MULQ, bit-number BSET/BCLR, TBZ/TBNZ, PXST), in any image.

### 3.3 Instruction forms

- Static: 129 of the 159 forms in every image.
- Executed in the traces: 116 (raycris 116, psyvaria 114). The 10 most
  frequent forms cover 47.8% of executed instructions, 20 cover 70.3%, 40
  cover 87.9% and 80 cover 99.2%.
- Present in the code but not executed in the traces (13): BCSX, BNS,
  CMP An,Dm, MOV (d16,An),Am, MOV Am,(d16,An), MOVX (d16,An),Dm, MOVX
  Dm,(d16,An), NOP, ROL, ROR, SUB Dm,An, SUB imm16,Dn, XOR Dn,Dm. Psyvaria
  also did not execute MOV (d16,An),Dm and MOV Dm,(d16,An); raycris did.
- Never present (30): BSET, all Bccx except BLTX and BCSX (BCCX, BEQX,
  BGEX, BGTX, BHIX, BLEX, BLSX, BNCX, BNEX, BNSX, BVCX, BVSX), BVC, BVS,
  BTST imm16, CMP An,Am, MOV (abs16),An, MOV An,(abs16), MOV PSW,Dn, MOV
  Am,(Di,An), MOV Am,(d24,An), MOVB and MOVBU (d16,An), MOVB Dm,(d16,An),
  MOVX (d24,An) both directions, SUB imm16,An, SUB imm24,An, SUB imm24,Dn.

Dynamic mix (raycris, 222,427,777 instructions):

| Form | Share |
|---|---|
| CMP imm8,Dn | 7.98% |
| MOVX Dm,(d8,An) | 6.67% |
| MOVX (d8,An),Dm | 6.24% |
| ADD imm8,An | 5.20% |
| ADD imm8,Dn | 4.72% |
| BEQ | 3.87% |
| MOV (d8,An),Dm | 3.86% |
| ADD Dn,Dm | 3.47% |
| MOV (abs24),Dn | 3.17% |
| RTS, JSR label16 | 2.92%, 2.89% |

By class: ALU 40.1%, loads 24.8%, stores 15.0%, branches 10.7%, calls and
returns 5.8%, jumps 1.9%, PSW writes 0.6%, MUL/MULU/DIVU 1.04% (about 31,000
per second), BCLR 55 times in total. Average fetch 2.40 bytes per
instruction.

Rates (raycris): 3.01 M instructions/s, 7.24 MB/s of instruction fetch,
0.75 M loads/s and 0.45 M stores/s. psyvaria: 2.96 M instructions/s, 2.11
cycles per instruction.

Because the CPU never halts in MAME (3.4), these rates are the full machine
rate, not the firmware's useful work. Most of the time goes into a main
loop that polls the TMS57002 FIFO line (fc56 is read 305,325 times in
raycris) and the ZSG-2.

### 3.4 Program structure (firmware facts the design depends on)

- Boot (0x080090): the first instructions program the memory control
  registers (0xFC30 to 0xFC36, 0xFC02), CPUM = 0x8000, PSW = 0, clear the
  interrupt controller, set up the timers, serial, A/D, DMA and ports, set
  A3 = 0x406CC6, then call the main routine at 0x08060F.
- The main routine does not return in either trace. After it the code
  writes 0x0B to CPUM (on the MN102H that pattern is STOP with the low-speed
  oscillator bits set; MAME only logs a "stop request"), then NOP, NOP, NOP
  and a branch back. None of these instructions executed, so the
  STOP/HALT behaviour does not affect the traced games (open question O4).
- Interrupt entry 0x080008: allocate 14 bytes, save A0, D0, D1 (MOVX) and
  MDR, read IAGR (0xFC0E), double it, index a table of 4-byte pointers at
  0x08712C with `mov (d0,a0),a0` (F1:00), JSR (A0), restore, RTI. With 4-byte
  entries, IAGR must read group x 2 (MAME: group << 1). The MN102H returns
  group x 4 (p.89), which would break this dispatcher: more evidence that
  the MN1020012A is the older generation.
- Handlers in the table: group 1 at 0x0804B6 (timers 0 to 3), group 8 at
  0x0804E7 (external pins), group 9 at 0x080517 (serial 0 receive and
  transmit), group 10 at 0x080401 (A/D: reads eight result bytes at 0xFDA8 to
  0xFDAF), all others to an RTS.
- Interrupt levels: every enabled group has level 0 in ICRH, so the mask
  after acceptance (IM = 0) blocks all others. The handlers never nest.
  Acceptance clears IE in MAME too (`mn10200.cpp:300` masks PSW with
  0xF0FF), as in the MN102H manual; corrected 2026-10-05, see
  docs/mn10200_rtl.md 4.4.
- Work RAM: static accesses span 0x400046 to 0x4064C4, the stack starts at
  0x406CC6 and the boot code uses 0x408000 as a bound. That fits the 32 KB
  LH52B256 on the FC PCB (PLAN.md R7; mirroring still unknown).

## 4. Internal peripherals the firmware touches

### 4.1 Register use (raycris trace; psyvaria identical in kind)

| Address | MAME name | Firmware use | RTL |
|---|---|---|---|
| FC00 | CPUM | W 0x8000 at boot (watchdog off per MN102H p.323); 0x0B in the unreached idle tail | Store; STOP/HALT decode per O4 |
| FC02, FC30-FC37 | memory control, memory mode 0 to 3 | W once: FC02 = 0x0430, FC30 = 0x0000, FC32 = 0x0100, FC34 = 0x0000, FC36 = 0x0101 | Store; drive the optional wait-state model (6.3) |
| FC0E | IAGR | R on every interrupt: 0x0002 (group 1) 73,879 times, 0x0010 (group 8) 10 times | Full |
| FC40 | NMICR | W 0 | Full (illegal opcode sets it in MAME) |
| FC42 | group 1 (timers 0 to 3) | RMW; enables timer 3 only (ICRH = 0x08); handler acks by writing 0x0828; reads 0x08A8 (IR for timers 3 and 1 set) | Full |
| FC44-FC4E | groups 2 to 6 | W 0 | Full (cheap; IR bits of timer 7 latch here) |
| FC50 | group 8 (IRQ0 to IRQ3 pins) | enables IRQ0 (ICRH = 0x01), the main CPU doorbell; reads 0x0131 (IRQ0 and IRQ1 requested) | Full |
| FC52 | group 9 (serial 0) | enables bit 1 (ICRH = 0x02); never requested in the traces | Full |
| FC54 | group 10 (A/D) | W 0; not enabled | Full |
| FC56/FC57 | EXTMD low/high, P4 pin levels | W 0x0002 (IRQ0 falling edge); R about 4,000 times a second: the high byte returns the pin levels, so the firmware polls IRQ1 (TMS57002 FIFO empty, inverted) here, 0xF002 or 0xD002 | Full, including pin readback |
| FD00, FD02 | DRAM control, refresh | W 0 | Ignore writes |
| FD80-FD83 | serial 0 | ctrl 0x81 (8 data bits, no parity, 1 stop, clock from timer 8), then RMW to 0xC081 (transmit and receive on); TX buffer 0xFF; RX/status read only in the group 9 handler | Control register readback; RX never ready, TX accepted (O6) |
| FD90 | serial 1 ctrl | W 0x0081 | Ignore |
| FDA0 | A/D control | W 0x704D (converter off, bit 7 = 0) | Ignore; result reads (group 10 handler only) return 0 |
| FE10-FE1B | timer 0 to 9 base, prescaler 0/1 base | bases t0 0x57, t1 0x02, t2 0x69, t3 0x18, t4 0x0F, t5 0x0F, t6 0x0F, t7 0x7A, t8 0x18, t9 0x0F; prescaler 0 base 0x0F then 0x00, prescaler 1 base 0x07 | Full |
| FE20-FE2B | timer and prescaler mode | enabled: t0 0x83 (prescaler 1) with t1 0x81 (cascade), t2 0x82 (prescaler 0) with t3 0x81, t6 0x83 with t7 0x81, t8 0x82; prescalers 0 and 1 0x80; t4, t5, t9 off | Full |
| FE30-FE5B | 16-bit timers 10 to 12 | W 0 | Ignore |
| FE60-FE62 | sync output | W 0 | Ignore |
| FE64 | port 1 output (taito_zm.cpp TMS57002 PLOAD/CLOAD) | RMW about 12,000 times a second | Full; input reads return the output latch (as MAME's taito_zm wiring) |
| FE80-FEFF | DMA 0 to 7 | W 0 | Ignore |
| FFB0, FFB2 | pull-ups | W 0 | Ignore |
| FFC0, FFC2/3 | port 0, 2, 3 outputs | W 0 | Store (nothing connected in MAME) |
| FFD3 | port 3 input | R once at start of the main routine: bit 0 = 1 selects the path at 0x08075C | Input pins (O5) |
| FFE0-FFE3 | port directions | P0 0x3F, P1 0x7F, others 0 | Store; port reads OR in the direction bits as MAME does |
| FFF2/FFF3 | port mode | W 0 | Ignore |

Accesses from the CPU to the other devices (raycris, 73.9 s): ZSG-2 489,155
writes and 133,038 reads, TMS57002 data port 1,491,056 writes, mailbox 230
reads and 79 writes.

### 4.2 Interrupt controller

MAME's model, which the firmware's register values match: groups 1 to 10,
one 16-bit register each at 0xFC42 + 2(g-1). Low byte: IR (request) bits
7:4, read-only ID = IR & IE in bits 3:0; writing the low byte ANDs the IR
bits (acknowledge). High byte: level bits 6:4, IE bits 3:0. Group 8 also
re-samples the pins on acknowledge (level-triggered pins stay requested).
Priority: the lowest level number that is below PSW.IM wins, ties to the
lowest group. Acceptance pushes the 24-bit PC at A3-4 and PSW at A3-6,
A3 -= 6, PC = 0x080008, PSW.IM = level, IAGR = group, 7 cycles. RTI pops
both, 6 cycles.

Sources wired on G-NET (taito_zm.cpp, taitogn.cpp): IRQ0 = main CPU write
to 0x1FBA0000 (MAME pulses the line), IRQ1 = TMS57002 FIFO empty (inverted),
IRQ2 and IRQ3 unused. Timer IRQs: timer n sets IR bit (n & 3) of group
1 + (n >> 2).

### 4.3 Timers

The firmware runs three cascaded 16-bit pairs and one single timer:

| Pair | Base (high:low) | Clock | Period | Rate | IRQ enabled |
|---|---|---|---|---|---|
| t3:t2 | 0x1869 | prescaler 0, divide 1 | 6,250 cycles | 1.000 kHz | yes (the sound driver tick) |
| t1:t0 | 0x0257 | prescaler 1, divide 8 | 4,800 cycles | 1,302 Hz | no (IR latches only) |
| t7:t6 | 0x7A0F | prescaler 1, divide 8 | 249,984 cycles | 25.0 Hz | no |
| t8 | 0x18 | prescaler 0 | 25 cycles | 250 kHz | serial 0 clock (31,250 baud if the UART divides by 8: MIDI rate) |

The tick is exactly 1.000 ms in the trace (19 consecutive intervals
measured) and 1,000.2 interrupts per second over the whole run. A 16-bit
base of 0x1869 = 6,249 giving exactly 1 kHz at 6.25 MHz is, in my reading, the designer's intent, which supports
two things: the timer clock is the 6.25 MHz machine cycle (OSCI/2), and a
cascaded pair counts as one 16-bit counter. MAME implements the cascade
that way: the low timer reloads to 0xFF, not to its base, while the high
timer has not underflowed. A naive model with each timer reloading from its
own base would give (0x69+1) x (0x18+1) = 2,650 cycles (2.36 kHz) and the
music would play 2.36 times too fast.

The firmware never reads a timer counter (0xFE00 to 0xFE0B), so only the
underflow timing matters.

## 5. Microarchitecture proposal

### 5.1 Principles

1. Count the manual's cycles, do not reproduce the pipeline. Every
   instruction retires a fixed number of virtual machine cycles (2.4), and
   everything time-dependent inside the chip (timers, interrupt sampling)
   runs on those virtual cycles. How many FPGA clocks an instruction takes
   is free, because a pacer (5.2) keeps the virtual time locked to real
   time. This is the property that makes a small design possible.
2. One of everything: one 24-bit adder for the ALU, address and PC
   arithmetic, one shifter stage, one memory port, used in sequence. The
   budget allows it: 11.2 FPGA clocks per instruction on average against
   about 4 to 7 needed.
3. 24-bit registers, not MAME's 32-bit storage. Verification masks MAME's
   register values to 24 bits (7.2).
4. Implement the whole MN102L instruction set plus F1:00/F1:80 (159 forms),
   even though the games use 129. The unused 30 share the datapath with the
   used ones and cost mostly decode-table entries. Other firmware revisions
   (the MN1020819DA boards, R9) are then covered.
5. Peripherals at the level the firmware uses them (4.1): full interrupt
   controller and 8-bit timers, everything else as cheap stored or ignored
   registers.

### 5.2 Clocking and pacing

- Clock: the PSX core's clk_1x (33.8688 MHz) with a clock enable, no new
  clock domain. Any clock above about 25 MHz works, since the design
  depends only on the pacer.
- Pacer: a fractional accumulator adds 15,625 per clock; each virtual
  cycle the CPU retires subtracts 84,672, and the CPU may start an
  instruction while the credit is positive (6,250,000 / 33,868,800
  reduced exactly, so there is no long-term drift).
  Credit is capped (for example at 64 cycles) so the CPU never runs more
  than about 10 us ahead of real time. Cache misses and slow instructions
  simply use up slack.
- All interaction with the rest of the board (mailbox, IRQ0 from the main
  CPU, ZSG-2 and TMS57002 accesses) happens in real time, within that window
  of the virtual time. MAME couples the CPUs with a 1/60,000 s quantum
  (taito_zm.cpp), which is a coarser window, so this is no less exact than
  the oracle.

### 5.3 Control: sequencer and decode

- A micro-sequenced FSM, with these steps:
  - FETCH: opcode byte and any prefix byte.
  - OPERANDS: 0 to 3 immediate, displacement or address bytes.
  - EA: one adder pass for An + d, An + Di or the PC-relative target.
  - MEM: 1 or 2 bus cycles (16-bit word, then a byte for 24-bit data).
  - EXEC: one ALU pass, or 16 iterations for MUL and MULU, or 16 for DIVU.
  - WB: write back.
- Decode by table, not by a large casez:
  - A decode ROM indexed by {page, byte} gives each form a micro-routine
    entry, the register-field mapping, the immediate type, the data width,
    the flag class and the cycle count. The page is one of 8: the first
    byte, or the second byte after F0, F1, F2, F3, F4, F5 or F7. That is
    2,048 entries of about 20 bits, 4 M10K.
  - A microcode ROM holds the steps, in 1 or 2 M10K.
  - A Python generator produces both ROMs from the same form table as
    `tools/mn102/mn102_isa.py`. The manual-derived table is then the single
    source of truth, and it is the table the static scanner already
    validates against the six firmware images.
- Length from the first byte only (2.2), so the fetch unit knows how many
  operand bytes to collect before decode finishes.

### 5.4 Register file

D0 to D3 and A0 to A3 as one 8 x 24-bit file in MLAB (32 x 20 simple dual
port, so 2 MLABs for 24 bits). Two read ports come from two copies written
together, 4 MLABs in all. Dm and An are read in the same clock, so (d8,An)
stores and ADD Dn,Dm need no extra read step. PC, PSW, MDR, the immediate
and EA registers and the memory data register are flip-flops.

### 5.5 Datapath

- One 25-bit adder and subtractor with carry-in (ADDC/SUBC). The 16-bit
  carry and overflow come from the internal carry at bit 16 (split the adder
  at bit 15/16 and chain, or compute C16 as a16 ^ b16 ^ s16). The same adder
  serves the ALU, EA computation (An + d8/d16/d24/Di), PC-relative branch
  targets and stack pointer adjustment (A3 -/+ 4/6) in separate micro-steps.
- PC increment: a dedicated 24-bit incrementer (cheap, and it keeps fetch
  off the adder).
- Logic unit (AND, OR, XOR, NOT on 16 bits with bits 23:16 passed or
  masked), one-bit shifter (ROL, ROR, ASR, LSR), and sign or zero extension
  (EXTX, EXTXU, EXTXB, EXTXBU, MOVB, immediates).
- MUL/MULU: radix-2 shift-add over 16 steps on the shared adder, with MDR
  and a temp register as the 32-bit shift pair. At 12 machine cycles, about
  65 FPGA clocks are available, so no DSP is needed. Option: one 18 x 18
  DSP if the iterative unit's muxes cost more than about 40 ALMs at fit.
  The DSP budget has room (93 of 112, f0_budget.md 5.1).
- DIVU: restoring, 16 steps of 1 bit on the same adder (13 machine cycles,
  about 70 FPGA clocks available).
- Flags: one flag unit fed by the adder result and carries, the logic
  result, or the shifter output. The decode table selects which flags
  update (2.5).

### 5.6 Fetch and bus interface

- One bus master port of 16 bits with byte enables, address, read/write and
  ready (the Zoom glue decodes ROM/flash, RAM, ZSG-2, TMS57002, mailbox).
  8-bit accesses use one lane; 16-bit accesses are one word at an even
  address (MAME clears bit 0); 24-bit accesses are a word plus a byte at
  +2. Interrupt entry and RTI use the same sequencing.
- Instruction fetch: a 2-word (4-byte) prefetch buffer, the same depth as
  the real queue, refilled by word reads while the execute steps do not use
  the bus. The first byte decides the length, and operands are taken from
  the buffer. A taken branch flushes it.
- Internal I/O (0xFC00 to 0xFFFF) is decoded inside the core and answers
  in one clock.
- The program flash lives in SDRAM or DDR3 with the 8.5 MB of G-NET flash
  (PLAN.md 3.3). The Zoom glue needs a small read cache, as in FX-1B (an
  8 KB direct-mapped cache there), counted in the Zoom glue budget, not
  here. The cache is invalidated when the main CPU releases the Zoom reset,
  because the main CPU programs U27 only while the Zoom is held.

### 5.7 Interrupt controller and timers

- Interrupt controller (4.2): 10 groups of 8 request and enable bits plus 3
  level bits, NMICR, EXTMD with the P4 pin readback, edge detection on the
  four pins, and a priority scan over 10 groups. The scan is registered
  and sampled at instruction boundaries only.
- Timers: ten 8-bit down counters with base and mode registers and two
  8-bit prescalers, each stepped by the virtual-cycle enable. A cascaded
  timer steps on the underflow of the one below, and the lower timer
  reloads to 0xFF until the upper underflows (MAME's 16-bit cascade, 4.3).
  Counting cycle by cycle replaces XelaNotPu's event scheduler: 24-bit
  expiry times and a 10-way earliest-due tournament. Their comments
  measure that logic at 1,339 ALMs before a rework; I estimate 400 to 700
  ALMs for it now (no per-unit fit figure exists).
- Virtual-cycle stepping: an instruction retires N cycles at once (up to
  20 with interrupt entry). The timer unit keeps a small count of pending
  cycles and steps one per FPGA clock, in parallel with the next
  instruction. The interrupt sample at the next instruction boundary waits
  until the pending count is zero. Instructions take at least about N FPGA
  clocks anyway, so this almost never stalls.

### 5.8 Debug and verification port

A retire port carries PC, the cycle count and register writeback,
compiled into simulation builds and optional in hardware builds (a
SignalTap-sized trace for board bring-up). It does not count in the
release budget.

### 5.9 ALM estimate per unit

Method: I counted ALUTs per bit from operand width and mux depth (a 4:1
mux is one 6-input LUT, an 8:1 mux is about 2.5), counted adders at 2 bits
per ALM in arithmetic mode, and converted with about 1.6 ALUTs per ALM. I
added about 1 ALM per 3 flip-flops that cannot pack with logic. These are
estimates, not measurements.

| Unit | ALMs low | ALMs high | M10K | Notes |
|---|---|---|---|---|
| Sequencer, decode ROM interface, field extraction | 120 | 220 | 4 to 6 | ROMs generated from the form table |
| Register file D0-D3/A0-A3 | 40 | 70 | 0 | 4 MLABs (counted as 10 ALMs each) plus write-data mux |
| PC, PSW, MDR, EA, immediate, memory data, temp | 60 | 110 | 0 | About 150 flip-flops |
| ALU: 25-bit add/sub, flags, logic, shift, extend | 120 | 200 | 0 | One adder |
| Operand and address muxes, PC incrementer | 120 | 220 | 0 | 24-bit, 6 to 8 sources per side |
| MUL/MULU/DIVU sequencing | 60 | 120 | 0 | Iterative on the shared adder; 0 DSP |
| Fetch buffer and operand assembly | 50 | 90 | 0 | 4 bytes, byte select |
| Bus interface (8/16/24-bit sequencing, lanes) | 60 | 110 | 0 | |
| Interrupt controller and pins | 90 | 150 | 0 | |
| Timers 0-9, prescalers 0-1 | 120 | 200 | 0 | Cycle-stepped down counters |
| I/O register file and read mux (CPUM, memory mode, serial 0 stub, ports 1/3/4, ignored ranges) | 60 | 120 | 0 | |
| Pacer and pending-cycle counter | 30 | 60 | 0 | |
| **Total** | **930** | **1,670** | **4 to 6** | **0 DSP** |

Against the cap of 2,800 that leaves 1,130 ALMs at the high estimate. Against
the own-MN10200 line of f0_budget.md 5.1 (1,800 to 2,800) it lowers the
projection by 870 ALMs (low) to 1,130 ALMs (high).

Where XelaNotPu's 3,944.5 goes, and which choice above avoids it:

| Cost in their design | This design |
|---|---|
| 32-bit registers in flops, each with 15 to 25 write sources | 24-bit MLAB register file |
| About 11 dedicated PC and A3 adders plus a 4-term address adder | One shared adder, sequenced |
| Timer event scheduler with ten 24-bit expiry registers | Ten 8-bit counters |
| 44-bit cycle counter | Pacer accumulator and a small pending count |
| Large two-level casez decode | Decode and microcode ROMs in M10K |

### 5.10 Area checkpoint

The first RTL milestone is the CPU without peripherals (5.3 to 5.6),
synthesised alone in Quartus 17 with `tools/fit_entities.py` per unit.
Gate: 1,400 ALMs for that subset. Above 2,000 ALMs, stop and redesign
before adding the peripherals.

## 6. Timing accuracy

### 6.1 What MAME does

MAME runs the MN10200 at clock/2 (`execute_clocks_to_cycles`), which is
the manual's machine cycle (2 OSCI periods, 6.25 MHz on the Zoom board).
Per instruction it charges the manual's minimum counts (2.4). It does not
model:

- memory wait states;
- the instruction queue (refill after a branch, or an empty queue after
  long sequences of short instructions);
- register-dependence stalls;
- interrupt acceptance latency: MAME takes an interrupt at the next
  instruction boundary, where the MN102H manual allows up to 6 cycles and
  aborts and re-executes MUL and DIVU.

Timers run as scheduled events with the cascade semantics in 4.3.

### 6.2 Baseline: MAME-equivalent counting

I make the baseline equal to MAME: the same cycle counts, the same
machine-cycle rate, interrupts sampled at instruction boundaries, timers
stepped per virtual cycle. With the same inputs, the RTL then takes every
timer interrupt at the same instruction as MAME, which makes the CPU
verifiable instruction by instruction against MAME traces (section 7). For
the target games this baseline is also close to the hardware where it
matters most:

- The music tempo comes from the 1 kHz timer, so it depends on the
  machine-cycle rate only, not on instruction timing.
- The CPU polls in a loop, so extra cycles per instruction on the real
  chip lower the spare capacity, but do not change what the firmware
  outputs as long as each 1 ms tick's work finishes inside the tick.

### 6.3 Divergence hooks (off by default)

- Wait states: per-region extra cycles for external accesses (program
  flash, RAM, ZSG-2, TMS57002, mailbox), applied in virtual cycles per bus
  access. The firmware programs FC02 = 0x0430 and memory mode registers
  0x0000 / 0x0100 / 0x0000 / 0x0101. Their bit meaning on the MN1020012A is
  unknown (O2). On the MN102H, the reset default is 7 waits (8 cycles per
  access) until software lowers it, so the boot instructions before
  0x080092 may run slower than MAME.
- Queue penalty: extra cycles after taken branches and when the queue
  empties, if the older-generation manual gives numbers.
- Interrupt acceptance latency: complete-or-abort within 6 cycles, with
  MUL/DIVU restart.

Each hook, when enabled, is a classified divergence from MAME with its
evidence recorded, as PLAN.md requires.

### 6.4 What could make the difference audible

The only firmware-visible effect of CPU speed I have found is the ratio of
work to spare time per 1 ms tick. MAME's trace shows the CPU always busy,
but that is polling. To measure the real headroom, the next trace step is to
count the instructions spent outside the polling loop per tick, in the
heaviest scenes. If the useful work is a small fraction of 6,250 cycles,
wait states cannot change the sound and the hooks can stay off. If it is
close to the tick, they matter and O2 becomes a priority.

## 7. Verification plan

### 7.1 Instruction level (before any peripheral)

- Decoder check: the ROM generator's table against the manual table and
  MAME. For all 65,536 first two bytes and the F4 page, compare the form,
  length and cycle count with MAME's `m_cycles` charges. To do that, build
  MAME's MN10200 core into a small host program for the testbench only (MAME
  is BSD-3; nothing goes into the RTL), or derive the charges from a MAME
  trace of a test program.
- Directed test programs, generated by my own tools (no game code), that
  execute every one of the 159 forms with corner operands:
  - flags at 16/24-bit boundaries, ADDC/SUBC Z stickiness;
  - MUL/MULU signs, DIVU by zero and overflow;
  - odd displacements, A3 wrap, (abs16) into I/O.
  
  They run in MAME by replacing the `zoomprog` NVRAM file of a copy of a
  game's NVRAM set, so MAME's Zoom CPU boots the test, and in Verilator
  against the RTL. This also covers the 30 forms no game uses and the 13 the
  traces did not reach.
- Comparison format: per retired instruction, PC, the D0-D3/A0-A3 values
  masked to 24 bits, PSW, MDR and the cumulative cycle count. MAME side:
  debugger `trace` with a `tracelog` action that prints the registers.

### 7.2 Firmware replay (CPU and peripherals, without ZSG-2/TMS models)

- Record a MAME run with `tools/mn102/mn102_trace.sh` extended to log:
  - every external read value (ZSG-2, TMS57002, mailbox, port 3);
  - the IRQ0 assertion point as an instruction index;
  - the IRQ1 pin level at each FC56 read.
- Replay those inputs into the RTL by instruction index, not by time.
- Expect identical PC, register and cycle streams, identical I/O write
  streams (address, data, cycle), and the 1 kHz timer interrupt entered at
  the same instruction index as MAME, which checks the cycle counts and the
  timer cascade together.
- Sets: all six games, cold boot to attract and a credit of play, 300 s
  each (the oracle runs in sim/oracle provide the start states).
- Known, expected differences, each to be classified as it appears:
  - timer phase after a prescaler mode write (MAME restarts all timers;
    counters do not), constant after boot;
  - the serial 0 receive register, which MAME post-increments on every read
    of 0x182; it is only read in the handler, which never runs.

### 7.3 Board level (M3 gate, PLAN.md 4)

The CPU in the Zoom block with the ZSG-2, TMS57002 and mailbox. The
ZSG-2 register stream and the TMS57002 write stream must equal MAME's.
After that, audio comparison per PLAN.md R13.

### 7.4 Area and timing

Per-unit fit after each milestone (5.10). Timing closure is not a concern at
33.8688 MHz for a design of this size, but every build is checked for setup
and hold on clk_1x, because the FX-1B reference fails hold at 99% device
fill.

## 8. Open questions

| # | Question | Evidence that would settle it |
|---|---|---|
| O1 | The MN1020012A peripheral generation: register layout and semantics for interrupts (4 vectors per group), timers (prescalers, cascade), memory control, CPUM, serial | The older MN10200 series manual (Japanese 22399-031, or English MN102H 22360-011E/-013E, SOURCES.md says datasheetarchive gates the download); any MN1020012A or MN10200-generation datasheet |
| O2 | Bus wait states as programmed by the firmware (FC02 = 0x0430, FC30-FC36 = 0, 0x100, 0, 0x101) and the reset default before that | O1's manual; a logic analyser on the FC PCB's /RD and /CS during the boot code; or a timing loop: run a known instruction loop on the PCB and measure a port toggle |
| O3 | Instruction queue and interrupt latency penalties on this chip | O1's manual; PCB measurement as O2 |
| O4 | CPUM write 0x0B in the idle tail: STOP or HALT, wake-up source and delay. Unreached in the traces; relevant only if another game or firmware path returns from the main routine | O1's manual; traces of all six games and later boards |
| O5 | Port 3 bit 0 on the FC PCB (MAME reads 1, the firmware branches to 0x08075C). What is on the pin, and does any board read 0 | FC PCB photos or continuity trace; the code at both branch targets (compare what each path initialises) |
| O6 | Serial 0 runs at what looks like MIDI rate with the receive interrupt enabled. Is anything wired to its RX pin on the FC PCB (development MIDI port, or nothing) | FC PCB inspection; MAME has no serial input |
| O7 | Timer phase: free-running prescalers on the chip against MAME's restart on mode writes; first-period length after the prescaler 0 base change from 0x0F to 0x00 while running | O1's manual; acceptable as a classified constant offset otherwise |
| O8 | Work RAM mirroring: is the 32 KB SRAM mirrored across 0x400000 to 0x41FFFF (MAME maps 128 KB of RAM). The firmware stays below 0x408000 statically (3.4) | FC PCB address decode (XC95108 CPLD E65-01, R15) |
| O9 | Cycle count of F1:00 and F1:80, which are missing from both manual tables (MAME: 3) | O1's manual |
| O10 | Behaviour of 16 and 24-bit accesses at odd addresses (MAME forces even). The RTL replay flags any occurrence in the firmware | O1's manual; none expected |
| O11 | MN1020819DA (later boards, R9): same core and peripheral map | Datasheet or a firmware image from a later board through the same scan |
| O12 | Acceptance clears PSW.IE: settled for MAME parity (MAME and the MN102H manual both clear it, docs/mn10200_rtl.md 4.4); the MN1020012A itself still per O1 | O1's manual |

## 9. Files

- `tools/mn102/mn102_isa.py`: decoder (form, length, minimum cycles, kind,
  memory width and mode). It is the planned source for the RTL decode ROMs.
- `tools/mn102/mn102_scan.py`: static scan of a `zoomprog` image
  (statistics only; `--listing DIR` writes a private listing, keep DIR
  outside the repository).
- `tools/mn102/mn102_trace.sh`, `mn102_trace.lua`, `mn102_cover.py`: MAME
  0.288 trace runner (nice -n 15, refuses to start with 3 MAME processes
  running), I/O log and PC histogram. Output directories hold game-derived
  data; keep them outside the repository or under gitignored `sim/`.
- [MAME 0.288 mn10200](https://github.com/mamedev/mame/tree/mame0288/src/devices/cpu/mn10200): `mn10200.cpp`, `mn10200.h`,
  `mn102dis.cpp`, `mn102dis.h` (reading only; md5s in
  `docs/mame_sources.md`).
