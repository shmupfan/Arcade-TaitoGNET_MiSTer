# G-NET set survey (MAME 0.288, all sets)

Status: 2026-10-05. Purpose: list what every G-NET set in MAME 0.288 needs
beyond the six priority games (raycris, psyvaria, psyvarrv, xiistag,
shikigam, nightrai; PLAN.md 2, which also lists psyvarij), so the core plan covers them.

Sources: [MAME 0.288 taitogn.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp) (cited as `gn:<line>`), `zn.cpp`
(`zn:`), `ataflash.cpp` (`af:`), `taito_zm.cpp` (`zm:`), `psxgpu.cpp`
(`gpu:`), and earlier findings in this repository. Only the six priority
games and three clones (raycrisj, psyvarij, shikigama) have CHDs in
`roms/`, so everything about the other 30 sets comes from the driver
source; game-level facts for those sets (GPU modes, DSP programs, MDEC,
card metadata) are open until their CHDs are available. I did not download
any ROM or CHD.

New measurements in this survey (section 4): the three local clones
(card metadata, flash images built from the card, one cold oracle boot
each) and the BIOS v2 EPROM flasher (three short runs of `coh3002t`).
Logs are under `sim/oracle/survey_*` and `sim/flash/`, not committed.

## 1. Summary table

39 game sets plus the two BIOS roots `coh3002t` and `coh1002t` (gn:1349
to 1401, 41 GAME() lines). Column notes:

- Card: MAME slot option from the machine config (gn:376 to 414) and the
  DISK_REGION of each ROM_START. T1 = `taitopccard1` (key written to
  attribute registers 0x280 to 0x288, af:182 to 206), T2 = `taitopccard2`
  (key sent with ATA vendor commands 0xFE and 0xFC, af:257 to 321), CF =
  `taitocf` (key in the task-file registers with ATA command 0x0F, af:353
  to 388), ATA = plain `ataflash`, no lock.
- BIOS/JP1: the EPROM image MAME selects (ROM_DEFAULT_BIOS; v1 when not
  given, gn:1028) and the JP1 default (input `taitogn` 0 at gn:912,
  `taitogn_jp1` 1 at gn:921). The EPROM is only reachable with JP1
  closed (bank 2, gn:502 to 505, gn:540), so with JP1 = 0 the EPROM choice
  has no effect.
- Zoom: `init_nozoom` keeps the MN10200 in reset (gn:416 to 419, 518 to
  535). DSP programs and ZSG-2 use are measured only for local sets.
- Class: driver state class and what it adds (section 2).
- GPU: all ZN-2 sets get a CXD8654Q with 2 MB VRAM (zn:94); `coh1002t`
  gets a CXD8561Q with 2 MB (zn:83). Both are MAME GPU type 2 (gpu:62 to
  69). Modes and upper-VRAM use are measured only for local sets.
- Flags: every game set carries only MACHINE_SUPPORTS_SAVE (gn:1353 to
  1401): MAME marks none imperfect or not working.

