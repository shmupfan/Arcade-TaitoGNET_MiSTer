# G-NET BIOS security check: MAME oracle for the 50 MHz halt

Status: 2026-10-05. Question from the hardware tests: the 50 MHz build
(gnet_z1c50) halts after the last TT16 (select 0x84) CAT702 sessions. Its
last RAM code PC is 3170, then it calls A(40h) at BFC0B530. The 33.87 MHz
build continues to 31D4 and reads the U30 header at 1F000120. This note is
what MAME 0.288 does over the same window, from the last 0x84 session to
the first 1F000120 read: the PCs, the branches, the RAM involved and its
expected values.

## 1. Answer

- **No compare between 3170 and 31D4.** 3170 is the chunk-length guard of
  a block descramble routine at 312C. The branches in the window test only
  the length and its alignment: a0 = 0x100, so 3170 is not taken, and
  a0 & 3 = 0, so 317C goes to 31B8. The first U30 read is the `lbu` at 31C4.
- **The real pass/fail is later and does not call A(40h).** The BIOS calls
  the loader through kernel B(63h) (BFC0B750), then tests the result at
  BFC056F8 (`bnez v0`). On 0 it prints "Program not found." (string at
  BFC0BE30) and reports error 0x44 through BFC05AE4 (the same path as
  "Program ROM not found.", error 0x42, the B930 case).
- **A(40h) means an unhandled CPU exception.** The kernel exception
  handler (vector 0x80 jumps to RAM 0C80) handles only ExcCode 0
  (interrupt) and 8 (syscall). Every other code goes to DeliverEvent
  (F0000010, 1000), then A(40h) from RAM 3F4C (ra = 3F54). The A0 table
  entry at RAM 0300 is BFC0B530, a stub that jumps to A0 with t1 = 0x40
  again, so the CPU loops there for good. That is the halt.
- **Interrupts are ruled out.** SR is 0 for the whole window in MAME
  (IEc = 0), and I_STAT = I_MASK = 0. Even an interrupt would take the
  handled ExcCode 0 path.
- **So the 50 MHz core takes a synchronous exception at or just after
  3170.** It is one of: address error (4 or 5), bus error (6 or 7), break
  (9), reserved instruction (10), coprocessor unusable (11) or overflow
  (12). The kernel saves the evidence in RAM (section 6). Reading three
  words from the core after the halt says which exception it is and where.

## 2. Method

`tools/mame/seccheck_trace.lua` runs shikigam warm. The NVRAM is from
`sim/r18/nv_shikigam` (the same source as `sim/oracle/shikigam_warm20`),
with no inputs before 0.1 s, under `-debug -debugger none -debuglog`. It
records:

- taps on the CAT702 select register (0x1FA10300) and on U30 reads at
  1F000100 to 1F0003FF, with emulated time and PC;
- a debugger instruction trace from the first frame (16.7 ms) to 100 ms;
- breakpoints at 312C, 3170, 1F1C, 80000080, 80 and BFC0B530 that print
  registers, COP0 SR, Cause and EPC, I_STAT and I_MASK, and save RAM.

Two runs gave byte-identical RAM dumps and traces. Outputs are in
`sim/oracle/seccheck/t3/` (gitignored; game-derived). I used one MAME at
a time under nice -n 15.

```
SEC_OUT=$PWD/sim/oracle/seccheck/t3 SEC_STOP=0.1 nice -n 15 mame shikigam -rompath roms \
  -video none -sound none -nothrottle -debug -debugger none -debuglog \
  -nvram_directory <warm nvram dir> -autoboot_script tools/mame/seccheck_trace.lua
```

(run from inside SEC_OUT so debug.log lands there; nvram, cfg and diff
directories as in tools/mame/oracle_run.sh.)

## 3. Timeline in MAME (emulated time)

| Time | PC | Event |
|---|---|---|
| 54.540 ms | BFC0552C | first U30 header read, 1F000004 ("Licensed by Sony...") |
| 54.5 to 66.0 ms | 274C / 2758 / 2798 | CAT702 sessions: select 0x88 (TT10) at 274C, 0x84 (TT16) at 2758, deselect 0x0C at 2798 |
| 60.76 ms | 2028 to 204C | reads of 1F0000A0 to 1F00011F (header block before the descrambled area) |
| 66.003920 ms | 2758 | last select 0x84 |
| 66.421560 ms | 2798 | deselect 0x0C (end of the last 0x84 session) |
| (trace) | 1F14 | `jal 312C` with a0 = A000CF78 (descriptor), a1 = 16388 (key) |
| (trace) | 3170 | chunk guard, first pass (registers in section 5) |
| 66.423920 ms | 31C4 | first read of 1F000120 (byte FCh), 2.4 us after the deselect |
| (trace) | 1F1C | return; the caller then zeroes the key buffer (0x300 bytes) |
| (trace) | BFC056F8 | `bnez v0` on the B(63h) result: taken (pass) |
| (trace) | 80010008 | the descrambled program at 80010000 runs |

## 4. Code

Call structure, all RAM code copied from the BIOS: BFC056F0 `jal
BFC0B750` (B(63h)) leads to the security loader. The loader's key builder
(1DA0 to 1F10) fills the key buffer at 16388 from five CAT702 segments
through 294C. 1E48 and 1E68 retry a segment for as long as 294C returns
nonzero (a retry loop, not an error exit). 1F14 calls the descrambler 312C;
1F1C onwards clears the key; 2700 to 2710 returns v0 = a3 to the BIOS.

