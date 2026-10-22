# High score save (MAME hiscore.dat): Super Puzzle Bobble

Branch hiscore (from alpha5-ddr3 53deaf1). Status 2026-10-21: need proven in
MAME; implemented behind the macro GNET_HISCORE (test revision GNET_Z1FULLH),
all simulation gates pass (section 5); not built, not tested on hardware.
GNET_Z1FULLR (the release revision) does not define the macro.

Closes the beta gap "High scores where hiscore.dat supports the game"
(docs/beta_readiness.md 2.6 on the alpha4 line). MAME 0.288's
plugins/hiscore/hiscore.dat has one G-NET set, lines 14697-14698:

    spuzbobl:
    @:maincpu,program,28bf08,10d,20,01

Main RAM 0x28BF08, 0x10D (269) bytes, first byte 20h and last byte 01h when
the table is valid. spuzboblj (the Japanese clone) has no entry, and the
game code differs (V2.04J against V2.05O), so it gets nothing.

## 1. Is it needed? Yes: the table lives in main RAM only

The core already saves the AT28C16 EEPROM (MRA `<nvram index="6"
size="2048"/>`, docs/m4_shell.md 9), and spuzbobl writes 44 bytes of it, so
the first question was whether those bytes hold the scores.

| Evidence | What it shows |
|---|---|
| MAME 0.288 zn.cpp 123 and 172: AT28C16 at 0x1FAF0000-0x1FAF07FF; taitogn.cpp's other non-volatile parts are the flash chips (firm, wave0 to 2, zoomprog), which the BIOS rebuilds from the card | the EEPROM, the flash chips and the PC card are the only places the game could keep anything |
| EEPROM contents after a cold boot and after 100 s of attract (sim/oracle/spuzbobl_cold200, i6_spb_bob in the main worktree): `TAITO_TG`, then 36 bytes of small values (`24 a2 07 00 4f 02 05 c3 11 12 ...`), rest FFh | 44 bytes of settings; no names, no scores. The RAM table is 269 bytes with names (BUB, ANJ, PCY, MAI, DEV) and scores (500000, 400000, ...) |
| docs/i9_nvram.md 2.4 (survey of the oracle runs): spuzbobl writes no card sectors | |
| tools/mame/hiscore_run.sh, play run: from the post-copy state, all ranking scores poked to 1 at 20 s, coin and play from 25 s, 420 s emulated | the game takes a ranking entry: 60 points, name ABC, in the RANKING VS CPU screen (snapshot 0044), written to the RAM table at 89.8 to 91.3 s. At the end of the run every MAME NVRAM file (at28c16, firm, wave0 to 2, zoomprog) and the CHD diff of the card are byte-identical to the ones the run started from |
| A boot from that end state | the table at 15 s is the default one again (BUB, 500000 first); no ABC |
| tools/mame/hiscore_run.sh wp (debugger watchpoints on the table's first and last byte, soft reset at 30 s) | the only writes are a clear at 12.13 s (PC 80038014, both bytes 00h) and the defaults at 14.74 s (PC 80073508 and 80073514); after the soft reset the same at 42.15 s and 44.76 s, that is 12.15 s and 14.76 s after the reset. Between the reset and the clear the old table stays in RAM, valid |

So the scores are lost at every power cycle on the board as in MAME, and
the EEPROM save does not keep them. A hiscore.dat module is needed.

One core detail that matters for the design: the core's reset zero fill
(rtl/gnet/cpu_split/cpu_reset_fill.vhd, FILL_RAM_WORDS 524288) clears the
first 2 MB of main RAM only. The table at 0x28BF08 is above it, so after an
OSD reset, or after loading the same game again (the SDRAM is not cleared
by a core load), the previous table is still in RAM, start and end bytes
valid, for about 12 s.

## 2. Design (rtl/gnet/gnet_hiscore.sv)

The standard module, rtl/gnet/hiscore.v (JimmyStones / alanswx
Hiscores_MiSTer, master 31789f3, version 0014), with two marked changes: a
clock enable `ce` on its state machine block, and the change mask size as a
parameter (HS_MASKBITS, upstream 256; the G-NET instance uses 8, as the MRA
block uses no mask, which saves about 300 ALMs). The wrapper adds what the
G-NET core needs around it. Its header gives the details; in short:

1. **Byte bridge.** hps_io is 16 bits wide here (WIDE=1); hiscore.v takes
   bytes. Config and dump words become two byte writes; upload words are two
   byte reads from hiscore.v's dump, with ioctl_wait holding Main meanwhile.
2. **One NVRAM file.** Main_MiSTer keeps one `<nvram>` per MRA
   (mra_loader.cpp 62-110), and it is already the EEPROM on index 6, so the
   dump goes in the same file (section 3).
3. **Game RAM port.** Main RAM is in SDRAM behind the CPU group's clock
   crossing. The wrapper reads and writes it on SDRAM channel 3 through the
   existing download crossing (PSX.sv ch3_cdc, zn2_ch3_arb port a), one
   32-bit word per request, with byte enables for writes, and holds
   hiscore.v (ce low) until the word is back. Writes, and the snapshot reads
   while the OSD is open, wait for psx_top's isPaused (synchronised to
   clk_1x); the wrapper's pause request goes into psx_top's pause only (not
   the audio mute, watchdog grace or coin timers). The start and end checks
   read while the game runs (two bytes every 1.9 ms during the boot).
