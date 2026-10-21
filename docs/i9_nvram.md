# Issue #9: Psyvariar settings are not kept

Branch i9-nvram (from alpha4 59d57d1). Status 2026-10-20: cause proven in
MAME; fix implemented behind the macro GNET_CARD_JOURNAL (test revision
GNET_Z1FULLJ), all simulation gates pass (section 8); not built, not tested
on hardware. GNET_Z1FULLR (the release revision) does not define the macro.

Report (Fizzen, alpha 1, 2026-10-09): Psyvariar -Medium Unit- (V2.02O).
"Default loads in Horizontal. Changing to vertical. When you reload the core
the Taito logo doesnt change its still horizontal. Setting in service menu
dont save."

## 1. Result

- Psyvariar keeps its service menu settings on the PC card, not in the
  EEPROM and not in the flash. Saving a setting is an ATA WRITE SECTORS to
  the card (section 2). The orientation the reporter means is the game's
  INVERT item ("Set direction of screen display", GAME CONFIGURATION); it
  is byte 48 of card sector 48629.
- The core keeps card writes in DDR3 only. Every load copies the card image
  from the zip into DDR3 again, so every setting the game stores on the card
  is lost at the next load. The core's NVRAM save covers only the 2 KB
  AT28C16 EEPROM (MRA `<nvram index="6" size="2048"/>`). Psyvariar never
  writes the EEPROM (it stays all FFh), so for this game no .nvm file is
  ever written, whether or not the OSD is opened. Saving the EEPROM alone
  can never keep these settings.
- The TAITO logo is drawn by the board's BIOS before the game runs. It is
  identical with INVERT on and off in MAME (frames 60 to 540 byte-identical,
  section 2.3), so the logo not turning is correct behaviour, not part of
  the bug.
- Card writes are the open item R25 in docs/PLAN.md: gnet_ata already
  writes sectors into DDR3 and keeps a 4 KB hunk dirty map, but nothing
  saved them (alpha4 zn2_board.vhd:338 leaves the dirty map ports open).
- Fix (section 6, rtl/gnet/gnet_card_journal.sv): a journal of the card
  hunks the game writes, in the same NVRAM file as the EEPROM. Main_MiSTer
  offers arcade cores no save trigger other than opening the OSD (section
  4), so the trigger stays "OSD open after a change", now counting card
  writes as well as EEPROM writes. MRAs need `<nvram index="6"
  size="268288"/>`; 2 KB MRAs keep working and save the EEPROM only.

## 2. Where Psyvariar stores its settings (MAME 0.288 evidence)

### 2.1 Method

MAME 0.288 (/opt/homebrew/bin/mame), tools/mame/oracle.lua (ata.log,
flash.log with ORACLE_FLASH_RAW=1, snapshots, ORACLE_PLAN inputs), run from
the post-first-boot state of sim/oracle/psyvaria_cold300 (NVRAM files firm,
wave0 to 2, zoomprog, at28c16 and the CHD diff of card writes). A MAME cfg
sets DSW S551:4 Test Mode On. Runs and the wrapper script are kept in
sim/oracle/i9_psyvaria_* (gitignored, game-derived data; the wrapper
run.sh and atawrites.py are in i9_psyvaria_gc3).

Test menu path (snapshots): the game's TEST MODE appears at about 12.5 s;
P1 Down x4, Button 1 opens GAME CONFIGURATION (DIFFICULTY, PLAYER, BOMB,
INVERT, RETURN); Down x3 to INVERT, Right sets ON, Down to RETURN,
Button 1 shows "SAVE ALL MODIFICATIONS? YES (NO)", Left, Button 1 = YES.
No other menu page has an orientation item (SYSTEM CONFIGURATION holds the
coin and continue settings, SCREEN ADJUSTMENT is a test grid).

### 2.2 What changes when the setting is saved

| Run | Plan | at28c16 | firm, wave0 to 2, zoomprog | Card (ATA writes in ata.log) |
|---|---|---|---|---|
| gc1 | INVERT ON, RETURN, stop at "SAVE?" (NO highlighted) | unchanged, all FFh | unchanged | none |
| gc2 | as gc1, then YES at 21.8 s | unchanged, all FFh | unchanged; flash.log (gc2, gc3) has no program or erase command, only 90h and FFh (identify, read array) and the card unlock writes to attribute memory | 6 x WRITE SECTORS (30h), 1 sector each, at 21.832 to 21.887 s: LBA 48553, 64, 48553, 48629, 64, 48553 |
| gc3 | three saves (ON, OFF, ON) | unchanged | unchanged | the same 6 writes at each save (21.8, 28.8, 35.8 s) |

