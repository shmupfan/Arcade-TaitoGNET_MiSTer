# G-NET target games: test matrix and hardware checklist

Status: 2026-10-05. Purpose: everything needed to test all five target
games on the MiSTer once the boot fix (docs/zn2_layer_design.md 18.5, on
branch zn2-layer) is in an RBF, not only Shikigami.

Sources: MAME 0.288 (`mame -listxml <set>` on the Mac, and
[MAME 0.288 taitogn.cpp](https://github.com/mamedev/mame/blob/mame0288/src/mame/sony/taitogn.cpp), cited as `gn:<line>`), the card images
in `sim/cards/` (from `tools/extract_card.sh`), and MAME runs I made for
this document (section 4). Game data, NVRAM and snapshots stay in
gitignored folders (`gnet_games/`, `sim/`); nothing here is game data.

## 1. Test matrix

All five are parent sets with `romof="coh3002t"` (no clone parent), on
the ZN-2 G-NET board with a Type 1 PC card. MAME marks all five as
emulation good, graphics and sound imperfect.

| | Ray Crisis | Psyvariar Medium Unit | XII Stag | Shikigami no Shiro | Night Raid |
|---|---|---|---|---|---|
| Set / parent | raycris / none | psyvaria / none | xiistag / none | shikigam / none | nightrai / none |
| MAME title (gn line) | Ray Crisis (V2.03O 1998/11/15 15:43) (1355) | Psyvariar -Medium Unit- (V2.02O 2000/02/22 13:00) (1371) | XII Stag (V2.01J 2002/6/26 22:27) (1391) | Shikigami no Shiro (V2.03J 2001/08/07 18:11) (1363) | Night Raid (V2.03J 2001/02/26 17:00) (1387) |
| Year, maker | 1998 Taito | 2000 Success | 2002 Triangle Service | 2001 Alfa System / Taito | 2001 Takumi |
| Driver class | taitogn_state | ttgncl4_state | taitogn_state | taitogn_state | ttgncl4_state |
| Rotation | ROT0 (horizontal) | ROT270 (vertical) | ROT270 (vertical) | ROT270 (vertical) | ROT0 (horizontal) |
| Video modes seen (MAME, before rotation) | 320, 256, 512, 640 x 240 | 320 x 240 | 320 x 240 | 320 x 240 | 320, 256 x 240 |
| Inputs | 2P, 8-way stick, 3 buttons each | same | same | same | same |
| Also on the inputs | Start 1/2, Coin 1/2, Service, Tilt, Test (S551:4) | same | same | same | same |
| Buttons the attract shows | not shown in 60 s | not shown in 60 s | A (shot) on the how-to screen | A, B on the how-to screen | A, B, C on the tutorial |
| Special controls | none | none | none | none | none |
| DIP defaults (S551, MRA `default="0F"`) | all Off | all Off | all Off | all Off | all Off |
| JP1 BIOS Flash | Off (0) | Off (0) | Off (0) | Off (0) | Off (0) |
| BIOS image | v1 (no default given; JP1 Off, so the EPROM is not used) | same | same | same | same |
| Card slot | taitopccard1 (T1) | T1 | T1 | T1 | T1 |
| Card CHD SHA1 | 9d255710c87c3286542d357820d828807cc6ca07 | 3c7fca5180356190a8bf94b22a847fdd2e6a4e13 | 586e37c8d926293b2bd928e5f0d693910cfb05a2 | fa49a0bc47f5cb7c30d7e49e2c3696b21bafb840 | 74d0458f851cbcf10453c5cc4c47bb4388244cdf |
| Card image | 40,960,000 bytes | same | same | same | same |
| Card key (5 bytes) | from the CHD metadata | from the CHD metadata | same as Shikigami and Night Raid | same as XII Stag and Night Raid | same as XII Stag and Shikigami |
| SYSTEM.INF area | O | O | J | J | J |
| gameprog (SYSTEM.INF) | ray.sdh (compressed) | main.bin | game.bin | main.bin | fire.bin |
| Flash chips filled by the first-boot copy | U30 firm, U27 zoomprog, U56/U55/U29 wave0 to 2 | all five | U30, U27, U56 (wave0 only; wave1 and 2 stay erased) | all five | all five |
| U30 program words written (MAME cold run) | 525,458 | 197,778 | 394,386 | 525,458 | 361,618 |
| MAME first-boot copy (emulated s) | 2.86 to 140.6 | 2.86 to 127.3 | 2.86 to 125.9 | 2.86 to 142.1 | 2.86 to 136.1 |
| Zoom (MN10200 + DSP) | yes, DSP A | yes, DSP A + B | yes, DSP A | yes, DSP A | yes, DSP A |
| CHD on the Mac | roms/raycris | roms/psyvaria | roms/xiistag | roms/shikigam | roms/nightrai |

Notes:

- Inputs: every set uses input `taitogn` (gn:912 to 918), which is `zn`
  reduced to two players and three buttons (`zn2p`, gn:877 to 897) plus
  S551:4 Test Mode (`znt2p`, gn:899 to 906). S551:2 is the BIOS Service
  Mode (gn:861 to 863). S551:1 and S551:3 are unknown. All DIPs are active
  low, so Off = 1 and the default byte is 0Fh, which is what the MRAs use.
- The listxml `<display>` is 640 x 480 for every set; that is the MAME
  screen maximum, not the mode the game uses. The modes in the table are
  the snapshot sizes from my runs (docs/gnet_set_survey.md has the GPU
  traces).
- Button use: MAME gives no button names. The "attract shows" row is only
  what the how-to or tutorial screens displayed in my runs.
- Region is the card's SYSTEM.INF `area` letter, not a driver setting
  (docs/gnet_set_survey.md 1). XII Stag, Shikigami and Night Raid show
  "for use in Japan only" notices; that is correct.
- XII Stag, Shikigami and Night Raid share the same card key.

## 2. Test package (gnet_games/test_z1, gitignored)

Built 2026-10-05 with `tools/gnet/make_game_zip.py <set> roms/coh3002t.zip
gnet_games/test_z1/games/mame --card-dir sim/cards --warm` (the tool is on
branch zn2-layer), exactly as the Ray Crisis and Shikigami zips were made.

| File | Size | Contents |
|---|---|---|
| games/mame/coh3002t.zip | 0.8 MB | BIOS, CAT702 keys, flash.u30 (existing) |
| games/mame/gnet_raycris.zip | 28.5 MB | existing |
| games/mame/gnet_psyvaria.zip | 28.9 MB | new |
| games/mame/gnet_xiistag.zip | 24.5 MB | new |
| games/mame/gnet_shikigam.zip | 34.0 MB | existing |
| games/mame/gnet_nightrai.zip | 31.4 MB | new |

Each game zip holds `<set>.img` (card), `<set>.meta` (IDNT, CIS, key) and
`<set>.flash` (warm-boot flash area). MRAs, four per game, named
`<Game> (G-NET silent test, cold|warm boot).mra` (rbf `gnet_z1`) and
`<Game> (G-NET 50 MHz test, cold|warm boot).mra` (rbf `gnet_z1c50`). New
in this round: Psyvariar Medium Unit, XII Stag and Night Raid (all four
each) and the two Ray Crisis 50 MHz MRAs, which did not exist yet. The
new MRAs are the Shikigami and Ray Crisis files with only the game fields
changed (name, setname, year, manufacturer, rotation, zip and part names).

Checks done:

- `tools/gnet/check_test_package.py gnet_games/test_z1`: all 23 MRAs parse,
  every named part is in its zip (with matching CRC where the MRA has
  one), each ioctl index gets the size docs/zn2_layer_design.md 13.5
  expects, and both RBF names have a core in `_Arcade/cores`. I also
  checked that the script fails on a missing part, a wrong CRC, a short
  repeat fill, a missing core and broken XML.
- For all five zips, each region of `<set>.flash` (firm, zoomprog, wave0
  to 2) equals the byte-swapped MAME NVRAM after the first-boot copy
  (`sim/oracle/<set>_cold300` or `raycris_cold200`), 0x280000 to 0x3FFFFF
  is FFh, `<set>.img` equals `sim/cards/<set>.img`, and `<set>.meta`
  holds the IDNT, CIS and key from `sim/cards/`.
  `tools/build_flash.py --check` against the same NVRAM also reports
  IDENTICAL for psyvaria, xiistag and nightrai.

Added later the same day: psyvarrv (Psyvariar -Revision- V2.04J
2000/08/11, ROT270, class ttgncl4, T1 card), gnet_psyvarrv.zip (27.7 MB)
and four MRAs named `Psyvariar Revision (...)`. Its flash image is
IDENTICAL to MAME's post-copy NVRAM (`build_flash.py --check` against
`sim/oracle/psyvarrv_cold300`), and the package check passes all 27 MRAs.
I have not made a MAME screen sequence for it; expect the same flow as
Psyvariar Medium Unit.

## 3. Expected timings and the two RBFs

All times below are MAME 0.288 emulated seconds from power on, to about
1 s (one snapshot per second for warm boots, one per 10 s for cold
boots). MAME's ZN-2 CPU runs at 1.476 times the PS1 rate
(docs/zn2_layer_design.md 13.7), which is about 50 MHz. So:

- `gnet_z1c50` (50 MHz CPU) should come closest to these times.
- `gnet_z1` (33.87 MHz, PS1 rate) runs CPU-bound parts slower: the
  install screen and the cold-boot copy take longer, up to about 1.5
  times. Video timing is the same in both.
- On the PCB the CPU measures 0.82 of MAME's rate (docs/r1_speed_study.md),
  so neither MAME nor the core is the PCB reference for timing.

The silent RBF has no rotation: the three vertical games (Psyvariar, XII
Stag, Shikigami) appear on their side on a horizontal monitor. The BIOS
screens (G-NET logo, install and "prepare" screens) are drawn horizontally
by the BIOS for every game and read normally; only the game's own screens
are sideways, with the game's top edge on the right of the screen
(ROT270). The MRAs carry `vertical (ccw)` for when rotation is added.

## 4. Hardware checklist per game

How I captured this: one MAME process at a time under `nice -n 15`, using
`tools/mame/oracle_run.sh <set> 60 sim/oracle/games_<set>_warm60` with
`ORACLE_SNAP_EVERY=60` and `ORACLE_COIN_AT=40` (coin at 40 s, start at
42 s, then fire held with left/right movement), starting from the five
post-copy flash images only: no EEPROM file and an unmodified card, which
is what a first warm-boot MRA load gives the core. Cold-boot sequences
come from the earlier 300 s cold runs (`sim/oracle/<set>_cold300`,
`raycris_cold200`; coin at 180 s in the 300 s runs, no coin in
raycris_cold200). Snapshots are in `sim/oracle/games_<set>_warm60/snap/`.

Common to all games, first 3 s of every boot (cold or warm):

1. 0 to 2 s: white "TAITO G-NET" logo, "(C) TAITO CORPORATION 1998 ALL
   RIGHTS RESERVED".
2. From about 3 s: the game's BIOS install screen (game logo, set name,
   version, a progress bar). Warm boot: a short "prepare to start" bar
   that reaches COMPLETE. Cold boot: "Loading now." (or the Japanese
   equivalent) with a red "do not turn off the power or remove the card"
   warning, for about 2 minutes or more.