4. **Fresh table.** Because of the 2 MB fill (section 1), a restore or a
   snapshot right after a reset could hit the old table. After each reset
   the table counts as fresh only after entry 0's start byte has been seen
   not matching (the game's clear) and then start and end matching again
   (its defaults). Until the clear has been seen, the start byte reads as a
   mismatch to hiscore.v's restore checks; until the table is fresh,
   hiscore.v does not see the OSD open, so it takes no snapshot. The wrapper
   polls the two bytes every 65,536 clocks until fresh; a restore also makes
   it fresh. A game that never clears its table is never restored and never
   saved, and its file is not overwritten.
5. **Save request.** hiscore.v asks for a save after a snapshot that found a
   change (autosave on). PSX.sv ORs that into the EEPROM's request. An
   upload that reaches the high score area while a snapshot is running waits
   for it, and that snapshot's own request is then dropped (the upload
   carries it).

Macro requirements (PSX.sv checks them): GNET_SHELL and GNET_ZN2 (index 6
NVRAM), GNET_CPU50 (the channel 3 crossing), GNET_LEAN (the CPU's turbo
data cache never holds main RAM, so a channel 3 write is seen at once). The
release revision has all four.

## 3. NVRAM file layout (index 6, 6,144 bytes)

| Bytes | Content |
|---|---|
| 0x000-0x7FF | EEPROM, as today |
| 0x800-0x9FF | zero (the card journal's directory on branch i9-nvram) |
| 0xA00-0xA03 | "GNHS" when the dump holds a table, else zero |
| 0xA04-0xC03 | hiscore dump, up to 512 bytes in hiscore.dat order (spuzbobl: 269) |
| 0xC04-0xFFF | zero |
| 0x1000-0x17FF | EEPROM again |

- The marker comes before the dump, so a load drops the dump bytes before
  they reach hiscore.v unless the marker is there.
- A 2 KB .nvm from today's releases arrives zero padded (Main loads the file
  into a zeroed buffer of nvram_size): EEPROM right, no marker, nothing
  restored (bench E).
- An older RBF given the new MRA loads the file wrapped on 2 KB (PSX.sv's
  EEPROM loader takes `ioctl_addr[10:0]`); the mirror, written last, leaves
  the right EEPROM. Its save writes the EEPROM three times; a newer RBF then
  finds no marker and restores nothing (bench E2).
- Compatible with the card journal (docs/i9_nvram.md 6.1, 268,288 bytes):
  the marker and dump sit in its zero padding at 0xA00 to 0xFFF, and both
  keep the EEPROM mirror in the last 2 KB. Merging the two branches needs
  one upload mux (the journal's cj_din for its words, this block's words
  for 0xA00 to 0xC03), both ioctl_wait terms, both requests, and one
  ee_sel; the PSX.sv hook points are the same lines.

## 4. MRA change (for the MRA generator in gnet-release; not made here)

spuzbobl only. Add, before the `<nvram>` line (Main sends `<rom>` entries in
file order and the `<nvram>` file when it reaches that tag; the config must
arrive first):

    <rom index="8" md5="none">
        <part>
            02 04 CC 00 FF FF 00 02 00 02 00 01 00 0F 10 00
            00 28 BF 08 01 0D 20 01
        </part>
    </rom>

and change its NVRAM line from `size="2048"` to:

    <nvram index="6" size="6144"/>

Header (16 bytes, hiscore.v format; clocks are clk_1x, 33,868,800 Hz):
START_WAIT 0204CC00h (1.0 s after the reset ends, before the game's clear
at about 12 s, so the clear is seen), CHECK_WAIT FFFFh (1.9 ms between
checks), CHECK_HOLD 2, WRITE_HOLD 2, WRITE_REPEATCOUNT 1, WRITE_REPEATWAIT
000Fh, ACCESS_PAUSEPAD 10h, change mask length 0. Entry (2-byte length
format, CFG_LENGTHWIDTH 2, as 0x10D does not fit in one byte): address
0028BF08h, length 010Dh, start 20h, end 01h. Index 8 is free in this core
(0 BIOS, 1 PS-X EXE, 2 keys, 3 flash, 4 card metadata, 5 card, 6 NVRAM, 7
game configuration, 251, 254 DIP switches, 255); index 3, the usual
hiscore index on other arcade cores, is the flash images here. An RBF
without GNET_HISCORE ignores index 8.

Every other set keeps `size="2048"` and no index 8 block; with the macro
and no block the core behaves as without it (bench A, the 2 KB file is
byte-identical between the builds).

## 5. Simulation (sim/hiscore/run.sh)