| Set | Parent | Game (MAME title, gn line) | Card | BIOS / JP1 | Zoom | Class | Rot | Inputs | GPU (measured) | Local |
|---|---|---|---|---|---|---|---|---|---|---|
| chaoshea | | Chaos Heat V2.09O (1353) | T1 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| chaosheaj | chaoshea | Chaos Heat V2.08J (1354) | T1 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| raycris | | Ray Crisis V2.03O (1355) | T1 | v1 / 0 | yes, DSP A | taitogn | 0 | 2P stick, 3 btn | 320, 512, 640 x 240p; upper VRAM | priority |
| raycrisj | raycris | Ray Crisis V2.03J (1356) | T1 | v1 / 0 | yes, DSP A (same zoomprog) | taitogn | 0 | 2P stick, 3 btn | 320, 512, 640 x 240p | yes (4.1) |
| spuzbobl | | Super Puzzle Bobble V2.05O (1357) | T2 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| spuzboblj | spuzbobl | Super Puzzle Bobble V2.04J (1358) | T2 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| gobyrc | | Go By RC V2.03O (1359) | T2 | v1 / 0 | yes | taitogn | 0 | analog wheel + trigger (znmcu), START1 | not traced | no |
| rcdego | gobyrc | RC De Go V2.03J (1360) | T1 | v1 / 0 | yes | taitogn | 0 | as gobyrc | not traced | no |
| flipmaze | | Flip Maze V2.04J (1361) | T1 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| mawasunda | coh1002t | Mawasunda!! V2.08J (1362) | CF | COH1002T, no EPROM / 0 | yes | mawasunda | 0 | 2 analog handles via znmcu trackball path; lamps, LEDs, "weight" outputs | not traced | no |
| shikigam | | Shikigami no Shiro V2.03J (1363) | T1 | v1 / 0 | yes, DSP A | taitogn | 270 | 2P stick, 3 btn | 320 x 240p; upper VRAM | priority |
| shikigama | (none; own set) | Shikigami no Shiro internal build V1.02J (1364) | T1 | v1 / 0 | yes, DSP A (same zoomprog) | taitogn | 270 | 2P stick, 3 btn | 320 x 240p; upper VRAM | yes (4.1) |
| sianniv | | Space Invaders Anniversary V2.02J (1365) | T1 | v1 / 0 | no | ttgnirq (IRQ hack) | 270 | 2P stick, 3 btn | not traced | no |
| kollon | | Kollon V2.04JA (1366) | T1 | v1 / 0 | yes | ttgnirq (IRQ hack) | 0 | 2P stick, 3 btn | not traced | no |
| kollonc | kollon | Kollon V2.04JC (1367) | CF | v2 / 1 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| otenamih | | Otenami Haiken V2.04J (1370) | T1 | v1 / 0 | no | ttgncl4 | 0 | 2P stick, 3 btn | not traced | no |
| psyvaria | | Psyvariar Medium Unit V2.02O (1371) | T1 | v1 / 0 | yes, DSP A + B | ttgncl4 | 270 | 2P stick, 3 btn | 320 x 240p; upper VRAM | priority |
| psyvarij | psyvaria | Psyvariar Medium Unit V2.04J (1372) | T1 | v1 / 0 | yes, DSP A + B (same zoomprog) | ttgncl4 | 270 | 2P stick, 3 btn | 320 x 240p; upper VRAM | yes (4.1) |
| psyvarrv | | Psyvariar Revision V2.04J (1373) | T1 | v1 / 0 | yes, DSP A + B | ttgncl4 | 270 | 2P stick, 3 btn | 320 x 240p; upper VRAM | priority |
| zokuoten | | Zoku Otenamihaiken V2.05J (1374) | T2 | v1 / 0 | no | ttgncl4 | 0 | 2P stick, 3 btn | not traced | no |
| zokuotena | zokuoten | Zoku Otenamihaiken V2.03J (1375) | T1 | v1 / 0 | no | ttgncl4 | 0 | 2P stick, 3 btn | not traced | no |
| zooo | | Zooo V2.01JA (1376) | T1 | v1 / 0 | no | ttgncl4 | 0 | 2P stick, 3 btn | not traced | no |
| otenamhf | | Otenami Haiken Final V2.07JC (1377) | CF | v2 / 1 | no | ttgncl4 | 0 | 2P stick, 3 btn | not traced | no |
| mahjngoh | | Mahjong Oh V2.06J (1380) | T1 | v1 / 0 | yes | ttgnmp (mahjong panel) | 0 | mahjong matrix 1P, P1 stick kept | not traced | no |
| shanghss | | Shanghai Shoryu Sairin V2.03J (1381) | T1 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| soutenry | | Soutenryu V2.07J (1382) | T1 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| usagi | | Usagi V2.02J (1383) | T2 | v1 / 0 | yes | ttgnmp (mahjong panel) | 0 | mahjong matrix only | not traced | no |
| shangtou | | Shanghai Sangokuhai Tougi 2.01J (1384) | T1 | v1 / 0 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| nightrai | | Night Raid V2.03J (1387) | T1 | v1 / 0 | yes, DSP A | ttgncl4 | 0 | 2P stick, 3 btn | 320 x 240p; upper VRAM | priority |
| otenki | | Otenki Kororin V2.01J (1388) | T1 | v1 / 0 | yes | ttgncl4 | 0 | 2P stick, 3 btn | not traced | no |
| xiistag | | XII Stag V2.01J (1391) | T1 | v1 / 0 | yes, DSP A | taitogn | 270 | 2P stick, 3 btn | 320 x 240p; upper VRAM | priority |
| aerofgtsg | | Aero Fighters Special VER 1.00G, bootleg (1394) | ATA | mb2011 / 1 | no | ttgncl0 | 270 | 2P stick, 2 btn; S551:3 Test, S551:4 Save | not traced | no |
| brvbladeg | | Brave Blade VER 1.40G, bootleg (1395) | ATA | mb2011 / 1 | no | taitogn | 270 | 2P stick, 3 btn | not traced | no |
| flamegung | | Flame Gunner VER 1.40G, bootleg (1396) | ATA | mb2011 / 1 | no | ttgncl0 | 0 | 2P stick, 3 btn | not traced | no |
| ftimpactg | | Fighters' Impact VER 2.10G, bootleg (1397) | ATA | mb2011 / 1 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| gdariusg | | G-Darius VER 2.70G, bootleg (1398) | ATA | mb2011 / 1 | yes | taitogn | 0 | 2P stick, 3 btn | not traced | no |
| raystormg | | Ray Storm VER 2.60G, bootleg (1399) | ATA | mb2011 / 1 | yes | taitogn | 0 | 2P stick, 2 btn | not traced | no |
| shngmtkbg | | Shanghai Matekibuyuu VER 1.20G, bootleg (1400) | ATA | mb2011 / 1 | no | ttgncl0 | 0 | 2P stick, 3 btn | not traced | no |
| tblkkuzug | | The Block Kuzushi VER 1.10G, bootleg (1401) | ATA | mb2011 / 1 | no | ttgncl0 | 0 | 2P stick, 3 btn | not traced | no |

