# ZN-2 layer design and the first silent test RBF

Status: DRAFT 2026-10-05, branch zn2-layer. The ZN-2 blocks (section 16)
and the M2 glue are integrated into psx_top behind generic ZN2_BOARD and
into PSX.sv behind macro GNET_ZN2; revision GNET_Z1 is ready to fit
(section 18). Full-system simulation of the integrated core with the real
BIOS runs in NVC (section 18.3). No Quartus run.

Goal of this document: everything that sits between the PSX_MiSTer PS1
system and a ZN-2 / Taito G-NET system, and a plan for a first silent test
RBF that boots the G-NET BIOS on a MiSTer: no Taito Zoom, CPU at the stock
PS1 rate, base revision GNET_B1 (LEAN + 2 MB VRAM + narrow GTE multipliers,
27,709 ALMs, docs/cpu_rate_probe.md "Baseline B1").

## 1. Summary

| Item | ZN-2 / G-NET | Change against PSX_MiSTer | Section |
|---|---|---|---|
| Main RAM | 4 MB, software uses all of it, nothing above 4 MB | set `ram8mb` = 1 (existing input), no RTL change | 3 |
| BIOS ROM | 512 KB at 0x1FC00000, same size as the PS1 BIOS | none: load into BIOS slot 0 | 4 |
| Board registers | expansion 3, 0x1FA00000-0x1FBFFFFF, plus expansion 1 for the flash window | memorymux generic ZN2_MAP (done, verified) and zn2_io (done, verified) | 5, 13.1 |
| Bus width per access | software switches expansion 1 and 3 between 8-bit and 16-bit per device | follows from the existing PS1 bus model once ZN2_MAP routes the steps out | 5.2 |
| CAT702 x2 | used by the BIOS at boot and by the games; keys TT10/TT16 are in the BIOS zip, the same for every G-NET game | zn_cat702 (done, verified on 141,900 bytes of MAME traffic) | 6 |
| znmcu | DIP switch S551 over SIO0; Shikigami reads the (unconnected) analog channels once | znmcu (done) | 7 |
| SIO0 | serial master for CAT702 x2 and znmcu, no pads or memory cards | zn_sio0 in place of joypad (done; SIO0 + CAT702 x2 + znmcu replayed against all MAME SIO0 traffic of the six games) | 7.2 |
| EEPROM | AT28C16 2 KB at 0x1FAF0000 | in zn2_io (done); NVRAM save path in the shell | 8 |
| IRQs | VBLANK, DMA, timers 1 and 2, bit 10 enabled with no source; the glue raises none | none | 9 |
| CD, pads, memory cards, MDEC, SIO1, expansion 2 | never accessed | already trimmed (LEAN) or idle | 10 |
| SPU | used by all six games; every SPU register read first polls 0x1FA60000 bit 3 (upstream would return 0 and time out) | zn2_io answers as MAME, or bit 3 constant 1 | 11 |
| Taito Zoom | absent in the silent build; both test games run with the Zoom CPU held in reset | stub in zn2_io (mailbox, status 0) | 12 |

First test expectations (section 13.8): no card, G-NET logo then "SYSTEM
ERROR"; card plus blank flashes, the flash copy screen for 2 to 3 minutes
then the attract; pre-built flashes, attract after about 15 s.

New logic for the silent RBF: about 2,100 to 3,500 ALMs, giving 29,800 to
31,200 ALMs (71 to 75% of the 5CSEBA6) on top of B1 (section 14).

## 2. Evidence

Ranks as in docs/evidence_sources.md (shmupfan ACCURACY.md).

| Rank | Source | Used for |
|---|---|---|
| 3 | Ricoh RF5C296/RF5C396L datasheet (mister-arcade-survey/datasheets/rf5c296/), Interrupt and General Control register 03h, printed p. 34 (PDF p. 38) | card IRQ steering (section 9) |
| 3 | Atmel AT28C16 datasheet doc0540 (datasheets/misc_gnet/), p. 1 to 2 and ordering table | EEPROM write time, DATA polling (section 8) |
| 3 | Fujitsu MB3773 DS04-27401-7E (datasheets/misc_gnet/) | watchdog (section 13.6) |
| 5 | MAME 0.288 [zn.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/zn.cpp), zn.h, taitogn.cpp, psx.cpp (docs/mame_sources.md); a local MAME 0.288 source tree for cat702.cpp, znmcu.cpp, sio.cpp, irq.cpp, at28c16.cpp | behaviour where no document exists |
| 5 | New MAME 0.288 traces (this branch, `tools/mame/zn2_map_trace.lua`): raycris and psyvarrv warm boots, 120 s each, from post-copy NVRAM; exp1/exp3 access widths per bus configuration, raycris warm 60 s; earliest expansion 1 accesses, raycris warm 2 s; Zoom held in reset, raycris and psyvarrv 60 s | what the BIOS and games actually touch |
| 5 | Existing M0 oracle logs (sim/oracle/<set>_cold300/sec.log and others) | CAT702 and znmcu traffic, all six games |
| 6 | XelaNotPu ZN2-Capcom fit numbers (docs/f0_budget.md 2.2) | area comparison only |

Trace logs, NVRAM and vectors are game-derived and stay under sim/
(gitignored). MAME CPU taps do not see DMA, so "not accessed" below means
not accessed by the CPU.

## 3. Main RAM

- MAME: `zn_base` sets the RAM to "4M" (zn.cpp 102). The BIOS writes
  0x0000433E to RAM_SIZE (0x1F801060) at 64 us (trace, both games); MAME
  reads nibble (value >> 8) & 0xF = 3 as the ZN-2 case, an 8 MB window
  (psx.cpp 1353-1402, `case 0x3: // zn2` at 1368), and mirrors 4 MB twice
  inside it.
- Board configuration register 0x1FA10200 reads 0x69 (trace, 8 reads in the
  first 15.5 s): RAM bits 01 = 4 MB, VRAM 2 MB, SPU RAM half a megabyte,
  revision 1 (zn.cpp 175-216 decodes the bits).
- Use: the CPU wrote 2 to 4 MB 10.2 M times (KUSEG) and 67.8 M times
  (KSEG0) in the Ray Crisis run and 217 M times (KSEG0) in the Psyvariar
  run; 4 to 8 MB was never read or written in any segment (counter taps
  from the first frame, 16 ms, to 120 s).
- PSX_MiSTer: `ram8mb` (status[85], PSX.sv 990) already gives 8 MB of
  distinct RAM: memorymux decodes RAM below 0x800000 (memorymux.vhd 599
  and 653 on this branch) and psx_top keeps address bit 22 when ram8mb = 1
  (psx_top.vhd 1375-1378);
  DMA masks bits 22-21 only when ram8mb = 0 (dma.vhd 741).

Decision for the first test: `ram8mb` tied to 1 in G-NET builds. No RTL
change. The difference from MAME (4 to 8 MB distinct instead of a mirror)
is invisible to software that never touches it. The PS1 meaning of RAM_SIZE
bits (psx-spx: 4 MB plus a locked area for this value) is not re-read this
session and is needs-review; it does not matter for these games.

MAME after 0.288: commit aab5dcadb (mamedev/mame, read through the GitHub
API 2026-10-05) rewrites `psxcpu_device::update_ram_config`: nibble 3 is
now `case 0x3: // zn2/namco system 12` in the 0x0400000 (4 MB) group, so
the ZN-2 RAM sits in a 4 MB window with bus error handlers from 4 MB up to
0x1EFFFFFF (and the KSEG0/KSEG1 copies), where 0.288 mirrored the 4 MB
twice in an 8 MB window. The same commit maps the 0x1F801000 I/O block in
all three segments and widens the SPU range to 0x1F801FFF. Three
behaviours for 4 to 8 MB, then: 0.288 a mirror, aab5dcadb a bus error,
this core (ram8mb = 1) distinct RAM. I implement the third and keep it for
the test build: the traces show no CPU access to 4 to 8 MB from 16 ms to
120 s, and the T1/T2 system runs match MAME's frames and bus traffic. A
BIOS probe of the RAM size before 16 ms, or a game that depends on the
bus error, would tell them apart (needs-review; neither has been seen). If
it matters, the change is in memorymux (bus error above 4 MB when
ZN2_MAP = 1).

## 4. BIOS ROM

- COH3002T BIOS: `m534002c-60.ic353`, 512 KB (taitogn.cpp 1016-1018), at
  0x1FC00000 like the PS1 BIOS. The BIOS writes BIOS delay/size 0x0013246F
  (size 2^19 = 512 KB) as its first store (trace).