Bench tb_hs.sv with sys/hps_io.sv, PSX.sv's own declarations, loader, save
request, instance and channel 3 path (copied by gen_glue.py), cdc_handshake
and zn2_ch3_arb (GHDL to Verilog), the wrapper and hiscore.v. Models: Main's
word handshake with random HPS latency (load, save, MENU_SAVE_CHECK),
sys_top's acknowledge, zn2_io's EEPROM copy, SDRAM channel 3 with random
latency and random flash reads on arbiter port b, the DDR3 mirror stall at
random, psx_top's pause (isPaused after a random wait), and the game
(clear at 3 ms and defaults at 8 ms after each reset, scaled from 12.15 s
and 14.76 s; score changes when the bench says). Results 2026-10-21:

| Run | Result |
|---|---|
| without GNET_HISCORE | PASS, 5 checks (A) |
| with, main sequence | PASS, 31 checks (A to D, F) |
| with, +old | PASS, 11 checks (A, E, E2) |
| A EEPROM-only MRA | 2 KB file byte-identical between the two builds; no channel 3 access |
| B first run, no .nvm | no save before the game's own table (OSD opened during the boot with random RAM); a score saved; file = EEPROM, zero, marker, dump equal to the RAM table, zero, EEPROM mirror; no repeat save |
| C reload, the SDRAM holding a newer unsaved table with valid start and end bytes | restore only after the game's defaults (never into the old table), RAM equals the saved table, 269 writes, none while the game ran, none outside the table; a new top score (start byte no longer 20h) saved |
| D OSD reset | restored again after the defaults, including the table whose start byte is not 20h |
| E, E2 | 2 KB file and older RBF's repeated-EEPROM file: no dump taken, nothing restored, a later score saved with the new layout |
| F EEPROM write and a score at one OSD open, the core taking 3 ms to pause | saved at once by the EEPROM's request; the upload waited 23,433 clocks at the marker for the snapshot, so the same save holds the new score; no repeat save |

Negative controls (mutants.py, each must FAIL, all do): no reset gate (C:
restored before the clear), no fresh-table condition (B: junk snapshot), no
pause wait for writes (C: writes while the game ran), no marker check (E:
zero dump restored), no request suppression (B: repeat save), all byte
enables on writes (C: table wrong), no upload hold at the high score area
(F: stale dump in the save).

Not covered: the real sdram.sv (the channel 3 byte lanes are those of the
downloads and upstream's cheat engine, little-endian, be[0] = lowest
address), the real psx_top pause, and the full system. A full-system run
of spuzbobl to its table (about 15 s of game time after a warm boot) would
take hours in sim/fullsys; I did not run it.

Save request timing: in the bench the request comes about 114 us after the
OSD opens (pause entry up to 60 us plus 68 word reads). Main_MiSTer reads
the request once, two menu passes after it shows the OSD (menu.cpp
MENU_NONE2, MENU_GENERIC_MAIN1, MENU_SAVE_CHECK); a request that comes later
is kept by hps_io and saved at the next OSD open. Whether the first or the
second OSD open saves depends on that timing on hardware.

## 6. Cost

Estimate from yosys synth_intel_alm (Cyclone V) of the wrapper with
hiscore.v, RAMs as black boxes: 1,126 LUTs and 280 arithmetic cells, 640
registers, which packs to roughly 700 to 900 ALMs; plus 2 M10K (dump and
snapshot buffer, 512 x 8 each) and four small config tables (4 entries).
Quartus usually maps tighter than yosys; the real figure needs a
GNET_Z1FULLH build. The PSX.sv glue adds a few muxes on channel 3 and the
hps_io wait and data paths. At 87% (36,324 of 41,910 ALMs in the last
GNET_Z1FULLR fits) this would take the core to about 89%.

## 7. Hardware test

1. Build GNET_Z1FULLH (tools/pc_build.sh target z1fullh) and copy the
   spuzbobl MRA with the section 4 change.
2. Delete config/nvram/<MRA name>.nvm if it exists. Load, play until a
   score enters a ranking, open the OSD (once or twice). Expect
   "Saving..." and a 6,144-byte .nvm.
3. Power cycle (or load another core, then spuzbobl again). Wait about 15 s
   into the attract: the ranking shows the saved score.
4. OSD Reset during the attract: after the boot the ranking still shows it.
5. Load a different G-NET game: its 2 KB EEPROM save works as before.

## 8. Open questions

1. Autosave is always on (no OSD option): a changed table is saved at the
   next OSD open, with Main's "Saving..." message. Other arcade cores offer
   "Autosave Hiscores" on and off.
2. Merge with the card journal branch (section 3) if both are wanted in one
   release.
3. An upload that reaches the high score area while a snapshot runs waits
   for the snapshot, which waits for the core to pause. If psx_top never
   reached isPaused, Main would wait with it; the OSD pause relies on the
   same psx_top pause, so I have not added a time limit.
4. START_WAIT and the poll rely on the game clearing its table about 12 s
   after a reset (MAME). If the board's boot is much slower or faster this
   still works (the gate waits for the clear, however late), but a table
   that is never cleared is never restored.