Totals: card T1 23, T2 5, CF 3, ATA 8. Zoom 28, no Zoom 11 (six
originals plus five bootlegs). ZN-1 board (`coh1002t`): mawasunda only.
ROT270: 9 sets. Classes: taitogn_state 20, ttgncl4 10, ttgncl0 4, ttgnirq
2, ttgnmp 2, mawasunda 1.

"2P stick, 3 btn" is input `taitogn`: input `zn` (gn:798 to 875) minus
button 4, START3/4, COIN3/4, button 5 and players 3/4 (`zn2p`, gn:877 to
897), plus S551:4 Test Mode (`znt2p`, gn:899 to 906) and S551:2 BIOS test
(gn:861). Region is not a driver setting: it is the card's SYSTEM.INF
`area` letter (O or J on the local cards, 4.1). The AT28C16 EEPROM at
0x1faf0000 is common to every set (zn:113, zn:162); the G-NET driver has
nothing set-specific for it. CAT702 data is board-level, not per game: all
ZN-2 sets use tt10 and tt16 (gn:1019 to 1022), mawasunda uses tt01 and tt99
(gn:1042 to 1045).

## 2. Per-set and per-group notes

### 2.1 Driver state classes

- **ttgncl4** (gn:634 to 647): coin lockouts 2 and 3 from coin latch bits 3
  and 7. Output only; nothing for the core beyond the latch it already has.
- **ttgncl0** (gn:619 to 632): coin counters on bits 0 and 4, no lockouts.
  Output only.