- No CPU access above 0x1FC80000 in either run (counter taps).
- PSX_MiSTer maps 0x1FC00000-0x1FC7FFFF to SDRAM slot "01" & "00" & region
  (memorymux.vhd 624 and 686) and the loader writes ioctl index 0 to slot
  ioctl_index[7:6] (PSX.sv 565). The G-NET BIOS loads into slot 0 with the
  region fixed to 0. `fastboot` and `PATCHSERIAL` patch PS1 BIOS words
  (memorymux.vhd READBIOS); G-NET builds tie both to 0 (PATCHSERIAL already
  is, PSX.sv 1010; fastboot needs hasCD, which a G-NET build never sets).
- The BIOS zip also carries the CAT702 keys (`tt10.ic652`, `tt16.u17`, 8
  bytes each), `flash.u30` (2 MB, the sub-BIOS) and the bootleg EPROMs
  (taitogn.cpp 1019-1035). The uPD78081 ROM is NO_DUMP (1024).

## 5. Address map and bus configuration

### 5.1 Map (main CPU)

PS1 internal registers (0x1F801000-0x1F802FFF) are unchanged
(psx.cpp 1744-1776). ZN-2 additions, MAME 0.288. Trace counts are CPU
accesses in the warm 120 s runs of tools/mame/zn2_map_trace.lua:

| Address | Device | Source | Trace (raycris / psyvarrv) | Core block |
|---|---|---|---|---|
| 0x1F000000-0x1F7FFFFF | flash bank window (expansion 1) | taitogn.cpp 477, 490-506 | heavy | gnet_fc (M2) |
| 0x1FA00000, 0x1FA00100, 0x1FA00200, 0x1FA00300 | P1, P2, SERVICE, SYSTEM (8-bit, active low) | zn.cpp 148-151 | 55,904 / 55,596 reads; the BIOS also writes 0Fh then 1 to 7 to 0x1FA00000 (POST codes, needs-review), MAME ignores them | zn2_io |
| 0x1FA10000, 0x1FA10100 | P3, P4 | zn.cpp 152-153 | never read | zn2_io (FFh) |
| 0x1FA10200 | board configuration, 69h | zn.cpp 154, 175-216 | 8 / 9 reads | zn2_io |
| 0x1FA10300 | znsecsel: CAT702 and znmcu selects | zn.cpp 155, 253-270 | 380 / 379 writes; Shikigami also sets bit 4 (znmcu analog read) | zn2_io |
| 0x1FA20000 | coin counters and lockouts | zn.cpp 156, 218-231; taitogn.cpp 619-647 | 12,177 / 8 writes | zn2_io |
| 0x1FA30000 | control3 | taitogn.cpp 478 | | gnet_fc |
| 0x1FA40000 | reads 0 | zn.cpp 160 | 2 reads at 51-54 ms | zn2_io |
| 0x1FA51C00-0x1FA51DFF | reads 0 | zn.cpp 171 | 701,031 / 215,866 reads from 15.7 s / 7.4 s | zn2_io |
| 0x1FA60000 | bit 3 toggles per read; the SPU read routine polls it until bit 3 = 1 (section 11) | zn.cpp 172, 233-243 | 1,402,061 / 431,731 reads | zn2_io |
| 0x1FAF0000-0x1FAF07FF | AT28C16 EEPROM | zn.cpp 162 | raycris 32 reads at 15.7 s ("TAITO_TG..."), psyvarrv none | zn2_io |
| 0x1FB00000-0x1FB0FFFF | RF5C296 I/O, ATA task file | taitogn.cpp 479 | heavy | gnet_fc |
| 0x1FB20000-0x1FB20007 | reads FFFFh | zn.cpp 163, 245-251 | never | zn2_io |
| 0x1FB40000, 0x1FB60000, 0x1FB70000 | control, control2, 0x1FB70000 | taitogn.cpp 480-482 | | gnet_fc |
| 0x1FB80000-0x1FBE01FF | Taito Zoom host port and mailbox | taitogn.cpp 483-487 | used | zn2_io stub (section 12) |

CD (0x1F801800), SIO1 (0x1F801050), MDEC (0x1F801820) and expansion 2
(0x1F802000-0x1F803FFF) were never accessed by the CPU in either run.
Byte writes to 0x1FB68000 also occur (width trace, Ray Crisis) and hit no
MAME device; the core ignores them (needs-review: maybe a write-only latch
in the FC PCB CPLD).

### 5.2 How the PS1 memory controller sees it

The ZN-2 board registers sit in the PS1's expansion regions:

- Expansion 1 at 0x1F000000 (base register 0x1F801000 = 0x1F000000), size
  field 17h = 8 MB.
- Expansion 3 at 0x1FA00000, size field 15h = 2 MB, so 0x1FA00000-0x1FBFFFFF.
  This is why the whole ZN-2 register area is one region.

The BIOS sets these at reset (memctrl writes in the first 3.5 us: exp1
0x001734FF, exp3 0x00153410, BIOS 0x0013246F, SPU 0x200931FF, CD
0x00000843, exp2 0x00071077, com_delay 0x00031225). Software then rewrites
the delay/size registers before each device access (3.66 M memctrl writes
in 90 s of Ray Crisis), choosing the width and auto-increment per device
(the width trace, raycris warm 60 s):

| Register value | Width, auto-increment | Used for | Accesses seen |
|---|---|---|---|
| exp1 0x001724FF | 8-bit, on | U30 header and sub-BIOS read byte by byte, 54 to 77 ms | byte loads only |
| exp1 0x201716BB | 16-bit, off | flash window reads | halfword loads only |
| exp1 0x201726BB | 8-bit, on | card attribute memory (unlock, configuration) | byte loads and stores |
| exp1 0x201736BB | 16-bit, on | flash window, program and erase | halfword |
| exp3 0x00153410 | 16-bit, off | BIOS start: inputs, znsecsel, coin, control3, 0x1FB70000 | byte, halfword |
| exp3 0x20150688 | 8-bit, off | EEPROM | byte |
| exp3 0x201516BB | 16-bit, off | inputs, control, znsecsel | byte, halfword |
| exp3 0x20151EBB | 16-bit, off | ATA data port 0x1FB00000 | halfword (949,810) |
| exp3 0x20152EBB | 8-bit, on | RF5C296 ExCA (0x3E0/0x3E1) and ATA registers | bytes, including odd addresses |
| exp3 0x20153022 | 16-bit, on | 0x1FA51C00 area and 0x1FA60000 | halfword; 32-bit at 0x1FA60000 |
| exp3 0x201536BB | 16-bit, on | coin, inputs, control, Zoom mailbox | byte, halfword |

Two consequences:

1. In 8-bit mode every byte address must return its own byte. The BIOS
   reads the U30 license header "Licensed by Sony Computer Entertainment
   Inc." from 0x1F000004 one byte at a time (MAME, 54.5 ms). A 16-bit flash
   on an 8-bit bus would return the low byte twice unless the board steers
   bytes or the flash runs in x8 mode (the 28F160S3 has a BYTE# pin, to be
   checked on a board: needs-review). MAME presents the addressed byte; the
   core does the same (gnet_fc lane decode).
2. No 32-bit access to expansion 1 happens in 16-bit mode with
   auto-increment off, so the PS1 rule (both halves of a word access go to
   the same halfword address) never changes data for these games. The core
   keeps the PS1 rule from upstream's model; the test in 16.2 checks it.

## 6. CAT702 security

Two chips: TT10 on the ZN-2 board (`cat702_1`) and TT16 on the FC PCB
(`cat702_2`), both on SIO0 (taitogn.cpp 424-425; zn.cpp 127-135).

- Wiring (zn.cpp 127-135, zn.h 37-39): SIO0 SCK and TXD go to both chips;
  RXD is the AND of both chip outputs and the znmcu output. Selects come
  from znsecsel 0x1FA10300 bit 2 (TT10) and bit 3 (TT16), active low
  (zn.cpp 261-270). The SIO0's own DTR is not used for them.
- Protocol (cat702.cpp header and 202-245, sio.cpp 125-189): select low sets
  the state to FCh and the bit counter to 0. Per bit, SCK falls (at bit 0
  the state goes through a fixed sbox; the output is state bit n), the SIO
  drives TXD, SCK rises (if TXD is 0 the state goes through sbox n; the
  counter advances) and the SIO samples RXD. sbox 0 is the chip's 8-byte
  key; sbox n derives from sbox n-1 by a rotate with feedback.