Failure screens to report (with a photo):

- "CanNotFindProgramRom / ERROR B930": U30 header not read (the bug fixed
  in docs/zn2_layer_design.md 18.5). If this still appears with the fixed
  RBF, the fix is not in that build or the flash read path has another fault.
- "SYSTEM ERROR" after the logo: correct only for the BIOS no-card MRA.
  With a game MRA the BIOS did not get a usable card; card detection or
  the unlock are the first things to check (MAME shows this screen with
  no card).
- Logo repeating about every 5 s: watchdog reset loop.
- Stuck on the progress bar with no movement for more than 30 s (warm) or
  5 minutes (cold): note the bar position.

### 4.1 Ray Crisis (raycris, horizontal)

Warm boot (MAME):

| Time | Screen |
|---|---|
| 0 to 2 s | G-NET logo |
| 3 to 15 s | RAYCRISIS VER 2.030, "Prepares the start.", blue bar filling, red/white blinking "WARNING! DON'T INSERT COIN" at the bottom; bar shows COMPLETE at about 14 s. Ray Crisis is the only one of the five whose warm prepare bar takes about 12 s |
| 16 to 18 s | black (256 x 240) |
| 19 to 20 s | NOTICE text, 640 x 240 (high resolution, small text) |
| 21 to 22 s | blue TAITO logo, fading out (512 x 240) |
| 23 s | "Con-Human" |
| 24 s onwards | intro: green text, "NEURO COMPUTER", "ENCROACHMENT nn%" counters, "DIVE INTO THE NETWORK", ship close-ups "WR-01R", "CYBERNETICS LINK" girl |
| after coin | "PUSH START BUTTON TO START", CREDIT 1 (512 x 240) |
| after start | ENTRY CODE screen with a 30 s time limit counting down; MAME was still on it at 60 s |