- **ttgnirq** (sianniv, kollon; gn:649 to 680): a MAME hack. A read tap at
  0x80010008 writes 0 to I_MASK (0x1f801074) whenever the CPU executes that
  address ("IRQ still enabled when clearing bss", gn:657 to 658). The CF
  version of Kollon (kollonc) runs as plain taitogn_state without the hack
  (gn:1367), so the need may depend on the sub-BIOS (kollonc runs from the
  U30 that the v2 EPROM flashes, 2.3) or the card type; that is my
  inference, needs-review. The core should not copy the hack; the root cause (which IRQ fires and why it does
  not on the PCB, or whether the PCB also needs the game to survive it) is
  a research item (R27 below).
- **ttgnmp** (mahjngoh, usagi; gn:682 to 713): a mahjong panel read at
  0x1fa10100 (the P4 address), active-low AND of key rows KEY0 to KEY3
  selected by coin latch bits 2, 3, 6, 7 (gn:700 to 710). Inputs come from
  `mahjong_matrix_1p` (mahjong.h, not in docs/mame_sources.md). Mahjong Oh keeps the
  P1 stick and buttons (gn:971 to 978); Usagi removes them and START1/2
  (gn:1006 to 1014).
- **mawasunda** (gn:715 to 795): ZN-1 G-NET (`coh1002t_cf`, gn:729 to 735;
  `coh1002t` = `zn1_2mb_vram`, gn:370 to 374). Two "handles" (IPT_AD_STICK_X,
  gn:989 to 993) are integrated into the znmcu trackball counters, with
  player 2 scaled by -193/256 against 256/256 for player 1 and a TODO "figure
  out how each game balances the controls" (gn:782 to 788). Writes in the
  flash bank window at offsets 0x600000 (two 5-bit "weight" values) and
  0x600002 (16 lamps, active low) (gn:754 to 780), start LEDs on coin latch
  bits 2 and 3 (gn:762 to 768).

### 2.2 Card types

- **T1** (23 sets): what the core already builds for the priority games
  (docs/gnet_glue_design.md, docs/m0_findings.md 2 and 3).
- **T2** (spuzbobl, spuzboblj, gobyrc, usagi, zokuoten): unlock by ATA
  command 0xFE (sets sector count 1 and DRDY, raises IRQ) then 0xFC (DRQ,
  the host writes one 512-byte sector; bytes 2 to 6 must equal the key,
  every other byte 0) (af:257 to 321). While locked every other command ends
  with ERR and DRDY cleared (af:281 to 289). A wrong key sets ERR and leaves
  the card locked; whether a wrong key re-locks an unlocked card is a MAME
  TODO (af:306). Attribute register 0x07 is written 0xDF before the unlock
  (af:119, comment only).
- **CF** (kollonc, otenamhf, mawasunda): unlock by ATA command 0x0F with the
  five key bytes in Features, Sector Count, Sector Number, Cylinder Low,
  Cylinder High (af:353 to 375); IRQ raised either way, DRDY cleared on a
  wrong key. The header comment calls these SanDisk SDCFB-64 cards, 64 MB
  (gn:317 to 325), larger than the 40,960,000-byte Type 1 cards
  (m0_findings.md 2); size from the CHD, needs-review.
- **ATA** (eight bootlegs): no lock. If a CHD has no CIS metadata MAME
  builds a default CIS (af:29 to 52); key absent. Whether the bootleg CHDs
  carry IDNT and CIS is open until they are available.
- MAME notes a sealed "Type 2" card PCB for further Night Raid, XII Stag,
  Space Invaders Anniversary, Go By RC, Super Puzzle Bobble (Japan) and
  Usagi boards (gn:248 to 315); the dumps in MAME 0.288 use the slot option
  listed in the table regardless.

### 2.3 BIOS EPROM and JP1

- With JP1 = 1 the reset bank is 2 (gn:470), so the window at 0x1f000000
  shows the 1 MB EPROM instead of U30, and bank 3 shows the wave flashes
  (gn:497 to 505); the RF5C296 memory window (attribute memory) is only in
  bank 0 (gn:494). A T1 card unlocks through attribute memory, so by my
  reading of the map it cannot unlock with JP1 closed; consistently, every
  JP1 = 1 set in MAME is CF or ATA.