- Data per game: none. The keys come with the BIOS (`tt10.ic652`,
  `tt16.u17`, taitogn.cpp 1019-1022), so every G-NET game uses the same
  two keys.
- Needed: yes. In all six priority games the BIOS talks to TT10 from 0.6 ms
  and to TT16 from 3.2 ms and is done by 0.12 s (Psyvariar: 2,775 and 1,155
  bytes, nothing later). TT16 is sent the text "Licensed by Sony Computer
  Entertainment..." among other bytes. Four games come back later: Ray
  Crisis at 158 s, XII Stag at 130 s, Night Raid until 228 s, and Shikigami
  no Shiro all through play (56,615 bytes to TT10 and 63,987 to TT16 in
  300 s) (sec.log, sim/oracle/<set>_cold300). What happens on a wrong
  answer is not traced (needs-review; a run with a wrong key in MAME would
  show it).
- Bit timing: the BIOS uses SIO0 mode 0Eh with baud 3 (x16, 48 CPU cycles
  per bit) and mode 0Dh with baud 2 (x1, 2 cycles per bit) (sec.log). MAME
  ticks one bit per prescaler x baud cycles of 33.8688 MHz (sio.cpp 80-121).

RTL: `rtl/gnet/zn_cat702.vhd`, bit level, verified (16.1, 16.4). Its
interface to the SIO0 is one strobe per bit with the TXD value; the chip's
output for that bit is read in the same clock (16.4 explains why).

## 7. znmcu, inputs, DIP switches, coin

### 7.1 Behaviour

- The uPD78081 MCU ROM is NO_DUMP (taitogn.cpp 1023-1024); MAME and
  XelaNotPu use a behavioural model (znmcu.cpp), R16.
- Select: znsecsel value AND 8Ch = 8Ch (zn.cpp 269, marked TODO in MAME).
  50 us after select the MCU pulses DSR low for 5 us (znmcu.cpp 44-63,
  107-142); on SCK falling edges it shifts out bytes LSB first: byte 0 =
  (data byte count << 4) | DSW (4 bits), then the data bytes; after each
  byte with more to come it pulses DSR again 50 us later.
- G-NET shooters: with znsecsel bits 4 (analog) and 5 (trackball) at 0,
  one data byte (00h) follows; trace rx bytes 1Fh then 00h (DSW all off =
  Fh). Ray Crisis sends 3 bytes to it in 200 s, Night Raid 121 in 300 s.
  Shikigami no Shiro selects it once with bit 4 set (znsecsel 9Ch at
  148.85 s) and receives 8Fh then eight FFh: the analog mode, eight
  channels, unconnected inputs reading FFh (znmcu.cpp 115-120, default FFh
  at line 10; ANALOG1/2 unused, taitogn.cpp 867-871). So the
  znmcu needs the analog mode too.
- DSW S551 (taitogn.cpp 859-865, 899-906): S551:2 service mode (BIOS test
  mode), S551:4 test mode, S551:1 and :3 unknown; all off by default.
- Inputs, active low (taitogn.cpp 798-857 with zn2p 877-897): P1 and P2 at
  0x1FA00000/0x1FA00100: up, down, left, right, buttons 1 to 4 (button 4
  unused on zn2p); SERVICE 0x1FA00200: bit 0 service, bit 1 service coin,
  bit 2 tilt, bits 4 to 7 button 5 per player (unused on zn2p); SYSTEM
  0x1FA00300: start 1/2 (bits 0-1), coin 1/2 (bits 4-5); starts 3/4 and
  coins 3/4 unused on zn2p.
- Coin register 0x1FA20000 (zn.cpp 223-231): bit 0 counter 1, bit 1
  lockout 1 (0 = locked), bit 4 counter 2, bit 5 lockout 2; ttgncl4
  (Psyvariar, Night Raid) adds lockouts 3 and 4 on bits 3 and 7
  (taitogn.cpp 634-647). Ray Crisis writes 22h (both coins unlocked),
  Psyvariar AAh.
- JP1 (bootleg sets only) selects flash bank 2 (taitogn.cpp 911-923).

### 7.2 SIO0 in the core

PSX_MiSTer's joypad.vhd is the SIO0 register model plus pad and memory card
models; LEAN removes it (HAS_PADS = 0, psx_top.vhd 1149-1168). The ZN-2
needs the register model with raw SCK, TXD, RXD and DSR lines instead:
`rtl/gnet/zn_sio0.vhd` on the bus_pad port with data, status, mode,
control and baud as MAME's sio.cpp (rank 5), one bit every prescaler x baud
cycles, DSR into status bit 7 and the IRQ7 request when control bit 12 is
set (sio.cpp 330-345). PSX_MiSTer's joypad.vhd times a byte as baud x 8
cycles and ignores the prescaler (PS1 timing from hardware tests); MAME
multiplies by the prescaler. For the BIOS's CAT702 setting (mode 0Eh, baud
3) that is 384 against 24 cycles per byte. Which the CXD8661R does is open
(needs-review); zn_sio0 defaults to MAME's rule, generic PS1_TIMING = 1
selects joypad.vhd's. Control values the BIOS uses:
0040h (reset), 0002h, 2002h, 2003h, 2050h, 1013h (DSR interrupt enable, for
the znmcu) (sec.log). IRQ7 is not in I_MASK (section 9), so the BIOS polls
STAT.

## 8. EEPROM

- Atmel AT28C16, 2K x 8, at 0x1FAF0000-0x1FAF07FF, one byte per address
  (zn.cpp 162; taitogn.cpp 74). Ray Crisis reads its first 32 bytes at
  15.7 s ("TAITO_TG" header); neither game wrote it in 120 s without input.
- Write: self-timed byte write, 1 ms (standard part) or 200 us (E option)
  (datasheet p. 1 and ordering table); MAME uses 200 us (at28c16.cpp 164,
  179). Which part the ZN-2 carries is unknown (needs-review); the core
  parameter defaults to 200 us.
- During the write a read returns the written byte with bit 7 inverted
  (DATA polling, datasheet p. 2; at28c16.cpp 184-190) and writes are
  ignored. MAME skips writes of the value already stored (at28c16.cpp 172);
  the datasheet does not, nor does the core (difference recorded).
- MAME's NVRAM file is 2,080 bytes: the 2,048 data bytes then 32 ID bytes.
- In the core: 2 M10K (dpram) with a shell port for MRA NVRAM load and
  save (zn2_io).

## 9. Interrupts

- I_MASK values written (trace, raycris): 0x000, 0x001, 0x009, 0x029,
  0x409, 0x429, 0x449, 0x469. Bits used: 0 VBLANK, 3 DMA, 5 timer 1, 6
  timer 2, 10 (PIO / lightpen line).
- No MAME G-NET device drives IRQ10 (`intin10` is used only by other ZN
  boards, zn.cpp 1352 and 2127). The RF5C296 card interrupt goes nowhere:
  the BIOS writes 03h = 00h/40h/70h, whose bits 3-0 select "IRQ not
  selected" (RF5C296 datasheet, register 03h, printed p. 34), and never
  writes 05h (docs/gnet_glue_design.md 4).
- The Zoom interrupt runs the other way (main CPU to MN10200, taito_zm.cpp
  139-149).
- So the glue raises no interrupt. PSX_MiSTer's IRQ10 input (irq_LIGHTPEN)
  is idle in LEAN. Software polls SIO0, the flash status and the ATA
  status.

## 10. PS1-only devices

| Device | ZN-2 | Core |
|---|---|---|
| CD-ROM (0x1F801800) and CD DMA (channel 3) | no drive; never accessed; DPCR never enables channel 3 (writes 33333333h, 33333B33h, 3B333B33h, 3B3B3B33h) | HAS_CD = 0 (LEAN) |
| Pads and memory cards | SIO0 carries CAT702 and znmcu instead | HAS_PADS = 0 (LEAN), zn_sio0 on the bus_pad port |
| MDEC | unused (docs/r18_mdec_spu.md) | HAS_MDEC = 0 (LEAN) |
| SIO1, expansion 2 | never accessed | left as upstream (idle) |
| PS1 BIOS patches (fastboot, PATCHSERIAL, EXE loading) | not applicable | tied off in G-NET builds |

DMA channels used: GPU (2), OTC (6) and SPU (4) (DPCR values above).

## 11. SPU