Cold boot (MAME): "Loading now." with the power warning from about 3 s to
about 141 s, "Prepares the start." at about 150 s, TAITO logo at about
160 s, then the intro. The red full-screen "ALERT" and tiled "ERROR ERROR"
frames at about 187 to 191 s are part of the intro, not a fault; the
RAYCRISIS title follows at about 198 s.

Test steps: warm boot first; at the intro, coin (Select) then Start; at
ENTRY CODE wait out the timer or press a button, to reach play.

### 4.2 Psyvariar Medium Unit (psyvaria, vertical)

Warm boot (MAME):

| Time | Screen |
|---|---|
| 0 to 2 s | G-NET logo |
| 3 to 4 s | PSYVARIAR VER 2.020 "Prepares the start.", COMPLETE already at 3 s |
| 5 to 9 s | black |
| 10 to 15 s | NOTICE text over a star field |
| 16 s | black |
| 17 s onwards | "Prologue": story text scrolling over 3D scenes (A.D.2123 to A.D.2167) |
| after coin | ship close-up, "PRESS START BUTTON", CREDIT 1 |
| after start | white flash, "AREA 1 EARTH", play starts within about 4 s of Start |

Cold boot (MAME): "Loading now." from about 3 s to about 127 s, "Prepares
the start." COMPLETE at about 130 s, NOTICE at about 140 s, Prologue from
about 150 s. After a coin at 180 s: play at 190 s, CONTINUE countdown at
about 220 s, GAME OVER, TOTAL RESULT name entry, TOP PSYVARIARS table.