- What the EPROM does, measured (4.2): the v2 EPROM is a flasher. With JP1
  closed it erases wave0 to wave2 and zoomprog, rewrites the U30 sub-BIOS
  area 0x000000 to 0x04ffff, and stops on "writing finished normally,
  switch the power off". It does this on every boot while JP1 stays closed.
  docs/r1_speed_study.md 2 (step 3) saw the MB2011 EPROM behave the same
  way (U30 rewritten, same two messages, the card copied again on the next
  boot with JP1 open). So the game boots only after JP1 is opened, as
  MAME's comment says for the bootlegs (gn:1393); MAME's default JP1 = 1
  for kollonc and otenamhf (gn:921) also needs the user to open JP1 after
  the flash (inferred from the no-card runs; no CF CHD is available).
- v1 (gn:1028, "hand made") and mb2009 (gn:1032) are not the default of
  any set.

### 2.4 Zoom

- 28 sets keep the Zoom running. The TMS57002 microcode lives in the Zoom
  program flash: the ST0/ST1 header of program A (0084AA 008020) and of
  program B (0084AA 000020), in the 3-byte download order of
  docs/zoom_zsg2_tms57002_design.md 4.3, appear in every one of the six
  priority `zoomprog` images (16-bit swapped; at 0x8470 and 0x8cec, Ray
  Crisis at 0x8516 and 0x8d92), so all six firmwares carry both programs
  and only Psyvariar loads B. For the three local clone families the
  `zoomprog` image of each clone is byte-identical to the parent's (4.1),
  so the clones have the same DSP programs. For the 19 Zoom sets without a
  local CHD the programs, ZSG-2 features and MB87078 volume use are
  unknown; any TMS57002 instruction or mode outside A and B is a new risk
  (that doc lists what A and B leave unused). A first check needs no MAME
  run: build `zoomprog` with tools/build_flash.py and search it for ST0
  headers.
- MAME notes newer boards with an MN1020819DA and a Zoom ZFX-2 in place of
  the MN1020012A and TMS57002, "functionally identical" (zm:20 to 21, R9).
  Which games shipped with them is not known.
- No-Zoom sets: in MAME the MN10200 stays in reset and the Zoom reset bit
  in control_w is ignored (gn:518 to 535). On the PCB the BIOS presumably
  still releases the Zoom reset and the MN10200 runs whatever U27 holds
  (inference, needs-review). If the card has no zoomprog entry, U27 keeps
  the previous game's program or stays erased.

### 2.5 Inputs needing new mapping

- **gobyrc, rcdego** (gn:944 to 969; controller description gn:145 to 161):
  ANALOG1 = wheel (IPT_PADDLE, centre 0x80), ANALOG2 = trigger
  (IPT_PADDLE_V, reversed), both through the znmcu analog channels (zn:120
  to 121). All digital stick and button bits and START2 unused. A
  commented-out cabinet link ID (gn:962 to 968) is not emulated; the
  optional Communication Interface PCB (gn:14) neither.
- **mahjngoh, usagi**: mahjong keyboard (2.1).
- **mawasunda**: two analog handles plus outputs (2.1).
- **aerofgtsg**: S551:3 Test Mode and S551:4 Save Yes/No (gn:926 to 942);
  **aerofgtsg, raystormg**: button 3 removed (gn:926 to 933, 996 to 1004).

### 2.6 Bootlegs

The 2011 "Arcade MOD BIOS" conversions run games from other ZN boards:
Ray Storm and Fighters' Impact (Taito FX-1B, zn:5999, zn:6003), G-Darius
(FX-1B variant coh1002tb, zn:6007), Aero Fighters Special (Visco coh1002v,
zn:6031), Brave Blade (Raizing, zn:6108), Shanghai Matekibuyuu, Flame
Gunner and The Block Kuzushi (Tecmo coh1002m, zn:6095, 6099, 6102). Three
of them keep the Zoom (ftimpactg, gdariusg, raystormg). PLAN.md 2 lists
only four bootlegs; ftimpactg, flamegung, shngmtkbg and tblkkuzug are the
other four.