Card content (chdman extractraw with the parent CHD), gc1 against gc2: only
sector 48629 differs, one byte: offset 48, 00h to 01h. Sectors 64 and 48553
are rewritten with the same data. The game rewrites the same three sectors
in place on every save (gc3), so the set of written sectors does not grow
with repeated saves.

Other card writes seen: psyvaria_cold300 (coin at 180 s, play until the game
ended) wrote LBA 64, 48553, 48633, 48634, 48665, 48666 at 287 s, so the
game's records also go to the card.

### 2.3 The card sectors alone carry the setting

Two warm boots, 25 s, Test Mode off, from the same NVRAM files (gc2's,
identical to gc1's):

| Run | Card diff | Result |
|---|---|---|
| v_saved | gc2's (with the saved sectors) | NOTICE, Prologue and attract drawn upside down (INVERT ON) |
| v_orig | psyvaria_cold300's (before the save) | normal orientation |

Frames 60 to 540 (TAITO G-NET logo, "Prepares the start", the BIOS warning)
are byte-identical PNGs in both runs; the game's own screens from the
NOTICE on differ.

### 2.4 Other games (survey of existing oracle runs)

EEPROM bytes not FFh at the end of existing runs, and ATA writes in their
ata.log (atawrites.py over sim/oracle/*):

| Set | EEPROM used | Card writes seen |
|---|---|---|
| psyvaria, psyvarrv | no | yes (settings, records) |
| raycris, raycrisj | 32 bytes | 32 sectors in 32 hunks, at boot (warm 15.7 s) and after the first boot copy |
| gobyrc | 1,160 bytes (calibration, EEPROM 478h-487h) | none seen |
| mahjngoh | 256 bytes | none seen |
| spuzbobl | 44 bytes | none seen |
| chaoshea | 192 bytes | none seen |
| nightrai, shikigam, xiistag, sianniv, zooo, otenamih, zokuoten | no | none in these runs (R25 lists 3 hunks each for xiistag and shikigam from older runs) |

So both kinds exist: some games keep settings in the EEPROM (these work
with today's save, once it is checked on hardware), others on the card.
None of these runs entered every game's service menu, so the per-game split
of settings is not complete (open question 1).

## 3. What the core saves today

- Load: Main_MiSTer sends the .nvm file as ioctl index 6 at load; PSX.sv
  passes each word to the EEPROM through the loader (zn_ld_*, target 2,
  `zn_ld_addr <= ioctl_addr[10:0]`, PSX.sv:869).
- Save: PSX.sv:1102-1123. A CPU write to the EEPROM toggles zn_nv_wtog
  (zn2_io); PSX.sv synchronises it and sets nv_dirty; on the OSD_STATUS
  rising edge with nv_dirty set, nv_upload_req pulses and hps_io latches it
  (sys/hps_io.sv:289-290) until Main reads it with UIO_CHK_UPLOAD (335).
  The upload reads zn2_io's EEPROM copy (nv_din, PSX.sv:2174).
- Card: gnet_ata writes each written sector to DDR3 through zn2_cardmem and
  sets the sector's 4 KB hunk in its dirty map (gnet_ata.sv:170-187);
  zn2_board.vhd:338-342 leaves the map's ports open. Nothing reads it.

Never checked on hardware: the EEPROM save itself (memory and the issue
reply drafts say so).

## 4. Main_MiSTer's NVRAM handling (MiSTer-devel/Main_MiSTer 63186a3, fetched 2026-10-20)

- support/arcade/mra_loader.cpp:66-110: one `<nvram>` per MRA (nvram_idx,
  nvram_size). Load: arcade_nvm_load() runs when the parser closes the
  `<nvram>` tag (line 963), after the `<rom>` entries above it, so after the
  card image; it reads config/nvram/<MRA name>.nvm into a zeroed buffer of
  nvram_size and sends all nvram_size bytes (FileLoad reads at most the
  file's length, file_io.cpp:849-866, so a shorter file arrives zero
  padded). Save: arcade_nvm_save() uploads nvram_size bytes of index
  nvram_idx and writes them with FileSave (temp file, then rename).
- Callers of arcade_nvm_save (menu.cpp): MENU_SAVE_CHECK (2297-2314), entered
  each time the OSD main menu opens (MENU_GENERIC_MAIN1, 1934-1937), saves
  only if UIO_CHK_UPLOAD returns the core's request, and shows "Saving..."
  for 500 ms; and the common menu's "Save settings" item (3104-3121), which
  saves without a request.
- user_io_poll (user_io.cpp:4050-4054) polls UIO_CHK_UPLOAD only for C64 and
  C128. There is no periodic or power-off save for arcade cores.

So every MiSTer arcade core that saves NVRAM (the Hiscores_MiSTer high score
module, as in my Hyper Duel core, included) saves only when the OSD main
menu opens after the core asked, or on "Save settings". A G-NET core cannot
autosave more often without a Main_MiSTer change.

Upload handshake: Main reads each 16-bit word with spi_w (spi.cpp:170-177,
fpga_spi waits for the acknowledge). hps_io latches ioctl_din at the strobe
for the current ioctl_addr, then steps ioctl_addr and pulses ioctl_rd
(hps_io.sv:686-699). sys_top holds the acknowledge while io_wait
(= ioctl_wait) is high (sys_top.v:254-262), so a core can stall an upload
word by word, as it stalls downloads.

## 5. Options considered

| Option | Verdict |
|---|---|
| Save the EEPROM only, better trigger | Cannot work for Psyvariar (section 2). |
| Save the whole card (41 MB) as the NVRAM | Rejected: about 24 s per save at the measured 1.6 to 1.8 MB/s word rate. |
| Card as an OSD-mounted writable image (sd_lba, like PSX memory cards) | Arcade MRAs have no automatic mount; the player would have to mount a file. Rejected. |
| Fixed card region per game in the MRA | Needs per-game LBA lists; FAT allocation can differ per game. Rejected. |
| Journal of written 4 KB hunks after the EEPROM in the same .nvm | Chosen (section 6). Small, generic, uses the existing loader and upload paths. |

## 6. Design: card hunk journal

### 6.1 File layout (index 6, size 268,288 bytes = 131 x 2 KB)

| Byte offset | Size | Content |
|---|---|---|
| 0 | 2,048 | EEPROM (as today) |
| 2,048 | 512 | Directory: 64 entries of 8 bytes: 47h 4Eh 43h 4Ah ("GNCJ"), hunk (16-bit little-endian), hunk XOR FFFFh. An entry that fails the check is empty. |
| 2,560 | 1,536 | zero |
| 4,096 | 262,144 | 64 slots of 4,096 bytes: slot k holds the card bytes of directory entry k's hunk (card byte hunk x 4096 onwards) |
| 266,240 | 2,048 | EEPROM again (mirror) |

Why the mirror: today's RBFs load index 6 with `ioctl_addr[10:0]`
(PSX.sv:869), so a longer file wraps onto the EEPROM and the last 2 KB wins.
With the mirror last, an alpha 3 or 4 RBF given a new MRA still ends with
the right EEPROM. A 2 KB .nvm from today loads zero padded: EEPROM right,
directory empty.

64 slots: the largest set seen is Ray Crisis, 32 hunks (section 2.4).
Upload and load of 268 KB take about 0.16 s each at the measured word rate.

### 6.2 Load (index 6 download, core in reset as for every G-NET download)

rtl/gnet/gnet_card_journal.sv on clk_1x, instanced in PSX.sv beside the
existing loader:

- addr < 2048: EEPROM through zn_ld_* as before; with the macro the EEPROM
  loader takes only these words (ee_sel), so the mirror and the journal
  never reach the EEPROM.
- 2048 to 2559: directory entries checked in order; the leading valid
  entries (GNCJ, hunk below 16384, complement right, entry number = list
  length) become the list (64 x 14-bit registers). The first invalid entry
  ends it.
- 4096 + 4096k + n, k below the list length: the word goes to the card
  loader path (zn_card_dl_*, the index 5 path into zn2_cardmem, ioctl_wait
  = zn_ld_busy or zn_card_wait) at card byte hunk(k) x 4096 + n. Words of
  other slots, the padding and the mirror are dropped.
- The list survives the load, so the restored hunks are saved again.
- An index 5 download (a new card image, also the DDR3 load of issue #12,
  which still raises ioctl_download) or an index 6 download empties the
  list first, so a game loaded without a .nvm never saves another game's
  hunks.

The card image (index 5) is complete before index 6 starts (section 4), so
the journal lands on top of the fresh image. Every journal word is written
before Main sends the next one (ioctl_wait), so the last DDR3 write is done
before the download ends and the core's reset is released (bench P5).

### 6.3 Dirty list and the crossing

zn2_board (its clock: clk_cpu in CPU_CLK_SPLIT builds) toggles
cdc_tx_cjtog and loads cdc_tx_cjhunk with gnet_ata's hunk on the same edge
for every stored sector (dirty_set, which gnet_ata raises after the sector
is in storage). The journal passes the toggle through cdc_rx_s1 and
cdc_rx_s2 and captures the hunk into cdc_rx_hold on the clock after the
toggle leaves cdc_rx_s2, so rtl/gnet/cdc/cdc.sdc rules 1 (cdc_tx to
cdc_rx_s1) and 1b (cdc_tx to cdc_rx_hold) constrain both paths by name.
gnet_ata stores at most one sector per 100 us, so the hunk is stable long
before the capture. The list search takes at most 65 clk_1x cycles
(about 2 us); a hunk already listed is not added again; a 65th distinct
hunk sets the sticky overflow flag. Every event sets card_dirty. The list
is not reset by the core reset, since the card in DDR3 keeps the writes
across an OSD reset.

### 6.4 Save

- Request (PSX.sv): on the OSD_STATUS rising edge, nv_upload_req if the
  EEPROM or the card is dirty; the journal clears card_dirty on that
  request (req_take), and an event in the same clock wins. A write during
  the upload sets it again, so the next OSD open saves again (bench P8).
- Upload stream: 0 to 2047 nv_din (EEPROM copy); directory entries 0 to
  n-1 (all empty if the overflow flag is set: saving no card hunks keeps the
  card image consistent, a partial set would not); zero padding; slot k
  below n: the hunk read from DDR3; other slots zero; the mirror: nv_din
  again. n and the overflow flag are taken at the start of the upload; the
  list only grows, so the file stays consistent when the game writes
  during the upload.
- DDR3 read: a third client in zn2_cardmem's IDLE arbitration, after the
  loader and the gnet_ata port (generic CARD_JOURNAL): one 64-bit line at
  BASE + byte address, acknowledged like the gnet_ata port (ul_ack held two
  clk2x cycles, one clk1x edge), so the existing states are reused with a
  flag (ul_sel) and nothing else changes when the generic is false.
- Stall rule as built: ioctl_din is a registered copy of the word at
  ioctl_addr (two clocks: the address, then the EEPROM copy's registered
  read or the line buffer); ioctl_wait = upload and "the copy is not for
  the current ioctl_addr", combinational. hps_io moves ioctl_addr on the
  strobe; in the next clock sys_top sees io_wait high and holds the
  acknowledge until the copy is right, so Main never reads a stale word.
  One line buffer, no prefetch: each new line stalls for one DDR3 read.

### 6.5 Compatibility

| RBF | MRA nvram size 2048 (today) | MRA nvram size 268,288 |
|---|---|---|
| alpha 3, alpha 4, any build without the macro | EEPROM saved (today) | EEPROM loads right (mirror last); the save writes the EEPROM repeated through the file, which the journal build's directory check rejects (bench P3) |
| GNET_CARD_JOURNAL build | EEPROM saved, byte-identical to the build without the macro (bench P1); card not saved (Main uploads only 2 KB) | EEPROM and card hunks saved |

The MRA generator (gnet-release tools/gnet/make_release_mras.py) needs one
attribute changed when the journal ships: `<nvram index="6"
size="268288"/>` in all 58 MRAs. Not changed yet.

### 6.6 Files changed

| File | Change |
|---|---|
| rtl/gnet/gnet_card_journal.sv | new: load routing, list, crossing, upload stream, DDR3 line reads |
| PSX.sv | under `GNET_CARD_JOURNAL` only: EEPROM loader gated to the first 2 KB, journal slot words to the card loader path, ioctl_wait for index 6 includes zn_card_wait, hps_io ioctl_wait or'd with the journal's stall and ioctl_din from the journal, request on card writes, the instance; always: psx_mister generic CARD_JOURNAL (0 without the macro) |
| rtl/gnet/zn2_cardmem.vhd | generic CARD_JOURNAL (default false) and the ul_* read client |
| rtl/gnet/zn2_board.vhd | gnet_fc's dirty_set and dirty_hunk connected; the cdc_tx_cjtog / cdc_tx_cjhunk process; ports cj_tog, cj_hunk |
| rtl/psx_top.vhd, rtl/psx_mister.vhd | generic CARD_JOURNAL, ports zn_cj_* passed through, both zn2_board and both zn2_cardmem instances (with and without CPU_CLK_SPLIT) |
| GNET_Z1FULLJ.qsf | new revision: GNET_Z1FULLR plus the macro and the new file |
| tools/pc_build.sh | target z1fullj |

GNET_Z1FULLR.qsf and files.qip are unchanged: without the macro the new
VHDL ports have no load and the new zn2_cardmem branch is constant false.

## 7. Behaviour without the macro

- PSX.sv: the code without GNET_CARD_JOURNAL is the alpha4 code, plus the
  psx_mister generic set to 0. tools/lint_psx.py GNET_Z1FULLR and
  GNET_Z1FULLJ: no warnings or errors.
- zn2_cardmem with CARD_JOURNAL = false against alpha4's: both through
  ghdl --synth, Verilator co-simulation of 20,000,000 clocks of random
  inputs, every output compared every clock: 0 differences (10,667,190
  clocks with a memory request). Negative control, the new file with the
  read client on and requesting: 19,996,826 clocks differ
  (sim/i9/eq_cardmem.sh).
- psx_top elaborates in the GNET_Z1FULLR configuration (zn2full.sh
  generics) with CARD_JOURNAL 0 and 1 (ghdl --synth, sim/i9/vhdl_check.sh).
- The release netlist can still differ slightly (Quartus may not fold every
  new constant the same way), so the first GNET_Z1FULLR build after a merge
  needs the usual fit and STA checks.

## 8. Simulation results

Bench: sim/i9/tb_cj.sv, `sim/i9/run.sh` (inputs from `sim/i9/prep_data.py`
into sim/i9/work, gitignored: the Psyvariar card from the CHD, MAME's card
after the session from sim/oracle/i9_psyvaria_gc2, the ATA writes MAME
logged, the Go By RC EEPROM from sim/oracle/i4_rc1).

Real RTL in the bench: sys/hps_io.sv; PSX.sv's own loader block, save
request block, journal declarations and instance (copied out of PSX.sv by
sim/i9/gen_glue.py at every run, so the bench runs what PSX.sv has);
gnet_card_journal.sv; zn2_cardmem.vhd (ghdl --synth, CARD_JOURNAL = true);
gnet_ata.sv on clk_cpu (50 MHz) doing the game's WRITE SECTORS through its
task file. Models: Main_MiSTer's fpga_spi word handshake (each HPS access
20 to 300 ns at random) and the arcade_nvm_load / arcade_nvm_save /
UIO_CHK_UPLOAD sequences (section 4); sys_top's gp_out pipeline and io_ack
block (copied); PSX.sv's ioctl_wait branch for the G-NET indices (copied by
hand: it sits in the block that also serves the BIOS and flash paths);
zn2_io's EEPROM copy (registered read); zn2_board's event process (copy)
behind a channel that delays the toggle and every hunk bit independently by
0 to 14 ns (the cdc.sdc bound); a DDR3 port with 0 to 40 clk2x of random
latency to the acknowledge and again to the data; clk_1x 33.8688 MHz, clk2x
twice that on the same edges, clk_cpu 50 MHz with an offset.

| Phase | Build | What | Result |
|---|---|---|---|
| P1 | both | Go By RC, 2 KB MRA: load MAME's calibrated EEPROM, rewrite 478h-487h from the CPU side, OSD open: request 0601h, upload, file equals the EEPROM; second OSD open: no request | PASS both; the two 2,048-byte files are byte-identical (run.sh cmp) |
| P3 | without | journal file on an RBF without the macro: EEPROM ends right (mirror), no card write; the save is the EEPROM repeated 131 times | PASS |
| P2 | journal | Go By RC 2 KB .nvm zero padded into a 268,288-byte MRA: EEPROM right, journal empty; saved file: EEPROM at 0 and at 266240, the rest zero | PASS |
| P3 | journal | the file from the build without the macro: EEPROM right, directory rejected, no card write; a synthetic two-entry journal replays at hunks 100 and 107 | PASS |
| P4 | journal | Psyvariar: card loaded by the DDR3 path, MAME's 20 WRITE SECTORS (the credit at 287 s, then the INVERT ON save), OSD open | PASS: request, directory 6069, 8, 6079, 6083, 6078 in write order, slots equal MAME's card, EEPROM FFh at both ends |
| P5 | journal | reload: fresh card, index 6 with the saved file | PASS: 5 entries, 5 x 512 line writes, the last one before the index 6 download ends (the core's reset release), loader idle; all 40,960,000 card bytes equal MAME's card after the session; sector 48629 byte 48 = 01h |
| P6 | journal | OSD open after the reload, nothing changed | PASS: no request |
| P7 | journal | INVERT OFF save, OSD, reload | PASS: still 5 entries; whole card equals the INVERT OFF card |
| P8 | journal | a write, OSD open, a second write finished during the upload | PASS: first file 6 entries (start snapshot), card_dirty set again, next OSD open saves 7 entries; reload equals the expected card |
| P9 | journal | 57 more hunks (64 in all), save, reload; then a 65th | PASS: 64 entries replayed, whole card right; 65th sets overflow, the save has an empty directory and both EEPROM copies, its reload gives the zip's card |
| P11 | journal | a card load without a .nvm after writes | PASS: next save has an empty directory |
| P10 | journal | crossing: 2,000 events from the clk_cpu side (40 hunks, repeats), gaps 2 to 20 us, skewed channel | PASS: list = the 40 hunks in first-seen order, card_dirty set |

Totals: without the macro 8 checks, with it 48 checks, all pass
(simulated 0.24 s and 2.0 s; 47 s and 767 s wall time).

Negative controls (sim/i9/mutants.py, each a copy of the journal with one
fault; run.sh expects every one to fail):

| Mutant | First failing check |
|---|---|
| nostall (no ioctl_wait from the journal) | P4: slots differ from MAME's card (words read before their DDR3 line arrived) |
| nomirror (no EEPROM copy at the end) | P2: mirror at 266240 missing |
| norearm (a write during an upload does not set card_dirty) | P8: card_dirty not set again |
| earlyhold (hunk captured on the edge that first samples the toggle) | P4: directory holds wrong hunks (4104, 6135, 5949, 24 among the right ones), the skewed bits caught early |
| noreplay (slot words not written to the card) | P3: synthetic journal not replayed |
| nodircheck (entries accepted without GNCJ and the complement) | P2: the zero padding of a 2 KB file read as 64 entries |
| noclear5 (index 5 does not empty the list) | P4: hunks 100 and 107 from the previous card listed first |
| nodedupe (no search, every write appends) | P4: 20 entries for 5 hunks |

Other checks: tools/lint_psx.py GNET_Z1FULLR and GNET_Z1FULLJ (no
warnings or errors in PSX.sv); `verilator --lint-only -Wall` on
gnet_card_journal.sv (clean apart from the house-style power-up values);
zn2_cardmem equivalence and psx_top elaboration (section 7).

Not covered: the full-system Psyvariar boot (open question 7); Quartus fit
and timing; Main_MiSTer's real HPS timing (the model's 20 to 300 ns per
access is faster on average than the 1.6 to 1.8 MB/s measured on hardware,
so it stresses the stall more than Main does).

## 9. Build request

- Branch i9-nvram, commit 617c721 (the RTL; later commits on the branch
  change docs only), revision GNET_Z1FULLJ,
  `tools/pc_build.sh z1fullj` (own build dir gn_z1fullj). Seed 8 as
  GNET_Z1FULLR; if timing misses, try the seeds that closed alpha 3 first.
  The pll_hdmi counter check applies.
- What it adds: gnet_card_journal (about 1,100 flip-flops, mostly the
  64 x 14-bit list; four 14-bit 64:1 read muxes on it: load slot, upload
  entry, upload slot, search; one 64-bit line buffer), the
  zn2_cardmem read client, two synchroniser stages and a 14-bit hold
  register. The device is at about 87%; if the fit is tight, the list can
  move to an MLAB.
- STA: the new crossing is named for cdc.sdc (cdc_tx_cjtog/cjhunk to
  cdc_rx_s1/cdc_rx_hold); check that the CDC report lists it and nothing
  else between the CPU and PS1 groups is new.
- Test MRAs: copies of the release MRAs with `size="268288"` on the nvram
  line and `<rbf>` pointed at the test RBF name (section 9, part B).

## 10. Hardware test procedure for Lee

Part A works on the alpha 3 or alpha 4 RBF, no new build. It checks the
EEPROM save that exists today and confirms the Psyvariar finding.

A1. Go By RC (EEPROM game): load it, do the calibration (three presses of
    Start), let the game reach attract. Open the OSD (F12) and close it.
    Expected: "Saving..." flashes briefly, and
    `/media/fat/config/nvram/<MRA name>.nvm` exists with 2,048 bytes.
    Reload the MRA: the calibration is kept.
A2. If no file appears: open the OSD common page (Win+F12) and pick
    "Save settings", which saves without the core's request. A file now
    means the request is the fault; still no file means the upload is.
A3. Psyvariar -Medium Unit- (V2.02O): OSD Service Menu On, then OSD Reset.
    In TEST MODE: GAME CONFIGURATION, INVERT to ON, RETURN, YES. Service Menu
    Off, OSD Reset. Expected: the game's screens are upside down (the card
    in DDR3 keeps the setting until the next load; the TAITO logo is not
    turned, as in MAME). Open and close the OSD. Expected: no Psyvariar
    .nvm file (the game never writes the EEPROM). Reload the MRA: INVERT is
    back to OFF. This is the bug, as section 2 predicts.

Part B needs the GNET_Z1FULLJ build (section 9), deployed under a test
name as the deploy rules say, for example `TaitoGNET_i9_<date>.rbf`. Do part
A first: if the EEPROM save fails there, it fails here too.

B0. Test MRAs: copies of the release MRAs for Psyvariar -Medium Unit-
    (V2.02O), Go By RC and Ray Crisis with `<rbf>TaitoGNET_i9_<date></rbf>`
    and the nvram line changed to `<nvram index="6" size="268288"/>`; give
    them their own names (the .nvm file is named after the MRA).

B1. Psyvariar: as A3; the OSD shows "Saving..." and the .nvm file is
    268,288 bytes.
    Reload: the NOTICE screen is upside down. Set INVERT OFF, save, open
    the OSD, reload: normal again.
B2. Go By RC with the 2 KB file from A1: calibration kept on the journal
    build; after the next save the file is 268,288 bytes and the
    calibration is still kept.
B3. The B0 Psyvariar MRA with `<rbf>` pointed back at the alpha 4 RBF:
    boots, the settings are the card's defaults (that RBF does not replay
    the journal), and the EEPROM is right (Go By RC the same way: the
    calibration is kept).
B4. Ray Crisis: play one credit, open the OSD, reload, play again (it writes
    32 hunks at boot; checks a full journal of real data).
B5. Load time with the new MRAs against A1's: no more than about 0.3 s
    longer.
B6. OSD pause Off (status 64), Psyvariar: change a setting with the OSD
    closed, open the OSD, reload: kept.

## 11. Open questions

1. Which other games keep settings on the card: needs a MAME pass per set
   with a service menu save and one full credit, reading ata.log and the
   EEPROM (the scripts in sim/oracle/i9_psyvaria_gc3 do this for one set).
   Also confirms that 64 slots are enough.
2. The EEPROM save has never run on hardware (part A).
3. Whether a real Psyvariar board shows the TAITO logo unturned with INVERT
   on: MAME does; no board evidence.
4. CompactFlash sets (kollonc, otenamhf): card up to 64 MB, 16,384 hunks,
   still 14 bits; not checked for writes.
5. A card write while the OSD is open (OSD pause off) is saved at the next
   OSD open, as for the EEPROM: Main checks for a request only when the
   main menu opens.
6. Main's upload rate for 268 KB with the journal's stalls: the bench
   cannot give it; B5 measures the load side.
7. Full-system sim (sim/fullsys) of a Psyvariar warm boot with the journal
   file was not run: the module bench replays the journal into the card
   memory and compares all 40,960,000 bytes with MAME's card, and MAME
   showed that card boots upside down (section 2.3).