The descrambler at 312C reads a descriptor at a0 (+08 chunk length,
+10 source, +14 total length, +18 destination), then loops over the source
in chunks. Each chunk is copied from U30 four bytes at a time (a byte loop
handles a length that is not a multiple of 4; the first U30 read is the
`lbu` at 31C4), then transformed in place by the three passes described
below, and the loop advances by the chunk length until the total is done.
The two swap passes divide by n - 1 and carry the compiler's
divide-by-zero guard (`break 7`). I read the routine with
`tools/mame/mips_dis.py` on a MAME RAM dump taken at the first entry of 312C;
the listing is not reproduced here because it is Taito's BIOS code.

What 312C computes, per 256-byte chunk: copy from U30; subtract key[i]
byte by byte; for idx in (0x1E, 3), for n/2 key halfwords h read
downwards from key + n - 2, swap dst[idx] with dst[h mod (n - 1)]. I
checked this with a Python model of the routine: MAME's source and key give
exactly MAME's 0x2800-byte output at 80010000.

## 5. Values in MAME

Registers at the first pass of 3170 (debugger, `debug.log`):

| Register | Value | Meaning |
|---|---|---|
| a0 | 00000100 | chunk length n (branch at 3170 not taken) |
| a1 | 00016388 | key buffer |
| a2 | 1F000120 | source, U30 |
| a3 | 00000100 | chunk length from the descriptor |
| t0, t1 | 00002800 | remaining, total |
| v0 | 00000000 | offset |
| v1 | 80010000 | destination |
| sp | A000CDE0 | |
| ra | 00001F1C | |
| SR | 00000000 | interrupts disabled (IEc = 0), BEV = 0 |
| Cause | 00000020 | left from the last syscall (BFC0B5D4, EnterCriticalSection) |
| I_STAT, I_MASK | 0, 0 | |

Branches from 312C to the first U30 read, first chunk: 3144 not taken
(t1 = 2800); 315C taken to 316C (2800 < 100 is false); 3170 not taken
(a0 = 100); 317C taken to 31B8 (a0 & 3 = 0); then 31C4 reads 1F000120.
Instruction sequence: 312C 3130 3134 3138 313C 3140 3144 3148 314C 3150
3154 3158 315C 3160 316C 3170 3174 3178 317C 3180 31B8 31BC 31C0 31C4
31C8 31CC 31D0 31D4.

Buffers (RAM addresses are physical; the code uses KSEG0/KSEG1 aliases):

| What | Where | Expected |
|---|---|---|
| Descriptor (a0 at 312C) | A000CF78: +08 chunk, +10 source, +14 total, +18 destination | 00000100, 1F000120, 00002800, 80010000 |
| Key, read by 312C | 16388 to 16487 (256 bytes) | CRC32 67CBD3FC, listed below |
| Source, U30 from 1F000120 | 0x2800 bytes, CPU view | CRC32 F76F0D6E |
| Result | 80010000 to 800127FF | CRC32 43BC734C; first words 03E00008 00000000 3C028001 24422628 (jr ra; nop; lui v0,0x8001; addiu v0,v0,0x2628) |
| A0 table entry A(40h) | 00000300 | BFC0B530 |
| Kernel TCB pointer | [00000108] = A000E1EC, [[0108]] = A000E1F4 | save area base A000E1FC |

Key bytes 16388 to 16487: not published here (they are derived from the
CAT702 key data in the BIOS set). The CRC32 above identifies them; the
MAME run in this section reproduces them from your own `coh3002t.zip`.

A wrong key does not stop 312C. It gives a wrong program at 80010000,
which fails only when it runs (likely a reserved instruction or address
error, then A(40h), but from 80010000 onwards, not near 3170).

## 6. A(40h) route, proven in MAME, and what to read in the core

Experiment (`sim/oracle/seccheck/x1`): I forced the chunk length to 1 at
3138 (a3 = 1), so the `lhu` at 32B8 reads key + 1, an odd address. MAME
then took an exception with Cause = 10000010 (ExcCode 4, address error on
load), EPC = 32B8 and SR = 0. The kernel handler ran (80000080 to 0C80),
and the CPU reached BFC0B530 with ra = 3F54, then stayed in the A0 and
B530 loop. The saved words were EPC = 000032B8 at E27C and Cause =
10000010 at E28C. The normal run never reaches BFC0B530; its only
exception is the syscall at BFC0B5D4.

The kernel's exception dispatcher (3F2C to 3F4C) tests v1 = Cause & 0x3C:
ExcCode 0 (interrupt) and ExcCode 8 (syscall) are handled; anything else
calls DeliverEvent(F0000010, 1000) and then A(40h) with ra = 3F54.

What the 50 MHz core should report after the halt (RAM, physical
addresses; the kernel stores them at exception entry, 0C80 onwards):

| Address | Word | Use |
|---|---|---|
| 0000E27C | EPC as saved | the faulting instruction (or the branch, when BD is set) |
| 0000E288 | SR | expected 0 here |
| 0000E28C | Cause | bit 31 BD; ExcCode = bits 6:2 |

How to read them:

- EPC = 3170 with BD set means the fault was in the delay slot at 3174.
  That is a `nop`, which cannot fault, so a reserved instruction or
  instruction bus error there points at a bad instruction fetch.
- EPC = 3170 with BD clear means a fault fetching the branch itself.
- EPC = 31C4 with ExcCode 7 (DBE) or 4 (AdEL) means the first U30 read.
- EPC in 32B8 to 334C points at the descramble; ExcCode 9 (break) there
  means a chunk length of 1, so a bad descriptor or a misread a3.

BadVaddr is not saved by this kernel, so it has to come from COP0 directly
if the core exposes it.

The A0/B530 loop also matches "halts after the BIOS POST bars": the
kernel prints nothing for an unresolved exception at this stage. That is
my reading of the code, not something I observed on the 50 MHz core.