Test steps: warm boot; coin and Start during the Prologue; check the play
field scrolls and the ship moves.

### 4.3 XII Stag (xiistag, vertical)

Warm boot (MAME):

| Time | Screen |
|---|---|
| 0 to 2 s | G-NET logo |
| 3 to 5 s | XIISTAG VER 2.01J, Japanese "preparing to start" text and bar; COMPLETE at about 4 s; red Japanese "do not insert coin yet" line |
| 6 to 8 s | black |
| 9 to 13 s | NOTICE "This video game is for use in Japan only" |
| 14 to 17 s | TAITO logo on grey, fading |
| 18 to 21 s | "Triangle Service" logo in katakana on white |
| 22 to 26 s | black, then a white flash and a glowing blue sphere |
| 27 to 40 s | XII STAG title over the sphere, "(C)2002 TRIANGLE SERVICE" |
| after coin | "PRESS START BUTTON TO START", CREDIT 1 |
| after start | black, then the how-to screen (A button attack, "PRESS BUTTON TO SKIP"), black, play over clouds at about 7 s after Start |

Cold boot (MAME): Japanese loading screen (bar plus red power and card
warning) from about 3 s to about 126 s, black at 130 s, TAITO logo at
about 140 s, title at about 150 to 160 s, a demo with a joystick hint at
170 s. After a coin at 180 s: play from about 190 s, a large boss at about
230 s, CONTINUE, then the ranking table.

