# G-NET glue design study (flash, RF5C296, ATA card, control)

Status: DRAFT 2026-10-04. No RTL. Register and command use taken from the
MAME oracle (tools/mame/oracle.lua): all six priority games traced cold,
Ray Crisis also warm with a credit. Area figures are the F0 estimates
(docs/f0_budget.md 4.1).

Evidence used, by rank (shmupfan ACCURACY.md):

| Rank | Source | Used for |
|---|---|---|
| 3 | Ricoh RF5C296/RF5C396L datasheet (mister-arcade-survey/datasheets/rf5c296/) | ExCA register set, defaults, window mapping |
| 3 | CF+ and CompactFlash Specification Rev 1.4 and 3.0 (datasheets/pccard_ata/) | ATA task file, attribute memory, CIS, configuration registers |
| 3 | Intel 28F400B5 datasheet 290599-004 (datasheets/intel_flash/) | E28F400B (U27) command set and timing |
| 3 | Intel 28F160S3/28F320S3 290608-005 and 28F160S5/28F320S5 290609-004 (datasheets/intel_flash/) | TE28F160 (U30, U29, U55, U56): ID B0h/D0h (Table 12 p24), status register (Table 15 p30), timing (p50 and p49) |
| 5 | MAME 0.288 taitogn.cpp, rf5c296.cpp, ataflash.cpp, atahle.cpp, atastorage.cpp, intelfsh.cpp, mb3773.cpp (links and md5s in docs/mame_sources.md) | Behaviour where no document exists (Taito lock, board decode) |

## 1. Main-CPU map (MAME 0.288 taitogn.cpp 476-500)

| Range | Block |
|---|---|
| 0x1f000000-0x1f7fffff | Flash bank window, 16-bit (section 3) |
| 0x1fa30000 | control3 (8-bit latch, read back) |
| 0x1fb00000-0x1fb0ffff | RF5C296 I/O space (section 4) |
| 0x1fb40000 | control: bit 5 watchdog kick, bit 4 Zoom reset, bit 2 flash bank select |
| 0x1fb60000 | control2 (16-bit, write only in MAME) |
| 0x1fb70000 | reads return 2 in MAME ("strange", R15) |
| 0x1fb80000-0x1fbe01ff | Zoom host port and mailbox (Zoom design, separate) |

## 2. Control registers and watchdog

control/control2/control3 are plain latches; control bit 4 holds the Zoom
in reset (MAME: set at power on, released by the BIOS), bit 5 kicks the
MB3773. MB3773 datasheet (datasheets/misc_gnet/, Fujitsu DS04-27401-7E)
gives the watchdog period from the external capacitor; the FC PCB value is
unknown (R17), so the period is a parameter, defaulting to MAME's.
Estimate 60 to 120 ALMs.

## 3. Flash bank and the five flash chips

| Chip | Part | Size | MAME ID | Holds | Storage in the core |
|---|---|---|---|---|---|
| U30 | TE28F160 | 2 MB | maker 0xB0 (Sharp), device 0xD0 | encrypted sub-BIOS | SDRAM |
| U27 | E28F400B | 512 KB | 0x89 / 0x4471 | Zoom (MN10200) program | SDRAM (also read by the MN10200) |
| U56, U55, U29 | TE28F160 x3 | 3 x 2 MB | 0xB0 / 0xD0 | ZSG-2 wave data | DDR3 (also read by the ZSG-2) |

Bank layout (taitogn.cpp flashbank_map): bank 0 = U30 at 0x000000, RF5C296
memory window at 0x200000, U27 at 0x300000; banks 1 and 3 = wave flashes;
bank 2 = bootleg EPROM, U27 mirror, U30. Bank select from control bit 2 and
JP1 (bootleg sets).

Command machine: one state machine per chip is unnecessary; the chips are
independent but only one is addressed per access, so a shared engine with a
small per-chip mode register (read array / read ID / read status, plus
pending program or erase) covers all five. Commands in MAME's model:
0xFF/0xF0 read array, 0x90 read ID, 0x70 read status, 0x50 clear status,
0x40/0x10 word program, 0x20 + 0xD0 block erase, 0x60 lock (ignored).
Status register (290608-005 Table 15, p30): SR.7 WSMS ready, SR.6 erase
suspended, SR.5 erase error, SR.4 program error, SR.3 VPP low, SR.2
program suspended, SR.1 lock detected, SR.0 reserved. The BIOS uses only
0x50 clear status, 0x70 read status, 0x40 program, 0x20/0xD0 erase, 0x90
read ID and 0xFF read array (oracle canary), and polls SR.7.

Timing: MAME programs instantly and erases in a fixed 1.0 s. The datasheet
typical values give a flash-only copy of 77.5 to 146.4 s depending on part
and VPP (docs/m0_findings.md 3). Plan: timing parameters with two presets,
MAME (for trace comparison) and datasheet typical (default for play, S3 at
the VPP that board evidence settles).

Persistence (R3): after the first boot the flashes hold 8.5 MB derived from
the card. Options: (1) redo the copy at every cold boot (133 to 155 s each
time); (2) build the flash images offline with MAME and load them from the
MRA; (3) save them to SD. Proposal: (2) for release (fast boot, no SD
writes), with (1) available as an OSD "first boot" option for accuracy.
Update 2026-10-04: option (2) no longer needs MAME. `tools/build_flash.py`
rebuilds all five flash images from the card and the BIOS zip, byte-
identical to MAME's post-copy NVRAM for all six games
(docs/m0_findings.md 3a), so the MRA/loader can derive them from the CHD.