- Present on the ZN-2 (CXD2925Q, 512 KB RAM; board configuration bit 2 = 0
  means half a megabyte, zn.cpp 181). Used by all six games
  (docs/r18_mdec_spu.md). So the "silent" RBF still plays SPU sound; only
  the Zoom music and effects are missing.
- MAME mixes the SPU at 0.3 under the Zoom at 1.0 (taitogn.cpp 441-448), R13.
- ZN-2 specific (MAME 0.288 trace, main
  ab64f26, docs/r1_cpu_domain_design.md "Measurement 1"): every SPU
  register read in raycris and psyvaria goes through one routine. It does a
  dummy read at 0x1FA51C00 + the register offset (any data), polls
  0x1FA60000 until bit 3 is set (up to 100 tries; on timeout it prints
  "SPU:T/O [ReadStatusFlag Error]"), then reads the real register at
  0x1F801C00 + offset. Writes skip it. Around these reads the games also
  switch the SPU delay register between 0x20093127 and 0x200931FF (645,000
  writes each in 90 s of Ray Crisis, my trace). MAME calls the pair a "work
  around for mismatched CPU & SPU clock?" (zn.cpp 170): 0x1FA51C00-0x1FA51DFF
  reads 0 and 0x1FA60000 toggles bit 3 on every read (zn.cpp 233-243).
- Upstream PSX_MiSTer returns 0 for 0x1FA60000 (its internal bus answers
  unmapped addresses with 0), so every SPU read would time out: about 6,722
  per second in raycris. With ZN2_MAP = 1 the whole 0x1FA00000-0x1FBFFFFF
  range goes to the zn_* bus (13.1), and zn2_io answers 0x1FA51C00-0x1FA51DFF
  with 0 and 0x1FA60000 with bit 3 set: generic SPU_STATUS = 0 toggles as
  MAME (first read 8, so the routine needs one or two polls), SPU_STATUS =
  1 returns bit 3 = 1 always (one poll; enough for both games per the
  trace). SPU_STATUS = 0 is verified (16.3); 1 is a constant and not
  simulated separately. The real register is open (R2); a
  constant flag would mean the board never makes the CPU wait for the SPU,
  which is part of the R1/R23 timing question.

## 12. Taito Zoom absent

- Test in MAME: a write tap forced control bit 4 (Zoom reset) to 1 for the
  whole run. The MN10200 stayed at its reset vector (PC 80000h at the end)
  and both Ray Crisis (60 s) and Psyvariar -Revision- (60 s) reached the
  attract demo (snapshots at 25 s and 55 s). Neither game waits for the
  Zoom.
- So the silent RBF needs only: the mailbox RAM (M66220FP, 256 x 8, lanes 0
  and 2 of 0x1FBE0000-0x1FBE01FF, taitogn.cpp 487), status 0x1FBC0000 = 0
  (taito_zm.cpp 145-149), and ignored writes to 0x1FB80000-0x1FB80003 and
  0x1FBA0000. zn2_io has these.
- The forced runs wrote control with bit 4 clear only 3 times, against 300
  times in 20 s without forcing, so the software reads control back and
  keeps the bit it finds.
- Bootleg sets with `init_nozoom` (Aero Fighters Special, Brave Blade) run
  the same way in MAME (taitogn.cpp 416-419, 519).

## 13. Integration plan for the silent test RBF

### 13.1 psx_top and memorymux

A new psx_top generic `ZN2_BOARD` (default 0 = upstream; PSX.sv macro
GNET_ZN2) does all of the following in one generate:

1. memorymux `ZN2_MAP => ZN2_BOARD` (written and verified, 16.2).
2. A small bus top on memorymux's zn_* port: decode by address to
   `gnet_fc` (flash window, 0xA30000, 0xB00000-0xB0FFFF, 0xB40000,
   0xB60000, 0xB70000) or `zn2_io` (its `hit`), else answer 0 with an ack.
   gnet_fc takes one 16-bit lane per request (its 32-bit port with byte
   enables, as memorymux sends them).
3. `zn_sio0` on the bus_pad port (joypad is already removed by
   HAS_PADS = 0), with zn_cat702 x2 and znmcu on its lines; its IRQ to
   irq_PAD (IRQ7).
4. New psx_top ports, all with defaults so the upstream instantiation in
   psx_mister.vhd and the PSX revision stay as they are: inputs (P1, P2,
   SERVICE, SYSTEM, DSW, JP1), coin out, CAT702 key load, card metadata
   load, EEPROM shell port, flash storage port (to SDRAM, 13.4), card
   storage handled inside psx_top by a new DDR3 arbiter client (13.4).
5. `ram8mb` = 1 and the region fixed to 0 in G-NET builds (PSX.sv).

### 13.2 Clock and wait states

- Everything runs on clk1x (33.8688 MHz) for the first test, glue
  parameter CLK_HZ = 33,868,800. No clock crossing.
- memorymux keeps the PS1 bus timing: each expansion step waits the
  programmed read/write delay (ex1/ex3_memctrl, com_delay), then issues its
  zn request and holds until zn_ack. So the device latency adds to the
  programmed delay. The real FC PCB's wait behaviour is unknown
  (needs-review); MAME has no bus timing for these regions at all.
- M2 found the glue needs about 10 clk1x cycles per access before the
  storage latency (docs/m2_glue_findings.md 1 and 5). The BIOS reads U30 up
  to about 2.9 M times per emulated second during boot (flashrd.log), so
  flash read latency shows directly in boot time. First test: accept it and
  measure. Then: issue the request at the start of the step so the device
  latency overlaps the programmed delay, a small read cache in front of the
  SDRAM flash port, or the glue on clk2x as M2 suggests.

### 13.3 Resets and the watchdog

