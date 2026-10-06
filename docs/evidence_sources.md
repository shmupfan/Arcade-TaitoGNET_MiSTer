# Evidence sources, ranked per chip

Framework: shmupfan ACCURACY.md
(https://github.com/shmupfan/.github/blob/main/ACCURACY.md). Ranks: 1 real-board
measurements; 2 die-level models of decapped chips; 3 manufacturer
documents (schematics, datasheets, manuals; a second reader for any reading
that changes the design); 4 real boards observed (PCB footage, 60 fps
preferred; PCB audio); 5 MAME (frame-by-frame oracle; its TODOs mark
guesses); 6 other cores and emulators (reference only). Higher wins on
conflict. With nothing above MAME, the core follows MAME and an R item
names the closing evidence.

Library: my local datasheet library (not in this repository), each file
listed with its URL and md5, section "Third pass (2026-10-04): Taito
G-NET". Checked 2026-10-04; nothing below was invented: "none
found" means searched and not found.

G-NET specific point: the PS1 chips (CPU, GPU, SPU) also exist in the
retail PlayStation, so tests run on retail hardware are rank 1 evidence for
their shared behaviour (not for ZN-2 clocks or the 2 MB VRAM variant).
JaCzekanski/ps1-tests (MIT, "for emulator development and hardware
verification") is the main suite; which tests carry results recorded on
real hardware is needs-review per test.

## 1. ZN-2 main board

| Chip | Rank 1 (board measurements) | Rank 2 (die-level) | Rank 3 (manufacturer docs, in library) | Rank 4 (PCB observed) | Rank 5 (MAME 0.288) | Rank 6 |
|---|---|---|---|---|---|---|
| CXD8661R CPU, GTE, MDEC | None for ZN-2. PS1 (CXD8530) results from ps1-tests and similar suites on retail hardware cover the shared core | emu-russia/psxcpu: CXD8530CQ (PS1) reverse engineering from die photos, CC0, unfinished; "slightly modified LSI CW33300 core". Nothing for the CXD8661R. Zeptobars CXD8530CQ die shot | r3000/: LSI CW33000 User's Manual (1992), IDT R3000A/R3051 Product Information (1991), IDT R3051/R3052 Hardware User's Manual (1992, pipeline, caches, bus timing), IDT R30xx Software Reference Manual. No Sony CXD8661R document found | Slowdown in PCB footage (section 3) is the only window on the ZN-2 CPU rate (R1, R23) | `devices/cpu/psx/psx.cpp` (CXD8661R = psxcpu at clock/4), `gte.cpp`, `mdec.cpp`, `dma.cpp`, `rcnt.cpp`, `irq.cpp`, `sio.cpp`; zn.cpp | PSX_MiSTer; XelaNotPu ZN2-Capcom; DuckStation and nocash psx-spx (community spec, links only) |
| CXD8654Q GPU, 2 MB SGRAM | PS1 GPU tests on retail hardware (ps1-tests gpu/*) for the shared rasteriser | None found (siliconpr0n unreadable behind Cloudflare: needs-review) | Sony documents on psx.arthus.net (gpu_command.pdf, service manuals; links only) | Frame captures of PCB footage | `devices/video/psx.cpp` (CXD8654Q = SGRAM type, n_gputype 2) | PSX_MiSTer `gpu*.vhd`; XelaNotPu 2 MB VRAM |
| CXD2925Q SPU | PS1 SPU tests | None found | nocash psx-spx (community) | PCB audio | `devices/sound/spu.cpp`; zn.cpp TODO on CPU vs SPU clock (R2) | PSX_MiSTer `spu*.vhd` |
| CAT702 TT10 | None | None | None (MAME pinout notes only) | | `devices/machine/cat702.cpp` (algorithm reverse-engineered, keys `tt10.ic652`, `tt16.u17`) | XelaNotPu `cat702.vhd` |
| uPD78081 (znmcu) | None; ROM NO_DUMP | None | upd78081/ uPD78083 subseries user's manual U12176EJ2V0UM00 (Renesas; covers uPD78081/78082). Low value without the ROM | | `src/mame/sony/znmcu.cpp` (behavioural) | XelaNotPu `znmcu.vhd` |
| AT28C16 | | | misc_gnet/AT28C16_Microchip_doc0540.pdf (write cycle timing, data polling) | | `devices/machine/at28c16.cpp` | XelaNotPu |
| EPM7064 CPLD | None | None | None | | zn.cpp map (0x1fa51c00, 0x1fa60000 TODO) | |
| Video timing | MAME notes: 59.8260 Hz, 15.4333 kHz (a measured value recorded in taitogn.cpp; who measured it is not stated) | | | 60 fps PCB captures | psx.cpp GPU timing | |

## 2. FC PCB

| Chip | Rank 1 | Rank 2 | Rank 3 (in library unless noted) | Rank 4 | Rank 5 (MAME 0.288) | Rank 6 |
|---|---|---|---|---|---|---|
| MN1020012A (MN10200) | None | None | mn10200/MN102H60G LSI User's Manual 22360-014E (CPU core, bus, interrupts, timers, instruction set with execution cycles; MN102H member of the family); mn10200/MN102L Instruction Manual 12250-030E. No MN1020012A-specific document. Known erratum: manuals give the wrong operand order for MOVB Dm,(An) (Pokechu22/ghidra-mn102-lang) | | `devices/cpu/mn10200/mn10200.cpp` (runs at clock/2) | XelaNotPu `mn10200.sv` (literal MAME port) |
| ZSG-2 | None | None | None anywhere (no datasheet; searched web, archive.org, aggregators) | PCB audio is the only evidence above MAME (R10, R26) | `devices/sound/zsg2.cpp` (reverse-engineered by Galibert, Belmont, hap, superctr; TODOs: filter and ramping, clicks in gdarius/raystorm, out-of-range reads). Post-0.288 fix 61c7940 (13-bit volume readback, Shikigami) | XelaNotPu `zsg2.sv` (MAME 0.277 behaviour, bit-exact vs MAME) |
| TMS57002 DASP | None | Die photos only (experimental-engineering.co.uk, 2016; die marked TMS67002; no netlist) | tms57002/TMS57002 User's Guide (TI, 1992, 143 pages): PMEM 256 x 24, DMEM0 256 x 24, DMEM1 32 x 24, CMEM, byte host download, serial ports with 16 or 24-bit word select, external delay RAM interface, instruction set. Settles or narrows R8 and R11 at M0 | | `devices/cpu/tms57002/*` (Galibert), taito_zm.cpp TODO on input scaling | XelaNotPu `tms57002.sv`; ppriest `gx_tms57002.sv` (Konami GX core) |
| ZFX-2 (later boards) | None | None | None. MAME taito_zm.cpp: "functionally identical"; a bannister.org MAME forum thread calls it an undocumented TMS57070 variant (needs-review, R9) | Board photos | | |
| LC321664 delay DRAM, LH52B256 SRAM | | | misc_gnet/ (Sanyo EN4795C: LC321664 is 64K x 16 fast page mode with byte write, not EDO; Sharp LH52B256 32K x 8 SRAM) | Board photos (R7, R8; exact LC321664 suffix needs-review) | taito_zm.cpp maps 256 KB and 128 KB | XelaNotPu 64 KB each |
| M66220FP mailbox | | | m66220/ (Mitsubishi 1990 Digital ASSP data book, bitsavers; M66220SP/FP pages 129 to 134 extracted): pinout, collision arbitration, Not Ready output, cycle timing | | taito_zm.cpp shared RAM | XelaNotPu |
| Intel TE28F160 (U30, U29, U55, U56) | | | intel_flash/28F160S3_28F320S3_290608-005 and 28F160S5_28F320S5_290609-004 (Intel, Dec 1998, Wayback copies of developer.intel.com): ID B0h/D0h (Table 12 p24), status register (Table 15 p30), program/erase timing (S3 p50, S5 p49). Settles R3 timing up to which part (S3 or S5) and VPP the board uses | PCB footage of a first boot (2 to 3 minutes per MAME notes) | `devices/machine/intelfsh.cpp` (no program/erase timing) | |
| Intel E28F400B (U27) | | | intel_flash/28F400B5 Smart 5 Boot Block datasheet 290599-004 (exact B-suffix family on the board needs-review) | | intelfsh.cpp INTEL_E28F400B | |
| RF5C296 | | | rf5c296/Ricoh RF5C296/RF5C396L Application Manual EA-028-9804 (i82365SL B-step compatible registers at 3E0h/3E1h, matching MAME) | | `devices/machine/rf5c296.cpp` ("very inaccurate ... hardcodes the gnet config") | |
| PC card (ATA) and Taito locks | None | None | pccard_ata/CF+ and CompactFlash Specification Rev 1.4 (1999) and Rev 3.0 (2004): attribute memory, CIS, ATA task file and commands. The Taito unlock is not documented anywhere | Load times in PCB footage (R6) | `devices/bus/pccard/ataflash.cpp` (taito_pccard1/2, taito_cf) | Main_MiSTer ide.cpp (generic ATA) |
| MB3773 watchdog | | | misc_gnet/MB3773 Fujitsu DS04-27401-7E (watchdog period from external C) | | `devices/machine/mb3773.cpp` | |
| MB87078 volume | | | mb87078/ (Fujitsu Edition 2.0A, 1992): 0.5 dB steps, 0 to -32 dB or mute, cascade to -64 dB, 6-bit interface, truth table p5 (R12) | PCB audio | not emulated | |
| XC95108 CPLD E65-01 | None | None | None | | taitogn.cpp control registers (R15) | |

## 3. PCB footage (rank 4 candidates, not downloaded)

Capture method unverified unless the title says PCB. No video downloads
without asking Lee.

| Game | Title / channel | URL | Note |
|---|---|---|---|
| Shikigami no Shiro | "Shikigami No Shiro G-NET Arcade PCB Gameplay", The Obsolete Geek | https://www.youtube.com/watch?v=V2F-Mld4ONc | PCB stated in title |
| Ray Crisis | "TAITO G NET Arcade Board with Ray Crisis", westtrade | https://www.youtube.com/watch?v=zIpQM4xNWdY | Board shown |
| Ray Crisis | Gamers Bay | https://www.youtube.com/watch?v=A_gQx5IWtVg | needs-review |
| Night Raid | Gamers Bay | https://www.youtube.com/watch?v=j13Liu8hmiY | needs-review |
| XII Stag | Martinoz | https://www.youtube.com/watch?v=DX07upvVHFI | source unknown |
| XII Stag | Vysethedetermined2 | https://www.youtube.com/watch?v=mNkIbSesdSI | source unknown |
| Psyvariar -Revision- | HIDEFACES | https://www.youtube.com/watch?v=u57ca4IcWwY | source unknown |
| Psyvariar | Batocera Retrobat Arcade Games | https://www.youtube.com/watch?v=DdgcjF4E3WQ | probably emulation, not usable |

Wanted: 60 fps direct captures of known heavy scenes (slowdown, R23), a
first boot with a new card (flash copy, R3), load screens (R6), and
line-out audio (R10, R12, R13, R26). The shmups forum thread "I measured
some input lag on original PCBs" (t=71343) may include G-NET games; it
returned 403 (needs-review).

## 4. MAME files (0.288 tag, 2c38dc6e)

`src/mame/sony/taitogn.cpp`, `zn.cpp`, `zn.h`, `taito_zm.cpp`,
`znmcu.cpp`; `src/devices/cpu/psx/*`; `src/devices/video/psx.cpp`;
`src/devices/sound/spu.cpp`, `zsg2.cpp`; `src/devices/cpu/mn10200/*`;
`src/devices/cpu/tms57002/*`; `src/devices/machine/cat702.cpp`,
`rf5c296.cpp`, `intelfsh.cpp`, `mb3773.cpp`, `at28c16.cpp`;
`src/devices/bus/pccard/ataflash.cpp`, `pccard.cpp`. Licence BSD-3-Clause
(taitogn.cpp). Post-0.288 commit to watch: 61c7940 (zsg2.cpp).

## 5. Which R items each source can settle (first reading, M0 to confirm)

| R item | Best available source |
|---|---|
| R1, R23 CPU rate | PCB footage slowdown counts (rank 4); no rank 1-3 source found |
| R3 flash copy | MAME trace for behaviour; 28F160S3 datasheet (missing) and 28F400B5 datasheet for timing |
| R4 RF5C296 | Ricoh application manual (rank 3) |
| R5, R25 card | CF specification (rank 3) for the ATA side; MAME for the Taito lock |
| R7, R8 RAM sizes | Board photos; TMS57002 guide (external RAM interface) |
| R9 ZFX-2 | Board photos |
| R10, R26 ZSG-2 | PCB audio only |
| R11 TMS57002 input format | TMS57002 guide (16/24-bit word select) |
| R12, R13 levels | MB87078 datasheet (to fetch); PCB line-out recordings |
| R17 watchdog | MB3773 datasheet |