## 3. What the core plan must add

| Need | Sets | Block or change | MRA fields | Risk |
|---|---|---|---|---|
| Per-set card data | all | none beyond M0 (card image, KEY, IDNT, CIS loaded per set) | card image, key (5 B), IDNT (512 B), CIS | low; checked for the three clones (4.1) |
| T2 unlock | spuzbobl, spuzboblj, gobyrc, usagi, zokuoten | ATA engine: vendor commands 0xFE (no data) and 0xFC (one 512-byte PIO data-out, compare bytes 2 to 6), lock flag gating other commands | card type | low; MAME is the only source (af:257 to 321) |
| CF unlock | kollonc, otenamhf, mawasunda | ATA command 0x0F compares the task-file registers with the key | card type | low; card size (64 MB per gn:320) |
| No lock | 8 bootlegs | card type "none"; default CIS when the CHD has none | card type | low |
| EPROM bank and JP1 | kollonc, otenamhf, 8 bootlegs | 1 MB EPROM in bank 2 (gn:503), bank 3 = waves, reset bank from JP1 (gn:470, 540); docs/m2_glue_findings.md 3 row 7 has bank 2 reading 0 today | EPROM image (v2 or mb2011), JP1 as an OSD switch | medium: the flasher erases the waves and zoomprog, so the next boot repeats the 2 to 3 minute card copy. Better: build U30 offline the way tools/build_flash.py does for the card, so JP1 can stay open; needs the flasher's U30 output decoded (4.2) |
| Zoom present flag | 11 no-Zoom sets | hold the MN10200 in reset when clear (gn:518) | zoom = 0/1 | low in MAME terms; the PCB behaviour is open (2.4) |
| TMS57002 coverage | 19 Zoom sets not traced | any instruction or ST0/ST1 mode outside programs A and B | none | medium until their zoomprog images are checked |
| IRQ hack root cause | sianniv, kollon | none expected; trace instead of copying the hack | none | medium: unknown cause (R27) |
| Mahjong panel | mahjngoh, usagi | P4 read at 0x1fa10100 = AND of rows selected by coin latch bits 2, 3, 6, 7 | input profile = mahjong | low (MiSTer keyboard mapping) |
| Analog controls | gobyrc, rcdego | znmcu analog channels 0/1 from MiSTer analog inputs (znmcu model already planned) | input profile = analog | low; centre and range per gn:957 to 960 |
| Button count, DIP names | aerofgtsg, raystormg | none | button names, S551 labels (Save) | none |
| ZN-1 G-NET | mawasunda | CPU at the ZN-1 rate (CXD8530CQ from 67.7376 MHz, zn:80) next to the 50 MHz ZN-2 choice (R1), COH1002T BIOS (m534002c-14, tt01, tt99, own flash.u30, no EPROM, gn:1039 to 1053), CF card, trackball integration of the handles, lamp/weight writes in the flash window | board = coh1002t, BIOS set | high relative to its value: a second CPU rate and BIOS set for one game |
| GPU modes and MDEC | all untraced sets | none known; R18 (MDEC unused) and the GP1(08h) results (240p, widths 320/512/640, no interlace, docs/m1_gpu_zn2.md 4) cover only the six priority games and three clones | none | medium: an untraced game could use 480i, 24-bit colour or MDEC (the F0 build trims MDEC behind a switch, PLAN.md 5) |

New research item for PLAN.md 6:

| # | Question | Evidence needed |
|---|---|---|
| R27 | ttgnirq hack (sianniv, kollon): which interrupt is pending while the game clears its BSS at 0x80010008, and why kollonc does not need it | Oracle trace of kollon and kollonc boots (IRQ status and mask writes around 0x80010008) once the CHDs are present; PCB behaviour |
| R28 | No-Zoom sets on the PCB: does the BIOS release the Zoom reset, and what runs from U27 | BIOS control_w trace for a no-Zoom card; PCB audio |
| R29 | v2 / MB2011 flasher output: how the U30 sub-BIOS written by the flasher derives from the EPROM (first 0x3000 bytes equal EPROM 0x2c000 onward, the rest differs) | Decode as done for ZOOM.SDH (m0_findings.md 3a), to pre-build U30 for JP1 sets |