- gnet_fc's MB3773 model resets after 5 s without a kick on control bit 5
  (MAME's period, R17). wd_reset goes to the core reset. A debug OSD option
  disables it, so a missing kick shows as a 5 s reset loop rather than
  hiding a hang.
- Control bit 4 (Zoom reset) goes nowhere in the silent build.
- Debug overlay (OSD "Debug overlay", status bit 101, default Off): hex
  text on the picture with the live PC, last data and I/O addresses, ms
  since reset, ms since the last watchdog kick, reset and ATA command
  counts, and a snapshot taken at each watchdog expiry that survives the
  reset. How to read it: docs/hw_debug_overlay.md.

### 13.4 Memory layout

SDRAM (32 MB, ram_Adr 25-bit byte address; EXE_START and BIOS_START at
PSX.sv 511-512):

| Range | Contents | Size | Access |
|---|---|---|---|
| 0x0000000-0x07FFFFF | main RAM (4 MB used) | 8 MB region | CPU ch1/ch2 (upstream) |
| 0x0800000-0x087FFFF | BIOS, slot 0 | 512 KB | upstream (BIOS_START) |
| 0x1000000-0x11FFFFF | U30 sub-BIOS flash | 2 MB | ch3 (cheats channel, free in LEAN) |
| 0x1200000-0x127FFFF | U27 Zoom program flash | 512 KB | ch3 |
| 0x1400000-0x19FFFFF | U56, U55, U29 wave flashes | 6 MB | ch3 |

0x1000000 is the EXE load area (EXE_START), unused by G-NET. The ch3 port
is 32-bit with byte enables (sdram.sv 69-75); a flash word is one half.
For the Zoom later the wave flashes may move to DDR3 because the ZSG-2
reads them continuously (decided with the Zoom design).

DDR3 (the core's 256 MB window at 0x30000000, psx_mister.vhd 303-304):

| Byte offset | Contents | Size |
|---|---|---|
| 0x0000000 | VRAM (2 MB with VRAM_Y_BITS = 10) | 2 MB |
| 0x0300000 | SPU RAM (SPUSDRAM = 0 in LEAN) | 512 KB |
| 0x0400000 up | GPU frame buffers | (upstream) |
| 0x4000000 | PC card image | 40,960,000 bytes |

The memory card clients x"01"/x"02" of the DDR3 arbiter overlap 2 MB VRAM
but are removed with the pads (psx_top.vhd 1163-1164). The card needs a
new arbiter client with a wider address than the 20-bit card fields
(psx_top.vhd 300-325), holding the last 64-bit line so a sector costs 64
DDR3 reads; every grant pauses VRAM (psx_top.vhd 896), acceptable for
the few hundred to few thousand sectors a game reads. The exact upper end of
the frame buffer area is needs-review before the offset is fixed.

### 13.5 Loader and MRA

| ioctl index | Content | Destination | From |
|---|---|---|---|
| 0 | BIOS `m534002c-60.ic353` | SDRAM BIOS slot 0 | coh3002t.zip (existing path, PSX.sv 498, 565) |
| 2 | CAT702 keys: `tt10.ic652` then `tt16.u17` (16 bytes) | zn_cat702 key ports | coh3002t.zip |
| 3 | flash area, 10 MB as SDRAM 0x1000000-0x19FFFFF: U30 at 0, U27 at 0x200000, U56 0x400000, U55 0x600000, U29 0x800000, little-endian 16-bit words (the ROM file order; MAME's NVRAM files are big-endian) | SDRAM flash area | cold: `flash.u30` from coh3002t.zip then 8 MB of FFh (MRA repeat); warm: `<set>.flash` from `tools/gnet/make_game_zip.py --warm` (build_flash.py output, byte-swapped) |
| 4 | card metadata: IDNT at 000h, CIS at 200h, KEY at 300h (1 KB) | gnet_fc meta port (gnet_ata.sv 128-134) | `tools/extract_card.sh` output |
| 5 | card image (40,960,000 bytes) | DDR3 card area | `tools/extract_card.sh` output |
| 6 | EEPROM 2 KB (NVRAM) | zn2_io shell port | MRA nvram, saved by Main (needs ioctl_upload in hps_io, not wired in PSX.sv) |
| 254 | DIP switches S551, JP1 | zn_sio0 / znmcu, gnet_fc | MRA switches |

MiSTer cannot read the hard-disk CHDs, so the card image and its metadata
are prepared once per game by the existing tools, and the flash images by
build_flash.py for a warm boot. Dirty card sectors (R25) are not saved in
the first test. Two ways for release, Lee to choose: card as an MRA ROM in
DDR3 with a dirty-sector save path, or the card as an OSD-mounted image read
and written through the hps_io block interface into the same DDR3 copy (the
pattern PSX_MiSTer uses for memory cards).

### 13.6 Inputs in PSX.sv

Map the MiSTer joysticks to P1/P2 (directions, buttons 1 to 3), SYSTEM
(start 1/2, coin 1/2), SERVICE (service, service coin, tilt), active low;
DSW and JP1 from the MRA switches; rotation per set (ROT0 / ROT270,
docs/PLAN.md 2) through the existing framework screen rotation.

### 13.7 CPU rate

The first test runs the CPU at the stock PS1 rate (clk1x 33.8688 MHz).
MAME's ZN-2 model is 1.476 times that and the PCB measures 0.82 of MAME
(docs/r1_speed_study.md), so CPU-bound parts (boot loader, flash copy
loop) run slower than on the PCB. Video timing is unchanged: 53.693175 MHz
/ 3413 / 263 = 59.826 Hz, the rate MAME's notes give for the PCB
(taitogn.cpp 83).

### 13.8 What the first test should show

From the MAME traces (docs/m0_findings.md 3, docs/m1_gpu_zn2.md 2):

| Test | Setup | Expected |
|---|---|---|
| T1 | BIOS, keys, flash.u30 in U30; no card | CAT702 exchange in the first 0.12 s, Taito G-NET logo (frames 30 to 60 in M1), then "SYSTEM ERROR" (taitogn.cpp 17-18). Proves CPU, BIOS, GPU, expansion bus, CAT702 and the U30 sub-BIOS decrypt |
| T2 | T1 plus card image and metadata; other flashes blank | card unlocked, flash copy screen from 2.9 s to about 141 s (MAME timing preset; longer with datasheet timing and the slower CPU), then the game's attract with SPU sound only |
| T3 | warm flash images from build_flash.py | attract after about 15 s (EEPROM read at 15.7 s in the Ray Crisis trace) |
| T4 | T3 plus coin and start | game play, silent apart from SPU |

Watch points: a 5 s reset loop (watchdog not kicked: control register path),
a hang at the license check (8-bit expansion reads), a hang after "SYSTEM
ERROR" never appearing (CAT702 or SIO0), and the flash status polling.

## 14. ALM estimates

Base: B1 27,709 ALMs, 245 M10K, 83 DSP (docs/cpu_rate_probe.md). Paper
estimates (flip-flops plus logic; one ALM holds two LUTs and up to four
registers) unless marked.

| Block | ALMs | M10K | Basis |
|---|---|---|---|
| memorymux ZN2_MAP | 80 to 150 | 0 | about 140 new registers (address, enables, write data, read latch) and lane muxes; XelaNotPu's ZN map cost +187 (measured, f0_budget 2.2) |
| zn2_io | 100 to 180 | 2 (+1 or MLAB mailbox) | about 130 registers, read mux |
| zn_cat702 x2 | 240 to 360 | 0 | per chip 64 key + 64 coefficient + 8 state registers, two 8 x 8 GF(2) products |
| znmcu | 40 to 80 | 0 | two timers, bit/byte counters |
| zn_sio0 | 150 to 300 | 0 | joypad.vhd's register and baud part (joypad total 1,053 with pads, f0_budget 1.1) |
| gnet_fc and blocks | 1,180 to 1,790 | 5 | docs/m2_glue_findings.md 4 |
| flash port to SDRAM ch3 | 80 to 150 | 0 | address map, 16/32 conversion |
| card port and DDR3 client | 150 to 250 | 0 | line buffer, arbiter state |
| loader and inputs in PSX.sv | 130 to 260 | 0 | index decode, address counters, input mapping |
| **Total** | **2,150 to 3,520** | **7 to 8** | |

Projection: 29,860 to 31,230 ALMs (71.2 to 74.5%), about 253 M10K (46%),
83 DSP. XelaNotPu's ZN-2 I/O (SIO0, CAT702 x2, znmcu, inputs, EEPROM)
measured 693.5 ALMs (f0_budget 2.2) against 530 to 920 here for the same
set.

## 15. Fit revision to queue

Ready, not queued (I have not run Quartus): revision `GNET_Z1`
(GNET_Z1.qsf) is GNET_B1.qsf byte for byte (CRLF and LF lines kept) plus
`VERILOG_MACRO "GNET_ZN2=1"` and the rtl/gnet SystemVerilog and VHDL files,
same SDC (GNET_LEAN.sdc) and seed (1). `tools/pc_build.sh z1` builds it
(DIR gn_z1, TASK gnz1). The gnet files are only in GNET_Z1.qsf, so every
other revision compiles as before. A synthesis-only run of revision PSX
(target psxsw) would confirm that the ZN2_BOARD = 0 paths in psx_top and
psx_mister and the GNET_ZN2-off paths in PSX.sv leave upstream unchanged
(memorymux is already checked cycle by cycle, 16.2).

## 16. RTL in this branch and verification

All new VHDL is GPL-2.0-or-later (docs/licensing.md), simulated with NVC
1.23 (VHDL-2008) under nice -n 15.

### 16.1 zn_cat702 (rtl/gnet/zn_cat702.vhd)

- First version drove SCK and TXD as levels; the final interface is one
  strobe per bit (16.4). Both pass the same replay.
- `tools/gnet/cat702_ref.py` is a reference model of MAME's algorithm and
  SIO bit order. It reproduces every byte MAME's SIO0 received from either
  CAT702 in the six cold 300 s oracle runs.
- `sim/zn2/run_cat702.sh <run dir>` turns that traffic into vectors (keys
  from coh3002t.zip, into sim/zn2/work/) and drives the RTL bit by bit as
  sio.cpp does (SCK low, TXD, SCK high, sample).

| Set | TT10 bytes | TT16 bytes | Mismatches |
|---|---|---|---|
| raycris (200 s) | 2,783 | 1,163 | 0 |
| psyvarrv | 2,775 | 1,155 | 0 |
| xiistag | 2,783 | 1,163 | 0 |
| shikigam | 56,615 | 63,987 | 0 |
| nightrai | 3,487 | 2,059 | 0 |
| psyvaria | 2,775 | 1,155 | 0 |

Total 141,900 bytes. Sensitivity: with one key bit changed, 2,629 of the
2,783 TT10 bytes of raycris differ.

### 16.2 memorymux ZN2_MAP (rtl/memorymux.vhd)

Changes, all inactive for ZN2_MAP = 0: a generic, seven ports with
defaults, the exp3 decode widened to 0x1FA00000-0x1FBFFFFF, one request per
expansion bus step with the step's lane, width-aware read assembly, and a
stall in EXT_READ / EXT_WRITE_WAIT until zn_ack. Upstream code is not
re-indented.

- Equivalence (`sim/zn2/run_memorymux.sh eq N SEED`): upstream memorymux
  from main (identical to upstream/main) against ZN2_MAP = 0, same
  pseudo-random CPU stimulus, every output compared every clock. Regions:
  RAM, BIOS (data and instruction fetch), internal registers, GPU, MDEC,
  SPU, CD, expansion 1, 2 and 3 including the ZN-2 range, all sizes, random
  delay/size and com_delay values, KUSEG/KSEG0/KSEG1, ce gaps while idle.
  Result: 0 differing cycles over 420,000 requests (seeds 1, 2, 3; 20,000,
  200,000, 200,000). Sensitivity: the same run against ZN2_MAP = 1 differs
  in 306,616 cycles.
- Directed (`sim/zn2/run_memorymux.sh zn SEED`, ZN2_MAP = 1, device latency
  1 to 13 cycles, seeds 1 to 3): 16-bit and 8-bit expansion 3 writes and
  reads with odd bytes (ExCA 3E0h/3E1h style), the 0x1FA60000 32-bit read in
  two lanes, expansion 1 16-bit with auto-increment off (both word halves
  from the first halfword, the PS1 rule), expansion 1 8-bit byte reads of
  the license header (each byte its own request), KSEG1 addresses, ce gaps
  during a stalled read. All pass.
- Testing found one point to keep in mind: ram_done arriving while ce is
  low is lost in upstream memorymux too; PSX_MiSTer only lowers ce when
  paused and idle, so the equivalence test inserts ce gaps only when idle.

### 16.3 zn2_io (rtl/gnet/zn2_io.vhd)

- Directed tests (`sim/zn2/run_zn2_io.sh`): board configuration, inputs,
  POST writes ignored, znsecsel and coin, the 0x1FA60000 toggle sequence (8,
  0, 8, upper lane 0), 0x1FA51DAC/0x1FA40000/0x1FB20000, hit decode, EEPROM
  byte lanes, write with DATA polling and the ignored write while busy, the
  shell port, mailbox lanes, Zoom status, and ten passes of the SPU read
  routine (dummy read, poll until bit 3 is set: never more than two polls).
  0 errors.
- Replay (`sim/zn2/run_zn2_io.sh <zn2map run> <at28c16>`): every logged
  access to the inputs, board configuration, znsecsel, coin, 0x1FA40000 and
  the EEPROM from the MAME map traces, with the EEPROM preloaded from the
  NVRAM the run started from. raycris: 61,121 reads and 12,562 writes;
  psyvarrv: 48,834 reads and 394 writes; 0 mismatches.

### 16.4 SIO0, CAT702 x2 and znmcu together (rtl/gnet/zn_sio0.vhd, znmcu.vhd)

`sim/zn2/run_sio0.sh <oracle run>` replays every main-CPU SIO0 access and
every znsecsel write from the M0 oracle's sec.log at its emulated time
(33.8688 MHz cycles) into zn_sio0 with both zn_cat702 (keys from the BIOS
zip) and znmcu (DSW all off) on its lines, and compares every read (data,
status, control) on its byte lanes. Idle gaps over 3 s are shortened to
3 ms (every model timer has run out by then).

A first version with SCK as a level and registered device outputs read the
status one bit late at every byte: MAME does the whole bit (SCK low, TXD,
SCK high, sample) at one instant. The devices now take one strobe per bit
and present their output combinationally, which gives MAME's tick times.

MAME logs an access at its CPU's local time, in steps of one MAME CPU cycle
(40 ns, 1.35 system cycles), and runs timers between CPU slices, so a
status read logged right at a tick can fall on either side. A status read
that differs is read again for up to 3 cycles; if it then matches it is
counted as a timing-tolerance match. Data and control reads must match
exactly.

| Set | Reads | Writes | znsecsel writes | Exact | Within 1 cycle | Within 2 | Mismatches |
|---|---|---|---|---|---|---|---|
| raycris (200 s) | 23,705 | 4,592 | 380 | 19,752 | 3,952 | 1 | 0 |
| psyvarrv | 23,627 | 4,585 | 379 | 19,668 | 3,956 | 3 | 0 |
| xiistag | 23,705 | 4,603 | 384 | 19,752 | 3,950 | 3 | 0 |
| nightrai | 34,367 | 7,193 | 1,079 | 30,078 | 4,210 | 79 | 0 |
| psyvaria | 23,627 | 4,585 | 379 | 19,669 | 3,957 | 1 | 0 |
| shikigam | 723,704 | 150,437 | 29,548 | 719,738 | 3,963 | 3 | 0 |

The RTL is never ahead of MAME; it is one cycle behind at about one status
change per byte, within MAME's timestamp step. Night Raid's 121 znmcu bytes
(DSR pulses and the DIP byte) and Shikigami's analog-mode read are in these
runs.

### 16.5 Integration

The bus top, psx_top and PSX.sv integration, the SDRAM flash port, the DDR3
card client and the loader are in section 18.

## 17. Open questions

Test-build defaults (2026-10-05): Q1 to Q6 below are set as
listed for the first silent test RBF. They are reversible and Lee decides
the release choices later.

1. Card image path for release: MRA ROM in DDR3 with a dirty-sector save
   path, or an OSD-mounted image through the hps_io block interface (13.5)?
   Test build: MRA-loaded ROM in DDR3, card writes kept in DDR3 only.
2. MRA data layout: one prepared zip per game holding the card image,
   metadata and (optionally) warm flash images, made by a script from the
   CHD and coh3002t.zip? MiSTer cannot read hard-disk CHDs. Test build: yes,
   `tools/gnet/make_game_zip.py`, output in gnet_games/ (gitignored).
3. First test cold (BIOS does the flash copy, about 2.5 min with MAME
   timing) or warm (build_flash.py images)? Test build: T1 and T2 cold
   first; a warm MRA is there too.
4. Watchdog: test build keeps the 5 s reset active, with an OSD option
   (status bit 100) to disable it.
5. Wave flashes: test build keeps them in SDRAM; DDR3 may follow for the
   Zoom (13.4).
6. SIO0 bit timing: test build uses MAME's prescaler x baud (zn_sio0
   default); joypad.vhd's PS1 rule stays a generic (7.2). SPU_STATUS: MAME's
   toggle. A timing test program on a CXD8661R board would settle both
   (R1 already asks for one).
7. Needs-review items to settle on a board: bus waits on the FC PCB (13.2),
   U30 byte mode on the 8-bit bus (5.2), 0x1FA00000 POST writes and
   0x1FB68000 writes (5.1), AT28C16 part suffix (8), CAT702 failure path
   (6), the real 0x1FA60000 register (R2).
8. BIOS speed: the core runs the BIOS's ROM-resident code about ten times
   slower than MAME (18.3). PS1-like ROM timing (8-bit BIOS bus, 25 cycles
   per word) against MAME's flat cost per instruction; PCB footage of the
   first seconds of a cold boot (logo to SYSTEM ERROR without a card) would
   show which is right.
9. Flash program and erase timing: the FC PCB photo shows TE28F160 S5100
   (28F160S5, 5 V VPP) on U30 and U29, and U27 is E28F400B5B80 (bottom
   boot, as MAME) (docs/board_evidence.md P1, S2, S9). The accurate
   gnet_flash timing is therefore PRESET 3: 28F160S5 typical, 9.24 us per
   word and 0.34 s per block erase (290609-004 p49), about 77.5 s of flash
   time for the first-boot copy (docs/m0_findings.md 72-77) against MAME's
   121 s of erase constant. PRESET 3 is in gnet_flash.sv and passes the
   gnet_fc directed tests (67/67, as presets 1 and 2). The test build
   keeps PRESET 1 (MAME: instant program, 1.0 s erase) so its first boot
   can be compared with MAME; the release choice is mine. PRESET 2
   (28F160S3 at 2.7 V) stays for comparison only.
10. Security select during play: Shikigami writes znsecsel once or twice
   per frame during play (1Ch, 94h, 98h in the 300 s oracle run: 14,584,
   7,853 and 6,729 writes after 60 s), each time with 4 SIO0 bytes; the
   other games only at boot. With MAME 0.288's decode (zn.cpp 271-282; the znmcu select is marked TODO
   at 279) 94h
   and 98h select a CAT702 (bit 3 or bit 2 low) and leave the znmcu
   deselected ((v and 8Ch) /= 8Ch); which device answers on a real board
   is open. The integrated path has no boot-only state: zn_cat702 restarts
   a session at every select falling edge and keeps its key registers
   through resets (written only by the loader), znmcu restarts at every
   select and rebuilds its reply at the first DSR pulse, zn_sio0 and the
   znsecsel register take any access at any time, and zn2_board wires them
   exactly as the replay testbench (sim/zn2/tb_sio0_replay.vhd 67-81). The
   Shikigami replay (16.4: 723,704 reads, 29,548 znsecsel writes over 300
   s, 0 mismatches) covers the in-play accesses. znmcu keeps MAME's
   behaviour of not clearing bytes 1 to 8 between sessions (znmcu.cpp
   send buffer filled with 0 only at start).

## 18. Integration for the silent test RBF (GNET_Z1)

### 18.1 What is integrated

| Where | What |
|---|---|
| rtl/psx_top.vhd | generics ZN2_BOARD (default 0), ZN2_FLASH_PRESET, ZN2_PS1_SIO, ZN2_SPU_STATUS; memorymux ZN2_MAP => ZN2_BOARD; zn2_board on the zn_* port and on bus_pad (SIO0, IRQ7) in place of joypad; a fifth DDR3 arbiter client for the card; new ports with defaults, outputs tied off when ZN2_BOARD = 0 |
| rtl/psx_mister.vhd | the same generics and ports passed through |
| rtl/gnet/zn2_board.vhd | bus top (gnet_fc or zn2_io by address, else 0), zn_sio0 + zn_cat702 x2 + znmcu, loader byte split (keys, card metadata, EEPROM), EEPROM erase at power-up, gnet_fc flash port to a 32-bit SDRAM port |
| rtl/gnet/zn2_cardmem.vhd | card image in DDR3 at 64 MB: loader (four 16-bit words per 64-bit write, dl_busy for ioctl_wait) and gnet_ata's word port (one-line read buffer, 16-bit writes with byte enables) |
| rtl/gnet/gnet_fc.sv | new input card_present (empty slot reads FFFFh, RF5C296 reports no card; Verilator directed tests 67/67) |
| PSX.sv (GNET_ZN2) | G-NET OSD (DIP menu, watchdog option, video options), ioctl indexes 2 to 6 and 254 (13.5), SDRAM ch3 to the flash port after downloads, ram8mb = 1, fastboot off, BIOS slot 0, inputs (13.6), watchdog reset held 256 clocks, downloads hold reset |
| GNET_Z1.qsf, tools/pc_build.sh z1 | section 15 |
| mra/ | Ray Crisis cold boot (T2), Ray Crisis warm boot (T3), G-NET BIOS without card (T1) |
| tools/gnet/make_game_zip.py | gnet_<set>.zip: card image, metadata, with --warm the 10 MB flash area |

Upstream builds: every change is behind ZN2_BOARD = 0 or `ifdef GNET_ZN2`,
apart from the memorymux generic (checked cycle by cycle, 16.2), the
gnopadbus split of the trimmed joypad outputs and the arbiter's extra
client (both constant when ZN2_BOARD = 0). A Verilator parse of PSX.sv with
and without GNET_ZN2 finds no syntax error (only the modules it cannot see:
framework and VHDL).

### 18.2 ALM expectation

The estimate of section 14 stands: 2,150 to 3,520 new ALMs, 29,900 to
31,200 ALMs in all (71 to 75% of the 5CSEBA6) on top of B1's 27,709, about
253 M10K, 83 DSP. zn2_cardmem (about 230 registers: two 64-bit line
buffers, address, state) and the bus top are inside the "card port and
DDR3 client" and "loader and inputs" rows. GNET_Z1 replaces this with a
measured figure.

### 18.3 System simulation

`sim/zn2/system/run.sh <name> <ms> [set]` builds psx_top with ZN2_BOARD = 1
and the LEAN trims, the real sdram.sv (R1 simulation copy,
tools/r1/mem_lat/sdram_sim_copy.py) with a chip model preloaded with the
BIOS (0x800000) and flash.u30 (0x1000000, other flash chips FFh), a DDR3
model (VRAM, SPU RAM, card image at 64 MB), and drives the CAT702 keys and
card metadata through the loader port. gnet_fc (SystemVerilog) runs in
Verilator behind VHPIDIRECT (sim/zn2/cosim), the rest in NVC. Logs: every
CPU write to GP0/GP1, every expansion bus request, every SIO0 access, the
CPU PC and frame count every 100 us, and a VRAM dump every 250 ms.
Speed: about 0.6 ms of emulated time per second with one simulation
running, 0.35 ms/s each with two.

Inputs are the real BIOS files from coh3002t.zip and, for T2, the Ray
Crisis card image and metadata from tools/extract_card.sh; all under
sim/zn2/work/ (gitignored). MAME references: `oracle_run.sh coh3002t 6
--cold` (no card; GPU log) and a run with VRAM dumps at frames 10 to 180
(sim/oracle/coh3002t_vram), and the raycris cold oracle run for T2.

Results (T1: no card, run to 3.79 s; T2: Ray Crisis card, cold flashes,
run to 5.20 s; figures at the times given):

| Check | Result |
|---|---|
| Reset | PSX_MiSTer's reset sequencer (savestates.vhd in reset mode: SPU RAM, VRAM and main RAM cleared through the savestate ports) takes 90 ms of emulated time before the CPU leaves 0xBFC00000; upstream behaviour, not in MAME |
| Board configuration, znsecsel, coin, POST writes | as MAME: 0x69 read, znsecsel 0Ch/88h, coin 0; POST codes to 0x1FA00000 in MAME's order (0Fh, 1, 2, 3, 4, 1, 3, 4, 5, 6, 2, 5, ...) |
| CAT702 through the whole integrated path | every byte sent to and received from a CAT702 equals the reference model (sim/zn2/system/check_cat702.py): T1 3,374 bytes by 600 ms. The first 166 byte pairs equal MAME's exactly; then the BIOS's challenge sessions differ in length (MAME 71, 71, 104, 66, 27, 53 bytes; core 36, 11, 19, 128), after which the next sessions (133 bytes each) are byte-identical to MAME's. The session lengths depend on CPU timing (see below) |
| GPU | T1: all 1,187 CPU writes to GP0/GP1 up to 3.41 s equal MAME's first 1,187 in order (MAME reaches that count at 2.69 s) except one extra E1h (draw mode) write at position 242 (timing of an interrupt-driven write); T2: 1,145 of 1,145 equal MAME's raycris cold run with the same exception; sim/zn2/system/compare_gpu.py |
| VRAM, T1 to the end screen | the whole 2 MB VRAM at 1.00 s equals MAME's at frame 15 (logo fading in), and from 1.25 s to 3.25 s MAME's at frame 30 onwards (logo complete): 0 of 1,048,576 pixels differ (colour bits). At 3.50 s the draw buffer equals MAME frame 163 (logo fading out) with 0 differing pixels. At 3.75 s the whole VRAM equals MAME frames 169 to 199: the BIOS's "SYSTEM ERROR" screen for a missing card, 0 differing pixels (sim/zn2/system/match_vram.py against a MAME run with VRAM dumps every third frame from 40 to 199). T1 has run its whole course |
| Sub-BIOS | U30 read through gnet_fc and the SDRAM flash port, decrypted to RAM and run from 0x8001xxxx and 0x803Bxxxx |
| Watchdog | control register written C8h/E8h alternately (bit 5 toggles), as MAME; no watchdog reset |
| T2 card path | RF5C296 setup, card attribute (CIS) reads, the unlock key writes, IDENTIFY and every READ SECTORS: all 2,015 bytes written to the RF5C296/ATA and attribute windows up to 5.20 s equal MAME's first 2,015 in order (sim/zn2/system/compare_ata.py); IDENTIFY shows BSY (D0h) then DRQ (58h), as MAME. The BIOS issues 49 READ SECTORS before the second flash erase, as MAME does, and every data port read through the integrated path (8-bit reads for the first 34 commands at 1.0 s, then 16-bit reads) equals the card image: 520,575 of 520,575 reads (sim/zn2/system/check_card_reads.py) |
| T2 CAT702 | 4,387 of 4,387 bytes equal the reference model |

T2, flash copy start: the BIOS's commands to the firmware flash (U30 area,
through gnet_fc and the SDRAM flash port) are MAME's, in order: read ID
(90h at 0x1F000000), three read array writes (FFh at 0x1F050000), then
read status (70h, status 80h), clear status (50h), block erase (20h, D0h)
at 0x1F050000. Status reads return 00h (busy) from 3.6615 s to 4.6617 s
and 80h after, a 1.000 s erase as MAME's (D0h at 2.8627 s, the next 50h
at 3.8627 s; gnet_flash PRESET 1). Before it the BIOS issues 7 READ SECTORS (3.653 to 3.660 s; MAME at
2.8 s). After it the BIOS issues 8 more (255 sectors each, the last 170,
as MAME) and erases the block at 0x1F060000 (core 5.1803 s, MAME
3.9926 s), where I stopped the run. This is the start of the first-boot
copy; programming was not reached in simulation (MAME's first program
word follows the erases, and the whole copy takes MAME 137 s).
The core lags MAME by about 0.8 s from the BIOS's ROM-resident start (see
Timing below) and keeps that lag up to the first erase (second FFh write
1.03 s vs 0.24 s, third 3.65 s vs 2.86 s). The card sector reads after the
first erase take longer than in MAME: 0.52 s for the run of sectors MAME
reads in 0.13 s. Likely cause, not measured (needs-review): every read
goes through the expansion 3 bus with the delay the BIOS programs, the
RF5C296 and the DDR3 card client, and MAME charges no bus wait states. On
hardware this stretches the first-boot copy beyond
MAME's 137 s; how much is open.