Estimate 500 to 900 ALMs (command machine 200 to 400, decode and bridges
300 to 500).

## 4. RF5C296 PC card controller

Datasheet facts (page numbers of the Ricoh PDF):
- Indexed access through I/O 3E0h (index) and 3E1h (data); 56 registers
  per slot (p26).
- Identification and Revision (00h, p31) reads 1000 0011b (0x83); Chip
  Identification (3Ah, p47) reads 32h for the RF5C296. MAME returns 0 for
  every register read; the core follows the datasheet (rank 3 over 5) and
  records the difference.
- Interface Status (01h, p31): card detect, ready, write protect, from the
  card pins.
- Interrupt and General Control (03h, p38): bit 6 = card reset (0 holds the
  card in reset); MAME implements only this.
- Windows: 5 memory windows (10h-35h) and 2 I/O windows (08h-0Fh, 36h-39h)
  map card spaces into the host space (p22).

MAME hardcodes the G-NET mapping: the I/O window at 0x1fb00000 reaches the
ATA task file directly (offsets 0-7 command block, 8-15 control block), and
the memory window in flash bank 0 at 0x200000 reaches attribute memory.
Oracle (raycris cold, ata.log): the BIOS never reads an ExCA register.
It writes 14 registers, once per boot sequence:

| Index | Values written | Meaning (datasheet) |
|---|---|---|
| 02h | 30h, B0h | Power and RESETDRV: card power on, then outputs enabled |
| 03h | 00h, 40h, 70h, 00h, 40h | Interrupt and General Control: bit 6 = 0 holds the card in reset, 1 releases it |
| 06h | 21h, 60h, 00h | Address Window Enable |
| 07h | 09h | I/O Control: 16-bit I/O window 0 |
| 08h-0Bh | start 0000h, stop 000Fh | I/O window 0 covers the ATA task file (card I/O 0 to 15) |
| 10h-13h | start C000h, stop 001Fh (high bytes carry the data width and wait bits) | memory window 0 |
| 14h-15h | offset 4338h, bit 6 of 15h set (REG) | memory window 0 maps attribute memory |

These produce exactly the mapping MAME hardcodes. Design: a 64 x 8 register
file written as the datasheet describes (cheap, MLAB), reads returning the
datasheet values (00h = 83h, 3Ah = 32h, 01h from card detect and ready),
card reset from 03h bit 6, and the two windows decoded at the fixed
G-NET addresses. Decoding by the programmed window values is not needed
for these games; a check that the programmed values match the fixed
mapping raises a debug flag if a game ever differs.

Estimate 200 to 400 ALMs.

## 5. ATA card (Taito Type 1)

Card data per game (docs/m0_findings.md 2): 40,960,000-byte image, 512-byte
IDENTIFY block (IDNT), 5-byte key (KEY), CIS (122 or 123 bytes).

Attribute memory (CF spec and MAME ataflash.cpp):
- 0x000-0x0FF: CIS bytes.
- 0x100 configuration option, 0x101 configuration and status, 0x102 pin
  replacement (MAME reset value 0x002e).
- 0x07 write: unknown (MAME notes Type 1 writes 0x0e then 0x0a); logged,
  no effect, as MAME.
- Taito Type 1 lock (MAME only, no document): writes to 0x280-0x284 are
  compared with the five key bytes, each match clears one lock bit, a
  mismatch sets it; 0x201 reads 1 while any bit is set. While locked every
  ATA command fails with ERR set and DRDY clear. Open in MAME: whether a
  wrong key re-locks (R5).

Task file: data, error/feature, sector count, sector number, cylinder
low/high, drive/head, status/command; alternate status and device control
in the control block. Commands used (oracle, all six games cold, and
raycris warm): READ SECTORS 0x20, IDENTIFY DEVICE 0xEC, WRITE SECTORS 0x30
only (LBA mode). The engine implements these three; any other command
returns ABRT, as ATA specifies for unsupported commands.

Data path: 512-byte sector buffer in one M10K, filled from or written back
to the card image in DDR3 by a small burst engine. Writes also set a bit in
a dirty map (10,000 bits, one per 4 KB hunk, so 2 M10K at most) that the
HPS side reads to save changed sectors (R25: at most 32 hunks seen).

Timing: MAME answers commands at once. Real BSY/DRQ timing is unknown (R6);
first version matches MAME, with a latency parameter for later matching
against PCB load-time footage.

Estimate 700 to 1,300 ALMs including the sector engine, 2 to 4 M10K.

## 6. Loader (MiSTer side)

MRA loads: BIOS (512 KB), flash images (8.5 MB, option (2) above), the card
image (40,960,000 bytes) to DDR3, and a small header with IDNT, KEY and
CIS. Dirty sectors saved through the HPS (mechanism decided at M4).
Estimate 200 to 400 ALMs.

## 7. Open items for the oracle trace

1. Answered: RF5C296 is write-only from the BIOS; values in section 4.
2. Answered: the same three ATA commands in all six games (section 5).
3. Answered: the BIOS polls SR.7, so flash timing matters (section 3).
4. control/control2/control3/0x1fb70000 values over boot.
5. Attribute register writes (0x07, 0x100-0x102, 0x280-0x288).