Note: XII Stag uses only wave0 (U56). U55 and U29 stay erased in MAME and
in the zip; that is correct.

### 4.4 Shikigami no Shiro (shikigam, vertical)

Warm boot (MAME):

| Time | Screen |
|---|---|
| 0 to 2 s | G-NET logo |
| 3 to 5 s | SHIKIGAMINOSHIRO VER 2.03J, Japanese "preparing to start" bar, COMPLETE at about 4 s |
| 6 to 7 s | black |
| 8 to 10 s | NOTICE ("for use in Japan only") on a brown background |
| 11 to 13 s | TAITO logo fading in on white |
| 14 to 19 s | white, then "Alfa System presents" |
| 20 to 40 s | black, then a night city with Japanese story text |
| after coin | blue hexagon pattern, "Press start button to start", CREDIT 1 |
| after start | Character Select with a 15 s timer, then "How to play" (A and B buttons, "WAIT A MOMENT", press Start to skip). MAME was still on How to play at 60 s |

Cold boot (MAME): Japanese loading screen from about 3 s to about 142 s,
NOTICE at about 150 s, Alfa System at about 160 s, story text at 170 s.
After a coin at 180 s: How to play from about 190 s to about 240 s, a
date card, a character portrait, then play from about 260 s.

Test steps: warm boot; coin, Start, pick a character, press Start on How
to play to skip it.

### 4.5 Night Raid (nightrai, horizontal)

Warm boot (MAME):

| Time | Screen |
|---|---|
| 0 to 2 s | G-NET logo |
| 3 to 5 s | "night raid" NIGHT RAID VER 2.03J, Japanese "preparing to start" bar, COMPLETE at about 4 s, red Japanese coin warning |
| 6 to 8 s | black, then white (256 x 240) |
| 9 to 11 s | NOTICE ("for use in Japan only"), blue text |
| 12 to 16 s | purple cave fly-through |
| 17 to 29 s | "THE BEST HOT PLAYERS" table over 3D scenes |
| 30 s | NIGHT RAID logo forming, a red craft |
| 31 to 40 s | "THE BEST COOL PLAYERS" table |
| after coin | NIGHT RAID title, "PRESS START BUTTON TO START", TAKUMI logo, CREDIT 1 |
| after start | TUTORIAL (stick, A, B, C buttons, Japanese text, "PRESS START BUTTON TO SKIP"); MAME was still in the tutorial at 60 s |

Cold boot (MAME): Japanese loading screen from about 3 s to about 135 s,
black at 140 s, cave intro at 150 s, score tables at 160 to 170 s. After a
coin at 180 s: title, tutorial from about 190 s, play from about 230 s.

Test steps: warm boot; coin, Start, then Start again to skip the tutorial.

## 5. Suggested order on hardware

1. BIOS no-card MRA (SYSTEM ERROR expected), as before.
2. Warm boots of all five games with `gnet_z1` (each should show its
   COMPLETE bar within about 15 s and its NOTICE screen within about 20 s).
3. The same with `gnet_z1c50`, noting whether each step comes sooner.
4. One cold boot (XII Stag has the shortest copy in MAME, about 126 s)
   to check the install path end to end.

Report per game: the last screen reached, the time to it, and a photo of
anything that differs from the tables above.