T1 and T2 together: from reset with the real BIOS, keys and flash.u30, the
integrated core draws the same frames as MAME (0 differing pixels) through
the G-NET logo to the no-card SYSTEM ERROR screen, and with the Ray Crisis
card starts the first-boot flash copy with MAME's command sequence.

Timing: the CPU-bound BIOS code that runs from ROM (0xBFC0xxxx) takes about
ten times longer than in MAME (MAME's POST write 2 at 3.8 ms, core at
65 ms after the CPU starts; the U30 license header read at 54.5 ms in
MAME, 557 ms after the CPU starts in the core; the header bytes read in
8-bit mode are right: "Li..." from 0x1F000004). The core uses PS1 BIOS ROM timing (8-bit bus
from the programmed delay register, 25 cycles per word in memorymux);
MAME charges no wait states. Once the sub-BIOS runs from RAM the core is
much closer to MAME (logo at MAME frame 15 by core frame 52). Which is
right for a ZN-2 is open (17, question 8; R1).

### 18.4 Still missing before an RBF can be tried on hardware

1. A Quartus fit of GNET_Z1 (section 15): compile errors, ALMs and timing
   are unknown. Points to watch: VHDL instantiating the SystemVerilog
   gnet_fc through a component, the longer read data path in memorymux
   (zn lane mux before ext_data_new), the new DDR3 client.