## 4. Measurements

### 4.1 Local clones: raycrisj, psyvarij, shikigama

`mame -rompath roms -verifyroms` (0.288): all three "best available" (the
uPD78081 is NO_DUMP), 1 of 1 OK. Cards extracted with
`tools/extract_card.sh <set>` to `sim/cards/`; flash images built with
`tools/build_flash.py sim/cards/<set>.img roms/coh3002t.zip
sim/flash/<set>`.

| Set | Card bytes | KEY | IDENTIFY model | Serial prefix | CIS bytes | SYSTEM.INF area, gameprog version | Flash images against parent |
|---|---|---|---|---|---|---|---|
| raycrisj | 40,960,000 | same as raycris | TAITO AT-40M-TE(S1) | LT980618 (same as raycris) | 123 | J, ray.sdh 2.03 | zoomprog, wave0, wave1, wave2 identical; firm differs (gameprog) |
| psyvarij | 40,960,000 | own key (CHD metadata) | TAITO AT-40M-TE(S1) | LT980921 | 123 | J, main.bin 2.04 | zoomprog, wave0 to 2 identical; firm differs |
| shikigama | 40,960,000 | own key (CHD metadata) | TAITO AT-40M-TE(S1) | LT980617SA034AT000 (different layout) | 122 | J, main.bin 1.02 | zoomprog, wave0 to 2 identical; firm differs |

All three: firmware Ver.6.3, IDENTIFY C/H/S 625/8/16, as the six priority
cards (m0_findings.md 2).

Cold oracle boots (`ORACLE_SNAP_EVERY=600 ORACLE_COIN_AT=190
tools/mame/oracle_run.sh <set> 240 sim/oracle/survey_<set>_cold240 --cold`,
psyvarij and shikigama with `ORACLE_VRAM_DUMPS=14000`). All three reached
play after the coin (snapshots at frame 13800: raycrisj player select,
psyvarij continue screen).

| Set | Flash copy (first to last command) | ATA commands | GP1(08h) values | Upper VRAM (lines 512 to 1023, frame 14000) | znsecsel (0x1fa10300) writes |
|---|---|---|---|---|---|
| raycrisj | 2.86 to 144.14 s | 0x20 x794, 0x30 x32, 0xEC x3 | 08000000 x4, 08000001 x10,981, 08000002 x2,995, 08000003 x129 | not dumped | 0x0c 190, 0x84 41, 0x88 144, 0x8c 3, 0x00 1; last at 162.6 s |
| psyvarij | 2.86 to 130.19 s | 0x20 x2,600, 0xEC x3 | 08000000 x4, 08000001 x14,104 | 315,502 pixels | 0x0c 189, 0x84 40, 0x88 145, 0x8c 3, 0x00 1; last at 139.0 s |
| shikigama | 2.86 to 142.06 s | 0x20 x184, 0xEC x3 | 08000000 x4, 08000001 x14,084 | 145,071 pixels | as the others at boot, then 0x1c, 0x94, 0x98 about 100 per second from 140 s to the end (8,818 / 4,742 / 4,074) |

Readings:
- The clones need no new hardware: same card format, same Zoom program
  and wave data, same GPU modes as their parents (raycris 01h/02h/03h,
  the rest 01h; m1_gpu_zn2.md 4), no interlace, 240 lines, upper VRAM
  used. Only the card data differs.
- Shikigami (both sets; the parent's 60 s log `sim/oracle/m1_shikigam_60`
  shows 0x1c x5,058, 0x94 x2,707, 0x98 x2,349) keeps using the security
  select during play: once or twice per frame it writes 0x94 or 0x98 (bit
  4 = znmcu analog read, zn:267; bit 2 or bit 3 low, the CAT702 select
  lines, zn:265 to 266) and then 0x1c, with 4 SIO0 bytes per selection
  (shikigama from 150 s to 240 s: 17,436 selections, 69,744 bytes sent).
  Which device answers is open: MAME also asserts the znmcu select for
  these values ("TODO", zn:269). The other five priority games and
  raycrisj/psyvarij touch znsecsel only at boot. So the SIO0 / CAT702 /
  znmcu path has to be right during play for Shikigami, not only at boot.
  This is a new fact for the priority set, not just the clone.
