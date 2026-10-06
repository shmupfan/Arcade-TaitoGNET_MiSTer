# Board evidence: open items and public sources

Compiled 2026-10-05. Scope: every open board-level item in docs/*.md on
main and in the branch docs zn2-layer:docs/zn2_layer_design.md (1240a40),
mn10200-rtl:docs/mn10200_rtl.md, zsg2-rtl:docs/zsg2_rtl.md,
tms57002-rtl:docs/tms57002_rtl.md, r1-cdc, r1-cpu50, r1-clk-ratio and
m2-glue-polish:docs/gnet_minimum_standard.md (7d17302). FPGA-internal items
(fit, timing, CDC, harness) are left out. Line numbers are as of this date.

Evidence ranks follow docs/evidence_sources.md: a photo or document of a
real board outranks MAME, and MAME outranks other emulators. No image or
document was copied into the repository; sources are cited by URL. Web
access was read-only, one request at a time per site.

Status key: **settled** (a rank 3 or 4 source answers it), **partly** (the
source narrows it), **open** (nothing found).

## 1. Sources found

| ID | Source | URL | What it shows | Rank |
|---|---|---|---|---|
| S1 | Taito "TAITO G NET Instruction Manual", G2500879A (operator manual for the mother board) | https://archive.org/details/arcademanual_Taito_G_Net (also https://www.arcade-museum.com/manuals-videogames/T/Taito-G-Net.pdf) | p.13: DIP switch drawing, "Operate No. 4 only" to enter test mode; game details deferred to each G card manual. p.11: board drawing with DIP switch, volume dial, stereo/mono switch. p.12: JAMMA pinout, 3 buttons per player (PUSH1 to PUSH3). p.13: 6-pin video connector carries Fsc 3.58 MHz on pin 6. Stereo/mono switch ships set to mono. p.15: 5 V 4 A, 12 V 2 A, about 30 W | 3 (manufacturer document) |
| S2 | System 16, Taito G-NET page, "PCB Pictures (large)": FC PCB top `boards/gnet_1st.jpg`, FC PCB underside `boards/gnet_1st_under.jpg`, ZN-2 `boards/gnet_2nd.jpg`, stack `boards/gnet_top.jpg` (2048 x 1536 each; the images load only from the page, direct links return 403) | https://www.system16.com/hardware.php?id=672 | Readable part markings, listed in section 2. The page text gives the CPU as "50MHz?" (question mark theirs) | 4 (real board photo) for markings; text is rank 6 |
| S3 | arcade-projects thread "Taito G-NET flash problems ... (updated with motherboard jumpers!)", photo by bytestorm, 2019-05-04 (1594 x 897) | https://www.arcade-projects.com/threads/taito-g-net-flash-problems-cannotfindprogramrom-error-b930-updated-with-motherboard-jumpers.9151/ ; photo https://www.arcade-projects.com/attachments/20190504_101751-jpg.19823/ | FC PCB with JP1 to JP4 labelled: JP1 2-pin header beside U30 and test point INT; JP4 beside TP9 and the XC95108 (U64); JP2 and JP3 near Q1 and D1. U30 silkscreen "LH28F160SK-10". U1 MB87078 beside U2/U3 NJM2100. U17 CAT702 "TT16". Thread: MoppelTheWhale (2019-05-06) runs "JP1 bridged only for update, JP2 bridged, JP3 open, JP4 bridged" | 4 |
| S4 | arcade-projects thread "Purpose of the back up pcb on a Taito g-net?", post by ack, 2023-08-02 | https://www.arcade-projects.com/threads/purpose-of-the-back-up-pcb-on-a-taito-g-net.15093/ (page 2) | Continuity trace of the Save/Backup PCB 6-pin connector: pin 1 to XC95108 (U64) pin 92; pin 5 to MB3771 pin 7 and ADM708AR (U5) pin 1; pin 6 to MB3771 pin 8, JP3, 74HC132 (U40), 74HC14 (U6) and XC95108 (U64) pin 27. MB3771 pin 8 pulses low at power-off | 4 (owner trace), single observer |
| S5 | arcade-projects thread "Taito G-NET Erase Error on updating", 2024 | https://www.arcade-projects.com/threads/taito-g-net-erase-error-on-updating.30958/ | Tailsnic Retroworks (2024-08-06): JP1 "Tracing the pin goes to U30 for enabling erase mode". Same poster (2024-08-08): Sharp LH28F160S5T-L70A works as a U30 replacement | 4/community, not photographed |
| S6 | bannister.org MAME forum, "ZOOM ZFX-2 sound chip support", 2020-12 to 2021-08 | https://forums.bannister.org/ubbthreads.php?ubb=printthread&Board=1&main=9160&type=thread | Prehistoricman: ZFX-2 is a TMS57070 variant, used on Taito Type Zero and Power-JC. R. Belmont: the ZFX-2 host is an MN1020819 with mask ROM. Prehistoricman compares the Type Zero ZFX-2 program with Chaos Heat's (G-NET) TMS57002 program: same structure, TTZ adds master volume. No G-NET board with a ZFX-2 is mentioned | 6 (community), relevant to R9 |
| S7 | MAME git after the 0.288 tag (GitHub API, mamedev/mame, read 2026-10-05) | https://github.com/mamedev/mame/commit/aab5dcadb ; https://github.com/mamedev/mame/commit/61c794064 ; https://github.com/mamedev/mame/commit/4f44364b2 ; https://github.com/mamedev/mame/commit/f11e04e31 | aab5dcadb (smf, SPU rework): zn.cpp now clocks the CXD8654Q GPU from `100_MHz_XTAL / 2` on ZN-2 (ZN-1: 67.7376 MHz / 2) with the 53.693175 MHz crystal as `set_vclkn` ("pin 192 on SGRAM GPU", video/psx.h); SPU still 67.7376 MHz / 2; psx.cpp RAM_SIZE nibble 3 ("zn2/namco system 12") is now a 4 MB window, was 8 MB; boardconfig bit 2 = SPU RAM above 512 KB, bit 3 = GPU RAM above 1 MB. 61c794064: ZSG-2 register 0xB readback 13 bits (already in R26). 4f44364b2: ATA and RF5C296 bus cleanup, removes the 8-bit CF hack in ataflash. f11e04e31: API rename only. taitogn.cpp header notes, the 0x1fa60000 hack (zn.cpp master line 184-186) and taito_zm.cpp are unchanged; no commit touches tms57002 or mn10200 since 2025 | 5 |
| S8 | newastrocity, "Taito G-Net System" (2012) | https://newastrocity.wordpress.com/2012/11/29/taito-g-net-system/ | Board list with Taito part numbers: FC PCB K91X0721A, CD PCB J9100483A, communication PCB K91X0762A/J9100502A, Back Up PCB J9100484A. Photos are 525 px wide (too small for markings). MAME notes say K91X0721B | 6 |
| S9 | Intel 28F160S5 datasheet 290609-004 and 28F400B5 datasheet 290599-004 (in library, datasheets/intel_flash/) | local | 290609-004 section 7.0 p.50 lists TE28F160S5-70 and TE28F160S5-100; front page "5 V VPP"; pin table: BYTE# selects x8 (low) or x16 (high). 290599-004 section 6.0 p.35 lists E28F400B5B80 (B = bottom boot, 80 ns) | 3 |
| S10 | YouTube "PSYVARIAR - MEDIUM UNIT (ARCADE - FULL GAME)", uploaded 2017-10-05, 980 s, published at 25 fps (480p) | https://www.youtube.com/watch?v=jG1nJSsQU_o | Not a G-NET board. The uploader's description says the game is "played on the PS2" (the 2003 PS2 release) and, for this upload, "PS2 emulation". So it shows the PS2 port in a PS2 emulator, at 25 fps (a PAL-rate chain), not the arcade PCB. Lee noted (2026-10-06) that its WARNING and BUZZ graphics look like the core's and that its sound effects are quiet against the music; that agrees with the core's output but cannot confirm the PCB, because the port, its mixing and the emulator all differ from the arcade board. Not usable for boot timing (PS2 boot, different hardware, 25 fps) | 6 (port under emulation; not evidence for the PCB) |
| S11 | YouTube "psyvariar revision arcade taito g-net", uploaded 2020-10-16, 161 s, 30 fps (up to 1080p), portrait, no description | https://www.youtube.com/watch?v=9z-gvMGvyZY | A phone filming a vertical CRT in an arcade cabinet (lit marquee, control panel with red buttons), so real hardware; the board is not shown and "taito g-net" is the uploader's title, but Psyvariar -Revision- exists only on G-NET (psyvarrv). Downloaded on 2026-10-06 (1080x1920, 48 kHz audio; kept in the gitignored sim/oracle/pcb_video/). Content: the end of an attract demo (0 to 32 s, the city stage that is MAME's second psyvarrv demo), the silent TOP PSYVARIARS ranking (two pages), the story screens, the title, then a coin at about 85.6 s and a replay-mode game to 160 s; no power-on, no loader, no WARNING. BUZZ labels: an outlined digit plus "BUZZ" after a few frames of streaks, LEVEL and BUZZ overlapping, the same family of look as the core on my hardware. Attract timing against MAME 0.288 psyvarrv (per-frame screen brightness from both, audio aligned on the demo): fixed-length screens match to within a camera frame (each ranking page 10.96 s; the three story cuts around "Galactic Unified Intelligence System" are 24 frames each with 6-frame gaps on both), so the board's frame rate matches MAME's 59.83 Hz to about 0.3%. The board is later than MAME only across the two loading points: 0.15 s at demo to ranking and a further 0.16 s at ranking to story (0.31 s in all, constant from there to the title). Effects against music (demo audio, PCB band power fitted as Zoom plus k times SPU, with MAME's SPU = full mix minus a Zoom-only run): the effects are 3.8 dB louder against the music than in MAME at 1.2 to 4.8 kHz (90% block-bootstrap range 2.2 to 6.1 dB) and 5.7 dB at 2.4 to 4.8 kHz, the best-fitting band (4.7 to 7.2 dB), an SPU-to-Zoom ratio of about 0.47 to 0.58 against MAME's 0.3 (M5). The fit explains 65 to 72% of the variance in those bands; below 1.2 kHz the room noise dominates | 4 (real board in a cabinet, phone camera and microphone, unknown volume dial and mono/stereo setting) |

Searched without a usable result: system16 text beyond the photos;
KLOV thread https://forums.arcade-museum.com/threads/taito-g-net-a-message-to-fellow-klovers.545709/
(no hardware detail); arcade-projects thread 4045 (Save PCB photos, no FC
detail); ikotsu.blogspot.com BIOS flashing posts (procedure only, "a couple
of minutes"); arcade-history Night Raid page (3 buttons, no orientation);
eBay listings (sold, photos gone); Wikipedia System 12 ("48 MHz", no
citation). shmups.system11.org returned 403 to the fetch tool (threads
t=42957 and the input-lag thread t=71343 still unread). Cloudflare on
arcade-projects and system16 cleared on its own in a normal browser; no
CAPTCHA was solved.

## 2. Readings from the photos (S2, S3)

FC PCB top (S2 gnet_1st.jpg):
- U30, U29, U56, U55: Intel "TE28F160 / S5100" (U30 and U29 read under
  zoom; U56 and U55 carry the same layout of marking). Silkscreen under
  each: "LH28F160SK-10" (an alternative Sharp footprint).
- U27: Intel "E28F400 / B5B80": 28F400B5, bottom boot, 80 ns (S9).
- U26: empty DIP40 socket, silkscreen "AM27C800-120PC".
- U11: empty DIP24 position, silkscreen "FM1208-200CC" (MAME notes:
  "Unpopulated position for FM1208", [MAME 0.288 taitogn.cpp:118](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L118)).
- U45 Mitsubishi M66220FP; U10 Sharp LH52B256N-10LL (32K x 8).
- U64 Xilinx XC95108 PQ100, "15C", label "E65-01"; U17 CAT702 "TT16".
- U1 Fujitsu MB87078 (SOP24) beside U2/U3 NJM2100M.
- U7 TI TMS57002DPHA (QFP80, pin 1 and pin 80 at the lower left corner).
- U42 silkscreen "MN1020012A" (chip marking not legible).
- OSC1 25 MHz. SW1: an empty 4-pad switch footprint below U42.
- JP1 beside U30 and test point INT; JP4 beside TP9 and U64.

FC PCB underside (S2 gnet_1st_under.jpg):
- U39 Sanyo LC321664AM-80 (silkscreen "LC321664 AM-80").
- U43 Fujitsu MB3773PF; U5 ADM708AR; U4 NEC uPD6379GR; U50 Ricoh RF5C296.
- U24: empty 24-pin footprint, silkscreen "ADM238LJR" (an RS-232 line
  driver/receiver, not fitted).
- A 6-pin connector marked "P" (the Save/Backup PCB connector of S4).
- Around U43 and U5 (viewed again 2026-10-05): U5 ADM708AR (SOIC-8,
  rotated 90 degrees) sits directly below U43 MB3773PF, with a cluster of
  vias between them next to C101 (chip capacitor, no value marking), R35
  and R36. A jumper-resistor position JPR2 is fitted beside R40, just
  below U5. C8, a tantalum marked "10 16V" (10 uF, 16 V), sits between U4
  (uPD6379GR) and U43; its net is not visible. U43's second marking line
  is not legible. No trace between U43, U5 and the board edge can be
  followed through the vias.

ZN-2 (S2 gnet_2nd.jpg):
- Sony CXD8661R and CXD8654Q; Altera EPM7064 (QFP100, speed suffix not
  legible); IC051 and IC052 fitted with SEC KM416V1204 parts, IC053 and
  IC054 empty; blue 4-way DIP switch at S551; label "COH-3002T".
- IC356 (Atmel, SOP) is the AT28C16 position; the suffix is not legible
  at this resolution. Crystal X001 beside the CPU is not legible.

## 3. Items grouped by what settles them

### 3.1 PCB inspection (photos, markings, traces)

| # | Item | Where raised | Status | Evidence and what is left |
|---|---|---|---|---|
| P1 | Wave and sub-BIOS flash part (S3 or S5) and VPP, which set the first-boot copy time (R3) | docs/m0_findings.md:79-81, docs/gnet_glue_design.md:66-68, docs/m2_glue_findings.md:117, docs/evidence_sources.md:48 | **settled (part)**, copy time open | S2: "TE28F160 S5100" on U30 and U29 = 28F160S5-100 (S9, 290609-004 p.50), a 5 V VPP part. The m0_findings inference (S3 at low VPP) does not hold: the flash-only estimate is the S5 row, 77.5 s (docs/m0_findings.md:72-77). MAME's "2-3 minutes" ([MAME 0.288 taitogn.cpp:20-21](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L20-L21)) then needs about 40 to 100 s from card reads and the verify pass seen as the third progress bar (ikotsu blog); PCB footage of a first boot measures it (M6) |
| P2 | U30 in x8 or x16 mode on the 8-bit expansion bus | zn2-layer:docs/zn2_layer_design.md:160-170 | **partly** | The fitted part is a 28F160S5, which has BYTE# (S9 pin table). Which level BYTE# (TSOP56 pin) sees on the FC PCB needs a close-up or a continuity check |
| P3 | U27 family and boot block | docs/evidence_sources.md:49 | **settled** | S2: E28F400B5B80, bottom boot, matching MAME's INTEL_E28F400B. A community post calling it "28F004" (S5, 2024-09-02) is superseded by the photo |
| P4 | LC321664 exact part | docs/evidence_sources.md:46; [MAME 0.288 taitogn.cpp:111](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L111) ("EDO DRAM") | **settled** | S2 underside: LC321664AM-80; the library sheet is the LC321664AM (fast page mode, docs/hardware_inventory.md). R8 width was already answered (docs/PLAN.md:184) |
| P5 | MN10200 work RAM size (R7) and mirroring (O8) | docs/PLAN.md:183, docs/mn10200_design.md:682 | **partly** | S2: one LH52B256N-10LL (32 KB) at U10, so 32 KB is fitted. Mirroring is decided inside the XC95108 (E65-01) and stays open |
| P6 | AT28C16 suffix (1 ms or 200 us write) | zn2-layer:docs/zn2_layer_design.md:262-269, 650 | **open** | S2 IC356 not legible. Needs a close-up of IC356 |
| P7 | MB87078: what drives DSEL, which signals channels 0 and 1 attenuate, channels 2 and 3 use (R12, Z10) | docs/zoom_zsg2_tms57002_design.md:31-41, 166-181, 870; docs/PLAN.md:188 | **open** | U1 located (S2, S3) next to the NJM2100 output op-amps, which suggests it sits in the Zoom output path, but no trace is followable in either photo. Needs close-ups of both sides around U1, or a continuity check from U1 DSEL to U64 or to an address line |
| P8 | TMS57002 CLKSEL (pin 10) strap and SYNC (pin 80) source (Z8) | docs/zoom_zsg2_tms57002_design.md:134-137, 868 | **open** | U7 located; pins 1 to 10 and 80 are at its lower left corner (S2). Needs a close-up or continuity check: pin 10 to VCC or GND, pin 80 to which net |
| P9 | MN10200 port 1 bits 2, 4, 5 (Z16) and port 3 bit 0 (O5) | docs/zoom_zsg2_tms57002_design.md:151, 876; docs/mn10200_design.md:679 | **open** | Lead: the empty SW1 footprint below U42 (S2) could be a strap or button on an MN10200 port pin. Needs a continuity check from the U42 port pins |
| P10 | MN10200 serial 0 receive pin (O6) | docs/mn10200_design.md:680 | **partly** | S2 underside: the U24 ADM238LJR RS-232 transceiver is not fitted, which fits a development-only serial port. Needs a trace from U42's serial pins to U24 to confirm |
| P11 | ZN-2 0x1fa51c00 / 0x1fa60000 register behind the EPM7064 (R2) | docs/PLAN.md:178; zn2-layer:docs/zn2_layer_design.md:312-334; docs/r1_cpu_domain_design.md:490 | **open** | MAME master keeps the same TODO and toggle (S7). No document. A logic analyser on the EPM7064 while the SPU read routine runs is the only route |
| P12 | 0x1fb70000 returning 2, control2/control3, byte writes to 0x1FB68000 (R15) | docs/PLAN.md:191; zn2-layer:docs/zn2_layer_design.md:126-128 | **open**, one lead | S4: the Save/Backup PCB connector reaches XC95108 pins 92 and 27, and one line is the MB3771 power-fail output. One FC CPLD input is therefore a backup or power-fail status; whether a 0x1fb70000 bit reads it is not known |
| P13 | JP1 function and location (R20) | docs/PLAN.md:196; zn2-layer:docs/zn2_layer_design.md:241 | **settled** | S3 photo: JP1 is the 2-pin header beside U30 on the FC PCB. Closed, the BIOS runs the flasher from the AM27C800 in U26 (S3 thread, ikotsu blog). S5 says it reaches U30 "for enabling erase mode" (not photographed). Matches MAME's JP1 port ([MAME 0.288 taitogn.cpp:911-923](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L911-L923)). JP2 to JP4 relate to the Save PCB (S3, S4); the core does not need them |
| P14 | S551 switch meanings | zn2-layer:docs/zn2_layer_design.md:228-229; m2-glue-polish:docs/gnet_minimum_standard.md:88-96 | **partly** | S1 p.13: "Operate No. 4 only" to enter test mode, so S551:4 = test mode, matching MAME's taitogn port ([MAME 0.288 taitogn.cpp:899-906](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L899-L906), "Test Mode", S551:4). Correction for gnet_minimum_standard.md:91, which lists S551:4 as unknown. S551:1 to 3: the operator manual says not to use them; MAME's generic ZN S551:2 "Service Mode" (taitogn.cpp:861) is not in the manual. Per-game meanings, if any, are in each G card manual (not found) |
| P15 | Later boards: MN1020819DA and ZFX-2 on G-NET (R9, O11, Z12) | docs/PLAN.md:185; docs/mn10200_design.md:685; docs/zoom_zsg2_tms57002_design.md:872 | **partly** | S6 places ZFX-2 with an MN1020819 host on Taito Type Zero and Power-JC; it names no G-NET board with them. Both FC PCBs photographed (S2, S3) are MN1020012A / TMS57002 boards; their game is unknown. Needs FC PCB photos from boards that shipped with late games (XII Stag 2002, Shikigami no Shiro 2001) |
| P16 | FC PCB revision K91X0721A or B | [MAME 0.288 taitogn.cpp:86](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L86) (B); S8 (A) | **open** (minor) | Both exist on paper. A photo of the board number with a known game would place them |
| P17 | MB3773 watchdog period (R17) | docs/PLAN.md:193; docs/gnet_watchdog_mb3773.md | **partly**, bounded | S2 underside locates U43 MB3773PF; the timing capacitor value is not legible (C101 next to the pin-1 via is an unmarked chip capacitor; C8 "10 16V" is nearby on an unknown net). Datasheet DS04-27401-7E: TWD (ms) = about 100 x CT (uF), +-50%, recommended at most 1000 ms (CT at most 10 uF); reset comes TWD to TWD + TWR after the last falling CK edge. Lower bound from the games: Night Raid, Ray Crisis and Shikigami run a 2,500,000-iteration delay loop in their Zoom init with no kick (2.4 to 2.9 s in MAME at 25 MIPS, about 3 s or more on the slower PCB CPU), and the boards boot, so either the period is above about 3 s (CT about 47 uF or more, outside the recommended range) or the MB3773 RESET does not reset the main CPU (P20). Needs the CT value and the RESET and RESET-bar (pins 8 and 2) destinations: owner question 6 |
| P18 | Main RAM population (R21) | docs/PLAN.md:197 | **settled** | S2: IC051/IC052 fitted, IC053/IC054 empty, as MAME notes ([MAME 0.288 taitogn.cpp:57](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp#L57), 80). R21 itself (boardconfig read) was already traced |
| P19 | CPU crystal marking | docs/PLAN.md:177 | **open** | S2 X001 not legible; MAME says 100 MHz. A close-up confirms the crystal, not the internal rate (M1) |
| P20 | What resets the main CPU: U5 ADM708AR and U43 MB3773 outputs | docs/gnet_watchdog_mb3773.md 4 | **open**, partly bounded | ADM708 (Analog Devices ADM705/706/707/708 Rev. H, p.1): supply supervisor without a watchdog (the watchdog is on the ADM705/706 only); 4.40 V threshold, 200 ms reset pulse, debounced TTL/CMOS manual reset input MR-bar, active-high RESET and active-low RESET-bar outputs, 1.25 V power-fail comparator (PFI, PFO-bar); a drop-in upgrade for the MAX705 to MAX708. S4 traces Save/Backup connector pin 5 to MB3771 pin 7 and U5 pin 1; in the MAX708 pinout pin 1 is MR-bar (I could not read the ADM708 pin table page; needs-review), so an external line can force U5's reset. MAME resets the whole machine on a watchdog timeout (mb3773.cpp schedule_soft_reset), a driver assumption. Whether U5 RESET, U43 RESET or neither reaches the ZN-2 CPU reset (through the expansion connector) is not known; a common pairing is the watchdog's RESET-bar into the supervisor's MR-bar (my inference, not seen on this board). JPR2 beside U5 may select a reset source (inference). Needs continuity checks: owner question 12 |

### 3.2 PCB measurement

| # | Item | Where raised | Status | Evidence and what is left |
|---|---|---|---|---|
| M1 | CXD8661R execution rate, cache size, wait states (R1, R23) | docs/PLAN.md:177, 199; docs/r1_speed_study.md:180-198 | **partly** (no change to the 50 MHz decision) | New rank 5 hint: post-0.288 MAME clocks the ZN-2 GPU from 100 MHz / 2 (S7, aab5dcadb), which fits a 50 MHz system clock out of the CPU. System 16 marks 50 MHz with a question mark (S2 text). Settled only by a timing program or a frequency counter on a board |
| M2 | Frame and line rate (R14): 59.826 Hz vs PSX_MiSTer's 3413 x 263; 15.4333 kHz note | docs/PLAN.md:190; docs/m1_gpu_zn2.md:330-341 | **open** | Nothing new. A frequency counter on composite sync (JAMMA P13 or CN503 pin 4, S1 pp.12-13) settles both |
| M3 | SPU clock on ZN-2 (R24) | docs/PLAN.md:200 | **open** | MAME master still uses 67.7376 MHz / 2 (S7) |
| M4 | FC PCB bus waits (O2, zn2 13.2) and MN10200 instruction timing (O3) | docs/mn10200_design.md:676-677; zn2-layer:docs/zn2_layer_design.md:383-384 | **open** | Logic analyser on /RD and /CS, or a loop timing test |
| M5 | Audio: ZSG-2 filter, ramps, attack, send gains, output rounding (R10, Z2 to Z7, Z13, Z15); MB87078 law in practice (R12, Z10); SPU against Zoom balance (R13, Z11); Shikigami intro voices (R26, Z1) | docs/PLAN.md:186, 188, 189, 201; docs/zoom_zsg2_tms57002_design.md:861-875 | **open** | No line-out PCB recording found. S1: the board ships set to mono (S301) and has a volume dial; a recording must note both. Night Raid or Shikigami (gain 0x30) against Ray Crisis (0x3F) checks the MB87078 law. SPU against Zoom: MAME's SPU 0.3 and Zoom 1.0 (taitogn.cpp:442-448) have no measured source. The SPU route was 0.35 in MAME 0.150, 0.45 by 0.200, and became 0.3 in superctr's commit df9d7ef55a (2018-08-19, PR 3868, "taito_zm games: Better default Zoom/SPU balance"), which also raised the TMS57002 output from 0.5 to 1.0 (taito_zm.cpp), so the SPU-to-Zoom ratio went from 0.9 to 0.3. The commit and the PR give no measurement or reference; a judgement by ear. On my hardware test (2026-10-06, gnet_full, Psyvariar) the SPU effects sound too quiet against the Zoom music at MAME's ratio. S11 (a phone recording of a real psyvarrv cabinet's attract demo, 2026-10-06) puts the effects 4 to 6 dB louder against the music than MAME's ratio, an SPU-to-Zoom ratio of about 0.5 (0.39 to 0.69 over the measured range), from one recording with an uncalibrated microphone. The analog mix on the boards (owner question 16) or a line-out recording (question 8) would settle it |
| M6 | First-boot copy duration (R3) | docs/PLAN.md:179 | **partly** | Part settled by P1. A timed video of a first boot gives the remainder Simulation only, for reference (2026-10-06, fullsys a6c50 at 50 MHz, cold start): COMPLETE at 150.02 s (raycris) and 153.21 s (shikigam), against MAME 0.288's last flash program command at 140.61 s and 142.06 s |
| M7 | Card access timing (R6) and Type 1 card relock on a wrong key, attribute register 07h (R5) | docs/PLAN.md:181-182; docs/m2_glue_findings.md:300-321 | **open** | Load-screen footage for R6; R5 needs a card on a logic analyser S11 (2026-10-06): on a real psyvarrv board the attract is 0.15 s slower than MAME 0.288 at demo to ranking and 0.16 s slower at ranking to story, the two loading points, with fixed-length screens equal to MAME's to a camera frame |
| M8 | SIO0 bit timing and root counter clock source | zn2-layer:docs/zn2_layer_design.md:250-256, 646 (open at 254); docs/r1_cpu_domain_design.md:489 | **open** | The R1 timing program covers it |
| M9 | GPU and SPU register access latency | docs/r1_cpu_domain_design.md:491 | **open** | Same test program |
| M10 | ZSG-2 to TMS57002 sample latency L (Zoom item Z18) | zoom-i5:docs/zoom_board_design.md 15.6 | **open**, low priority | MAME runs L = 0 (tms57002.cpp:923-938), which the TMS57002 User's Guide 3.8.1 rules out on hardware; the board model uses L = 1, the documented minimum; a frame pipeline gives L = 2. One sample is about 31 us of overall audio delay, not audible and not visible in a recording without a picture reference, so this only fixes the last undocumented timing in the sound path. Needs a scope trace of the TMS57002 SYNC pin (pin 80, see P8) against LRCKI and the ZSG-2 serial data into SI. If it shows L = 2, the board model needs one more zero in its sample queue (zoom_board.sv `sq`) |
| M11 | GP1(05h) display start written mid-scanout: applied at once (picture splits for one frame) or latched per frame | Psyvariar A/B fullsys against MAME, 2026-10-06 (two full-system runs) | **needs review**, leaning to the core | The core tears for 2 frames at the start of a Psyvariar fade (11.36 s warm boot) when the game misses a frame and flips GP1(05h) 11.2 ms into a scanout; MAME renders each frame at vblank from the registers then in force, so it never tears. The core's per-line readout of the display start (rtl/gpu.vhd:653, 1895; gpu_videoout_async.vhd:601-602) is upstream PSX_MiSTer (167509bd), only widened to 10-bit Y in c71a9914. Mednafen (Beetle PSX master, mednafen/psx/gpu.c, read 2026-10-06) does the same: GP1(05h) sets DisplayFB_YStart at once (lines 1655-1656) and every scanline reads DisplayFB_YStart + DisplayFB_CurYOffset (line 2329). psx-spx's GP1(05h) section does not say. A capture of a real PS1 or ZN board flipping mid-scanout would settle it |

### 3.3 Documents

| # | Item | Status | Notes |
|---|---|---|---|
| D1 | Older MN10200-series manual (O1, O2, O4, O7, O9, O10, O12; docs/mn10200_design.md:675-686) | **open** | Not found this pass |
| D2 | MN1020819DA datasheet (O11) | **open** | Not found; S6 says it has a mask ROM |
| D3 | G card (game) manuals: per-game DIP use, button names (gnet_minimum_standard.md:82), Night Raid orientation (R19, docs/PLAN.md:195) | **open** | S1 is the system manual only and refers to the game manuals. arcade-history lists Night Raid with 3 buttons (Shoot, Wave, Bomb) but no orientation |
| D4 | Sony CXD8661R, CXD8654Q, EPM7064 or XC95108 contents, ZSG-2 | **open** | None found, as in docs/evidence_sources.md |

### 3.4 Community knowledge

| # | Item | Status | Notes |
|---|---|---|---|
| C1 | ZFX-2 identity (docs/evidence_sources.md:45) | **partly** | S6: TMS57070 variant, Type Zero and Power-JC; nothing on G-NET |
| C2 | Save/Backup PCB function (not in MAME) | **open** | S4 traces; S3/S4 owners disagree on its effect. Outside the six-game scope |
| C3 | 0x1FA00000 POST writes (zn2-layer:docs/zn2_layer_design.md:109) | **open** | No source; a board LED or latch would show it |
| C4 | ps1-tests capture method (docs/m1_gpu_zn2.md:255-262) | **open** | Not searched this pass; needs the author's statement |

## 4. Questions for board owners

Text Lee can paste to a forum or send to a collector:

> I'm building a MiSTer core for Taito G-NET and want it to match the real
> hardware. If you own a G-NET (ZN-2 plus the Taito FC PCB), any of these
> would help me. Photos in good light, square on, sharp enough to read
> chip text, are ideal.
>
> 1. FC PCB, both sides, with the game you run noted: I want to know which
>    boards carry the TMS57002 and MN1020012A and whether any late boards
>    (XII Stag, Shikigami no Shiro) have a Zoom ZFX-2 or an MN1020819DA
>    instead. The board number (K91X0721A or K91X0721B) too, please.
> 2. A close-up of the TMS57002 (U7), lower left corner, and a continuity
>    check if you can: is pin 10 tied to 5 V or ground, and where does
>    pin 80 go? That decides the DSP's clock mode and sync source.
> 3. A close-up of the MB87078 (U1) area on both sides, or a continuity
>    check: which pin of the XC95108 (U64) or which address line reaches
>    its DSEL pin, and do its outputs feed the Zoom audio alone or the final
>    mix with the PlayStation sound?
> 4. The empty SW1 footprint under the MN1020012A (U42) and the empty U24
>    (ADM238LJR) on the underside: do the pads connect to MN1020012A pins,
>    and which ones? I'm trying to identify two port inputs and a serial
>    port that the sound program reads.
> 5. On the ZN-2 board: a sharp photo of the AT28C16 EEPROM marking (near
>    the SONY BIOS chip, position IC356), so I can tell the 1 ms part from
>    the 200 us "E" part, and of the crystal next to the CXD8661R.
> 6. Near the MB3773 (U43, underside of the FC PCB): the value of the
>    capacitor on its timing pin (pin 1, CT), which sets the watchdog
>    period. A meter reading of the capacitance is best; a photo of the
>    part works if it is marked. Also: where do U43 pin 8 (RESET) and
>    pin 2 (RESET-bar) go? To U5, to the connector to the main board, or
>    to the MN10200 or the XC95108?
> 7. With a frequency counter or scope: the vertical and horizontal sync
>    rates on the JAMMA sync pin. MAME's notes say 59.8260 Hz and
>    15.4333 kHz, and the second figure does not fit the rest.
> 8. A line-out recording (stereo switch S301 set to stereo, volume dial
>    noted) of the Shikigami no Shiro intro and of Night Raid and Ray
>    Crisis attract demos. I'll match them against MAME to set the Zoom
>    filter and volume levels. A Psyvariar attract or a minute of play is
>    also very useful: its sound effects come from the PlayStation sound
>    chip and its music from the Zoom board, so it shows the balance
>    between the two.
> 9. A timed video, ideally a direct capture, of a first boot after
>    swapping to a different game card, from power-on to the game's first
>    screen. It tells me how long the flash copy and the card reads take.
> 10. If you have the G card instruction manual for any of Ray Crisis,
>     Psyvariar, XII Stag, Shikigami no Shiro or Night Raid, a scan of the
>     test mode and DIP switch pages, and for Night Raid whether the
>     monitor is mounted horizontally or vertically.
>
> 11. On the FC PCB, where the Zoom reset line from the main board
>     (control register bit 4) goes: does it reach only the MN10200 reset
>     pin, or also the ZSG-2 and TMS57002 reset pins? A continuity check
>     from the MN10200 reset pin to the other two chips' reset pins would
>     settle it.
>
> 12. The ADM708AR (U5, next to the MB3773 on the underside): where do
>     its manual reset input and its two reset outputs go (pins 1, 7 and 8
>     if it follows the MAX708 pinout: MR-bar, RESET-bar, RESET), and what is JPR2 beside it (fitted with a 0 ohm part, or
>     something else)? In particular, does either U5 or U43 drive a pin of
>     the connector to the ZN-2 main board, and if so which one? That tells
>     me which chip can reset the main CPU.
> 13. A timed video (or a direct capture with audio) of a normal power-on
>     of Night Raid, Ray Crisis or Shikigami no Shiro, from power-on to the
>     NOTICE screen. All three pause for a few seconds on a dark screen
>     after the loading bar; the length of that pause on a real board tells
>     me the CPU speed in that code and confirms the watchdog does not fire
>     there.
> 14. If you have a scope: the MB3773 CK pin (pin 3) during that pause and
>     during the attract. I expect a falling edge about every two frames
>     in the attract and none for about 3 s in the pause; if the board
>     still does not reset, the timing capacitor or the reset wiring is
>     the reason.
> 15. Low priority, also for a scope: on the FC PCB, while a game plays
>     music, the TMS57002 (U7) SYNC pin (pin 80) together with its LRCKI
>     input and the serial sample data going from the ZSG-2 into the
>     TMS57002. I want to know whether a ZSG-2 sample reaches the DSP
>     program one or two samples after it is made (about 31 us of audio
>     delay either way), the last sound timing I can't find documented.
> 16. The analog audio path: where the PlayStation sound chip's output
>     (on the ZN-2 board) and the Zoom board's DAC output (the TMS57002
>     side, on the FC PCB) are added together before the amplifier. A
>     photo of the resistors at that mixing point with their values (or
>     colour bands), or a schematic, lets me set the effects-to-music
>     balance from the hardware instead of guessing.
>
> I'll credit anything I use in the core's notes.