2. PSX.sv is not simulated as Verilog in this harness: the ioctl loader,
   the SDRAM ch3 mux and the ioctl_wait handshake are covered by a VHDL
   translation (18.5, LOAD_MODE); the inputs and the watchdog stretch are
   not. The full-system Verilator harness (branch fullsys-sim) runs the
   real PSX.sv.
3. MRA behaviour on MiSTer: the `repeat` parts (as my Dooyong MRAs use),
   the DIP switch download on index 254, a 40 MB card image from a zip.
4. Not modelled for the first test: EEPROM save (hps_io ioctl_upload is not
   wired in PSX.sv, so the MRA nvram only loads), card writes (kept in
   DDR3, lost at power off), screen rotation for the vertical games, the
   Zoom (silent apart from the SPU), the ZN-2 CPU rate.
5. The full first-boot flash copy (MAME 137 s of emulated time, longer in
   the core) is beyond the system simulation (about 0.35 to 0.6 ms of
   emulated time per second); the flash command machine and its storage
   were verified by the M2 replay; here the SDRAM flash port is exercised
   by the U30 reads and T2 reaches two block erases with MAME's command
   sequence and erase time, but no program. T2 on hardware is the first full test of it.


### 18.5 First hardware test: ERROR B930, cause and fix

Result (2026-10-05, GNET_Z1 from 4ae0210, my MiSTer): the BIOS, GPU and
video work. With the Shikigami warm-boot MRA, and also with the cold-boot
MRA, the screen shows "CanNotFindProgramRom / ERROR B930" and no install
screen.