- Ray Crisis J writes 32 sectors like raycris; psyvarij and shikigama
  wrote none in 240 s.

### 4.2 BIOS v2 EPROM flasher (kollonc, otenamhf)

`coh3002t -bios v2` with JP1 = 1 through `tools/mame/oracle_bios_run.sh`
(written for this survey; the first two runs used the same command line
by hand), no card:

| Run | Result |
|---|---|
| cold, 220 s (`sim/oracle/survey_coh3002t_v2_jp1_220`) | From 0.17 s erases every block of wave0, wave1, wave2 (32 each) and zoomprog (7), no programming; then issues 37 U30 block erases and programs 163,858 words, U30 0x000000 to 0x04ffff plus a few words at 0x050000 (99.5 to 139.3 s); screen "初期化中" with a blue bar, then "正常に書き込みが終了しました。そのまま電源を切ってください。" (written normally, switch off). Waves and zoomprog left blank (all 0xFF); no ATA access |
| warm from that NVRAM, 40 s, JP1 still 1 (`sim/oracle/survey_coh3002t_v2_jp1_warm`) | Erases the waves again from 0.17 s: the flasher runs on every boot while JP1 is closed |
| cold, 20 s (`sim/oracle/survey_scriptcheck_v2`) | Script check: same start (wave0 erases from 0.17 s) |

The written U30 is not the stock flash.u30 sub-BIOS: the first 0x3000
bytes equal the 16-bit-swapped EPROM from 0x2c000, the rest differs
(57,440 of 327,680 bytes equal), and the v2 and MB2011 EPROMs hold
different payloads at that offset. I have not decoded it (R29).

## 5. Second wave

Recommended order, by new work per set:

1. **raycrisj, psyvarij, shikigama.** Data only: MRAs with their card
   files. Already verified in MAME and with the flash builder (4.1); ready
   as soon as the six priority games run.
2. **Super Puzzle Bobble (spuzbobl, spuzboblj).** The only new block is the
   T2 unlock (two ATA commands); Zoom, standard inputs. Needs the CHDs to
   trace GPU modes and the DSP program.
3. **gdariusg, raystormg, ftimpactg.** Plain ATA card (simplest) with the
   Zoom; needs the EPROM bank, JP1 and a decision on the flasher (R29).
   Their originals run on the FX-1B core, which makes them an A/B check
   of the Zoom (PLAN.md 2, priority 6). aerofgtsg and brvbladeg (shooters,
   ROT270) then add only the no-Zoom flag.
4. **Type 1 Zoom games with standard inputs**: chaoshea, chaosheaj,
   flipmaze, otenki, shanghss, soutenry, shangtou. No new block expected;
   each needs its CHD traced (GPU modes, MDEC, DSP program) before an MRA.

Later: the no-Zoom Type 1/2 puzzle games (otenamih, zokuoten, zokuotena,
zooo), gobyrc/rcdego (analog), mahjngoh/usagi (mahjong keyboard),
sianniv/kollon (R27 first), the CF sets kollonc and otenamhf (CF unlock
plus the v2 flasher), flamegung, shngmtkbg, tblkkuzug, and mawasunda last
(ZN-1 board for one game).

## 6. Files

- `tools/mame/oracle_bios_run.sh`: oracle run with a chosen BIOS EPROM and
  JP1 (cold, or warm from an NVRAM directory).
- Work data (gitignored, game-derived): `sim/cards/{raycrisj,psyvarij,
  shikigama}.*`, `sim/flash/{raycrisj,psyvarij,shikigama}/`,
  `sim/oracle/survey_*`.