What the error is: MAME 0.288 shows the same screen when U30 is erased
(shikigam with an all-FFh firm NVRAM, card present: frame 120 onwards,
sim/oracle/test_u30ff). It comes from the main BIOS (m534002c-60.ic353
string at 0xBE18, "Program ROM not found."): the license header
"Licensed by Sony Computer Entertainment Inc." at 0x1F000004 did not read
back. In the core that read is at 647.7 ms, before any card access, so the
card download and the metadata cannot cause it.

The zip was right: shikigam.flash equals MAME's post-copy NVRAM converted
to little-endian words (firm, zoomprog, wave0 to wave2 each identical;
build_flash.py --check against sim/r18/nv_shikigam), and its first
0x50000 bytes equal flash.u30.

Cause (rtl/gnet/zn2_board.vhd, flash storage process): the flash adapter
sent its SDRAM ch3 reads with the byte enables of the 16-bit lane, 1100
for an odd word. sdram.sv drives ~be[1:0] onto A12:A11 with the column
command (sdram.sv 476, 490), and A12:A11 are DQMH:DQML on the MiSTer SDRAM
board (sdram.sv 88). They keep that value in the next clock (STATE_IDLE_9,
sdram.sv 343, does not change SDRAM_A). An SDR SDRAM masks read data two
clocks after DQM (standard SDR SDRAM behaviour; the module's data sheet page is
needs-review), so with burst 2 and CAS latency 2 both words of an odd-word
read were masked and the bus was not driven. Even words (DQM 00) read
correctly. In 8-bit mode the BIOS reads "Li" (even word) right and "ce"
(odd word) as noise. Upstream PSX never reads ch3 with partial byte
enables (cheat reads use 1111, downloads are writes), and the simulation
chip model ignored DQM on reads, so the system runs passed.

Fix (commit 13b6e1d): reads use byte enables 1111 (the adapter picks the
lane itself); writes keep 1100/0011 (write DQM has no latency). Needs a
refit of GNET_Z1. Other read paths: zn2_cardmem reads DDR3 with BE FFh
(no DQM on the Avalon port), the EEPROM and mailbox are block RAM, and the
flash erase engine and program read-modify-write use the same adapter.

Simulation changes (sim/zn2/system):
- the SDRAM chip model applies read DQM with a latency of 2 (masked bytes
  read E7h; generic READ_DQM, default on);
- LOAD_MODE = 1 replaces the preloading by the MRA's downloads through a
  VHDL translation of PSX.sv's loader logic (PSX.sv 532-554, 573-592,
  659-683, reset 1003-1006, ch3 mux 1488-1495) and an hps_io/sys_top
  model (one word per ioctl_wr, next word only with ioctl_wait low);
  FLASH_SKIP and CARD_SKIP bytes are downloaded, the rest preloaded, and
  SDRAM and DDR3 are compared with the files when the downloads end. It is
  a translation, not the Verilog; the full-system Verilator harness
  (branch fullsys-sim) runs the real PSX.sv.

Results with the read DQM model:

| Run | Result |
|---|---|
| T1 before the fix (6d8e332) | the header read returns 694Ch ("Li") for the even word and E7E7h for the odd word; the BIOS retries, writes POST 0Fh at 648.8 ms and stops: B930 reproduced |
| T1 after the fix | header "Licensed..." read correctly, sub-BIOS runs; to 1.13 s the bus accesses (108,931), SIO bytes and GPU writes are identical to the earlier T1 run that matched MAME to the SYSTEM ERROR screen; CAT702 4,387 bytes equal the model; the draw buffer at 1.00 s equals MAME frame 15 |
| T2 after the fix | to 1.23 s: bus, SIO and GPU logs identical to the earlier T2 run; 1,925 card writes equal MAME's; 34 READ SECTORS, 17,408 of 17,408 reads equal the card image |
| T3, Shikigami warm boot through LOAD_MODE = 1 | downloads index 0 (524,288 bytes), 2, 3 (first 1 MB of shikigam.flash from the test zip), 4 (meta, equal to the zip's), 5 (first 1 MB of the card image): SDRAM BIOS 262,144 words, flash 524,288 words and DDR3 card 131,072 lines all equal to the files. Then, to 1.85 s (stopped; the Verilator harness ran this boot much further): the header reads "Licensed..." at 1,051 ms; 34 READ SECTORS, 17,408 of 17,408 reads equal the card image (the first 1 MB came through zn2_cardmem's download path); the first 386 card writes, 425 GPU writes (apart from the extra E1h) and 4,387 CAT702 bytes equal MAME's shikigam warm run (sim/oracle/shikigam_warm20) |
