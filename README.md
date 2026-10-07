# Taito G-NET - MiSTer FPGA Core (alpha)

A MiSTer core for Taito G-NET: Sony's ZN-2 main board (a PlayStation
derived arcade board) with Taito's FC PCB on top, which carries the
Taito Zoom sound board, five flash chips and the PC card slot the games
are sold on. The core is built on Robert Peip's PSX_MiSTer. I wrote the
ZN-2 board layer, the G-NET glue (flash, PC card, watchdog) and the Taito
Zoom sound board (MN10200, ZSG-2, TMS57002) for this core.

<img src="docs/images/raycris.png" width="26%" alt="Ray Crisis"> <img src="docs/images/psyvarrv.png" width="15%" alt="Psyvariar -Revision-"> <img src="docs/images/shikigam.png" width="15%" alt="Shikigami no Shiro"> <img src="docs/images/nightrai.png" width="26%" alt="Night Raid"> <img src="docs/images/xiistag.png" width="15%" alt="XII Stag">

*Screenshots taken on a MiSTer with this core.*

**Status: alpha.** All five target games boot and play in full-system
simulation, and on my MiSTer Shikigami no Shiro and Psyvariar run with the
Zoom music and the sound effects. On 2026-10-06 I played
Psyvariar -Revision- to the end on a DE10-Nano with the first alpha RBF
(`Arcade-TaitoGNET_20261006.rbf`, md5 e7d7995e); the sound and gameplay
were both good. On the same day I played Night Raid, Ray Crisis (V2.03J)
and Chaos Heat on test builds of this core. The current RBF
(`Arcade-TaitoGNET_20261007.rbf`, md5 3713d5df) adds the Type 2 and
CompactFlash cards, the no Zoom board setting and the mahjong and RC
controls, and sets the SFX Level default back to MAME's 0.3; the play
reports above are from the earlier builds. The other games, the
first-boot copy and several shell features still need testing on real
hardware, and some timings are known to differ from the real board (see
Known issues). I am
publishing it now to get test reports, especially from people who own a
G-NET board. How to help: [docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md).

The research behind the core, with the evidence for each subsystem and
every known difference from MAME and from the real board, is in
[docs/ACCURACY.md](docs/ACCURACY.md).

## Supported games

The games come in three batches. Only batch 1 is tested. Batches 2 and 3
share the same hardware paths in the core, but have had little or no
testing on hardware, so expect bugs. The full table, with each set's card
type, game configuration byte, zip name and test status, is in
[releases/README.md](releases/README.md).

| Batch | Folder | Games | Status |
|---|---|---|---|
| 1 | `releases/` | Ray Crisis (V2.03O and V2.03J), Chaos Heat (V2.09O), Psyvariar -Medium Unit- (V2.02O), Psyvariar -Revision-, XII Stag, Shikigami no Shiro, Night Raid | Tested: played on my MiSTer, except Ray Crisis (V2.03O) and XII Stag, which boot but I have not played yet |
| 2 | `releases/_Taito G-NET batch 2 (boots)/` | Chaos Heat (V2.08J), Psyvariar -Medium Unit- (V2.04J), Shikigami no Shiro internal build, Flip Maze, Kollon (Type 1 card), Shanghai Shoryu Sairin, Soutenryu, Shanghai Sangokuhai Tougi, Otenki Kororin | Boot to their title or attract screen on my MiSTer; Psyvariar (V2.04J) and the Shikigami internal build not yet tried. Expect bugs |
| 3 | `releases/_Taito G-NET batch 3 (new features)/` | Otenami Haiken, Zoku Otenamihaiken (both versions), Zooo, Space Invaders Anniversary, Otenami Haiken Final, Super Puzzle Bobble (both versions), Kollon (CompactFlash), Go By RC, RC De Go, Mahjong Oh, Usagi | New core features (no Zoom board, Type 2 and CompactFlash cards, mahjong and RC controls). Each set booted on my MiSTer with this RBF on 2026-10-07 except Zoku Otenamihaiken (V2.05J), whose card I do not have; not played yet. Expect bugs |

All of them use the `coh3002t` BIOS and the FC PCB. Not supported:
Mawasunda, which runs on the ZN-1 G-NET board (`coh1002t`), and the 2011
conversions of G-Darius, Ray Storm, Aero Fighters Special, Brave Blade
and others, which boot from a modified BIOS on a plain card.

## Roadmap

| Stage | Games | What each needs |
|---|---|---|
| Batch 1 (this release) | The shooters above | Done; test reports wanted |
| Batch 2 (this release) | Other Type 1 card games and versions | Play testing on hardware, and a look at the interrupt quirk MAME works around for Kollon (V2.04JA) |
| Batch 3 (this release) | No Zoom board, Type 2 and CompactFlash cards, special controls | A first hardware test of each new feature, the same interrupt quirk for Space Invaders Anniversary, and whether the CompactFlash games need the sub-BIOS that MAME's BIOS flasher writes |
| Later | The 2011 conversions on plain cards: G-Darius, Ray Storm, Aero Fighters Special, Brave Blade, Flame Gunner, Fighters' Impact, Shanghai Matekibuyuu, The Block Kuzushi | The modified BIOS they boot from, MRAs |
| Later | Mawasunda | The ZN-1 board and its G-NET BIOS, and its two handles |

## What works

- In full-system simulation of the core, Ray Crisis, Psyvariar -Medium
  Unit-, XII Stag, Shikigami no Shiro and Night Raid boot from power-on
  through the BIOS, the card unlock and the loader to their attract mode,
  and their screens match MAME's for the first 30 seconds, in the same
  order, a little later than MAME (see Known issues). On my MiSTer,
  Shikigami no Shiro and Psyvariar play with sound.
- Taito Zoom music and effects (MN10200, ZSG-2, TMS57002), checked
  against MAME instruction by instruction and sample by sample.
- PlayStation SPU sound, mixed with the Zoom output.
- The BIOS's first-boot install (it copies the card into the flash
  chips), or a quick start that loads the flash as the BIOS leaves it.
- Vertical games: rotation for HDMI, Flip Screen for a rotated monitor.
- The board's EEPROM (settings and high scores) saved as NVRAM; a check
  across a power cycle on hardware is still open.
- The MB3773 watchdog, so a hung game resets as on the board.

## Installation

You need your own MAME 0.288 files. No BIOS, card, flash or game data is
included in this repository.

1. Copy `releases/Arcade-TaitoGNET_20261007.rbf` to
   `/media/fat/_Arcade/cores/`, and the rest of `releases/` (the MRA
   files and the `_alternatives` and batch folders, as they are laid
   out) to `/media/fat/_Arcade/`.
2. Copy your `coh3002t.zip` (the G-NET BIOS set, MAME 0.288) to
   `/media/fat/games/mame/`.
3. MiSTer cannot read MAME's hard-disk CHD files, so each game's card is
   converted once on a computer. With Python 3 and MAME's `chdman`:

   ```
   python3 tools/gnet/gnet_tester_zips.py --roms <your MAME roms folder> --out <a new folder>
   ```

   The roms folder holds `coh3002t.zip` and each game's CHD in its MAME
   folder, for example `shikigam/shikigam.chd`. On Windows use `python`
   instead of `python3`; if `chdman` is not on your PATH, add
   `--chdman <path to chdman.exe>`. The tool checks that `coh3002t.zip`
   is the MAME 0.288 version and warns if a CHD does not match MAME 0.288.
   It writes one `gnet_<set>.zip` per game it finds, holding the card
   image (38.6 MB to 64.2 MB depending on the card), the card's identify
   data, CIS, unlock key and card type, and the flash chips as the BIOS
   leaves them after its first-boot copy.
   These zips are made from your own files: keep them to yourself.
4. Copy every `gnet_<set>.zip` to `/media/fat/games/mame/`.

There are two MRAs per game:

- **`<Game>.mra`**, the main MRA, loads the flash as the BIOS leaves it
  after its first-boot copy, so the game starts in a few seconds.
- **`_alternatives/_<Game>/<Game> (first boot).mra`** (in each batch
  folder) starts like a real
  board after a card swap: the BIOS copies the card into the flash chips
  (about 2.5 minutes), then the game starts. The flash is not kept
  between loads, so the copy runs every time. Do not reset or power off
  during it.

### MRA layout

For anyone writing MRAs for this core:

| ioctl index | Content | Source |
|---|---|---|
| 0 | BIOS `m534002c-60.ic353` (512 KB) | coh3002t.zip |
| 2 | CAT702 keys `tt10.ic652`, `tt16.u17` | coh3002t.zip |
| 3 | flash area, 10 MB: U30 sub-BIOS, U27 Zoom program, U56/U55/U29 wave data | `<set>.flash` from the game zip (main MRA), or `flash.u30` plus 8 MB of FFh (first boot MRA) |
| 4 | card identify data, CIS, key and card type at 3F0h (01 Type 1, 02 Type 2, 03 CompactFlash) (1 KB) | `<set>.meta` from the game zip |
| 5 | PC card image (whole sectors, up to 64 MB) | `<set>.img` from the game zip |
| 6 | EEPROM (2 KB), `<nvram index="6" size="2048"/>` | saved by MiSTer |
| 7 | game configuration byte: bit 0 vertical set (MAME ROT270), bit 1 no Taito Zoom board (MAME `init_nozoom`), bits 3:2 controls (0 stick, 1 mahjong panel and P1 stick, 2 mahjong panel, 3 RC wheel and trigger) | inline in the MRA |
| 254 | bits 3-0 DIP switch S551, bit 4 JP1 (kept open, see releases/README.md) | MRA switches |

## Controls

Two players, an 8-way stick and three buttons each, plus Start, Coin,
Service, Test and Pause. MAME gives no button names for these games and I
have not found the game manuals, so the buttons are Button 1 to 3.

| Function | Joypad (default) | Keyboard, player 1 | Keyboard, player 2 |
|---|---|---|---|
| Buttons 1, 2, 3 | A, B, X | Left Ctrl, Left Alt, Space | A, S, Q |
| Start | Start | 1 | 2 |
| Coin | Select | 5 | 6 |
| Service | L | 9 | |
| Test | R | F2 | |
| Pause | map it in the OSD | P | |

Movement is the stick or D-pad, the arrow keys for player 1, and R, F, D,
G for player 2. The keyboard keys are MAME's defaults.

Batch 3 has two other control types, as MAME 0.288 maps them:

- **Mahjong panel** (Mahjong Oh, Usagi), on the keyboard with MAME's
  default keys: A to N for the tiles, Left Ctrl Kan, Left Alt Pon, Space
  Chi, Left Shift Reach, Z Ron, 1 Start. Mahjong Oh also keeps the player
  1 stick and buttons; Usagi has neither.
- **RC wheel and trigger** (Go By RC, RC De Go), one player: the analog
  stick's X axis or a paddle steers, the stick's Y axis is the trigger;
  the D-pad or arrow keys give full deflection. On a first boot (fresh
  EEPROM) Go By RC stops on its CALIBRATION screen, as it does in MAME:
  leave the stick centred and press Start; the game saves the calibration
  to the EEPROM.

## OSD options

- **Aspect ratio** and **Scale** (HDMI): Original is 4:3 for the area the
  game draws, as an arcade monitor adjusted to fill the tube shows it.
  There is no 216p crop: the games use 240 lines, and a 216-line crop
  would cut part of the picture.
- **Orientation** and **Rotate Direction** (vertical games, HDMI): stand
  the picture upright on a horizontal screen.
- **Flip Screen** (vertical games): turns the picture 180 degrees in the
  video output, for a monitor rotated the other way. It works on a CRT as
  well as over HDMI.
- **Scandoubler Fx**: HQ2x or CRT scanlines for 31 kHz output.
- **CRT H Position** and **CRT V Position**: move the picture in 2 pixel
  steps (-16 to +14) and whole lines (-4 to +3). Only the sync pulses
  move; the picture and the game's timing stay as they are, and a change
  takes effect at the next frame. Vertical sync starts and ends on a
  horizontal sync edge, so a CRT gets a clean composite sync.
- **Pause when OSD is open**, plus the Pause button and the P key.
- **Volume**: Normal, +6 dB, -6 dB, -12 dB.
- **SFX Level**: the PlayStation SPU's
  level in the mix against the Zoom board: 0.3 (MAME's setting, the
  default), 0.45, 0.6, 0.9, 1.2, 1.5. The right level on a real board is
  not settled ([docs/ACCURACY.md](docs/ACCURACY.md), SPU).
- **DIP switches**: S551. Switch 4 is Test Mode (the operator manual says
  to use switch 4 only); switch 2 is the BIOS service mode in MAME;
  switches 1 and 3 are unknown. Leave them off for normal play.
- **Watchdog**: leave it On. It resets a game that stops running, as the
  board's MB3773 does. Off is for debugging.
- **Debug overlay**: a small box of hex numbers with the board state, for
  test reports ([docs/TESTING_GUIDE.md](docs/TESTING_GUIDE.md)).

The screen stays black, with sync running, while the MRA loads and while
the core resets, so a CRT or a direct video DAC keeps its picture. The
pixel clock is an exact division of the 53.693175 MHz video clock in
every mode the games use (256, 320, 512 and 640 dots), so direct video
shows even pixel widths.

The EEPROM is saved to the SD card by MiSTer's NVRAM mechanism when the
OSD opens after the game has written to it.

## Known issues

- **480i games on a CRT.** Flip Maze, Kollon and Otenami Haiken Final draw
  480-line interlaced screens (512 or 640 by 480). On a 15 kHz CRT the
  picture does not look right yet (fine detail shimmers), and the
  Deinterlacing option is not offered in that mode. The 240-line games
  are not affected. I am looking into it.
- **Loading is slower than on the board.** The CPU spends about 9.6 of its
  cycles on each main RAM load where the real chip needs about 7, so
  CPU-bound work runs slow: Ray Crisis's "Prepares the start." bar takes
  about 16.9 s on the core, 14.69 s on a real board and 12.3 s in MAME.
  Screens after the loaders come 1.5 to 5 s later than in MAME.
- **Sound balance.** MAME mixes the SPU at 0.3 under the Zoom board, a
  setting chosen by ear. The core also applies the SPU main volume the
  games set, which MAME ignores, so at MAME's setting the effects are
  quieter than in MAME (by 2.5 to 14.1 dB depending on the game). One
  phone recording of a real Psyvariar Revision cabinet suggests a level
  of about 0.6 to 0.8 for that game, but on my MiSTer 0.7 sounded wrong
  for Night Raid, so the default stays at MAME's 0.3 until there is board
  evidence per game; the other levels are in the OSD. A line-out
  recording of a board would settle it.
- **First-boot copy.** The first boot MRAs repeat the 2.5 minute copy at
  every load, because the flash chips are not saved. I have not yet
  confirmed the copy on my own hardware, only the main MRAs.
- **Card writes are not saved.** Some games write a few sectors to their
  PC card (what they hold is not known yet); the core keeps those writes
  only until the core is reloaded.
- **Not yet checked on hardware:** play in Ray Crisis (V2.03O) and XII
  Stag on my MiSTer; batches 2 and 3 beyond their title screens; slowdown in heavy scenes against a real board; the EEPROM
  save across a power cycle; rotation and Flip Screen on every display.
- **Watchdog period.** The core uses 8 s where MAME uses 5 s; the board's
  real period is not known (the timing capacitor's value is not legible
  in any photo I have found).
- **Frame rate.** The core runs 59.817 Hz (3413 x 263 at 53.693175 MHz);
  MAME and a note from a real board give 59.826 Hz. A cabinet recording
  agrees with MAME to about 0.3%, which cannot tell the two apart; a
  frequency counter on a board would.

The full list, with the evidence for each item, is in
[docs/ACCURACY.md](docs/ACCURACY.md).

## Findings

Where the core differs from MAME, and why. Full detail and sources are in
[docs/ACCURACY.md](docs/ACCURACY.md).

- **GPU rasteriser.** The PSX_MiSTer GPU matches the PS1 hardware test
  images of JaCzekanski's ps1-tests (Gouraud steps, blend mode 0, texture
  coordinates, edges, dithering); MAME 0.288 differs from them. The core
  keeps the PS1 behaviour, and the ZN-2's 2 MB VRAM.
- **ZSG-2 voice readback.** The Zoom sound driver needs a 13-bit volume
  readback; MAME 0.288 returns 16 bits, which corrupts its voice
  allocator in every game, not only Shikigami. The core follows MAME's
  later fix (commit 61c7940).
- **TMS57002 effects DSP.** The core follows the TI User's Guide on three
  points where MAME does not (multiplier input width, the coefficient
  update rule and the 16-bit serial input), each traced to a page of the
  guide.
- **Watchdog.** Three games run a 2.5 million iteration delay loop with
  no watchdog kick (2.4 to 2.9 s in MAME, longer on the slower real CPU),
  so the board's watchdog cannot be the 1 s or shorter that the MB3773
  datasheet recommends.
- **Flash parts.** Board photos show 28F160S5 (5 V) wave and sub-BIOS
  flash and a 28F400B5 bottom-boot Zoom program flash.

## Architecture

- PSX_MiSTer (Robert Peip): CPU, GTE, GPU, SPU, DMA, timers, IRQ. The CD,
  memory cards, pads, MDEC and savestate request paths are removed behind
  switches; the G-NET games do not use them.
- CPU group at 50.000 MHz with the GTE at 100 MHz; GPU and SPU on their
  own clocks, as on the ZN-2.
- ZN-2 board layer: 4 MB main RAM, 2 MB VRAM, BIOS, two CAT702 security
  chips, the I/O MCU model, the AT28C16 EEPROM, inputs.
- G-NET FC PCB: five Intel flash chips with their command set, the
  RF5C296 PC card controller, the Taito Type 1, Type 2 and CompactFlash
  ATA cards with their unlocks, control registers and the MB3773
  watchdog.
- Taito Zoom: MN10200 sound CPU, ZSG-2 wavetable chip, TMS57002 effects
  DSP, M66220 mailbox, MB87078 volume.
- Memory: main RAM, BIOS and flash in SDRAM; VRAM, SPU RAM, the card
  image and a copy of the flash area for the Zoom board in DDR3, behind a
  DDR3 arbiter that also serves HDMI rotation.

## Repository layout

```
PSX.sv, PSX.qpf               MiSTer shell and Quartus project
GNET_Z1FULLO.qsf, GNET_*.sdc  release revision and its timing constraints
PSX.qsf, PSX_DualSDRAM.*      upstream PSX_MiSTer revisions
rtl/                          PSX_MiSTer core (upstream), with trims behind switches
rtl/gnet/                     ZN-2 board layer, G-NET glue, shell blocks, DDR3 arbiter
rtl/zoom/                     Taito Zoom: MN10200, ZSG-2, TMS57002, board glue
sys/                          MiSTer framework
releases/                     released RBF and MRA files (releases/README.md)
docs/                         accuracy notes, design notes and findings
docs/images/                  screenshots taken on a MiSTer with this core
sim/                          NVC and Verilator benches against MAME traces
tools/                        card, flash and MRA tools, MAME trace scripts
```

The MAME 0.288 sources used as the reference are not copied into the
repository; `docs/mame_sources.md` links each one at the exact version,
with its md5.

## Building and verifying

- Synthesis: Quartus 17, project `PSX.qpf`, revision `GNET_Z1FULLO`.
  Releases are built only from a fit with every clock meeting timing.
  `Arcade-TaitoGNET_20261007.rbf` is the GNET_Z1FULLO build of this
  commit's sources (Quartus 17.0.2, every clock met).
- The design documents in `docs/` are a development log. They name
  earlier experimental Quartus revisions (GNET_F0, GNET_B1, GNET_Z1,
  GNET_Z1SHELL, ZOOM_FIT and others), test MRAs in `mra/`, the script
  that ran builds on my compile PC, and development branches. Those are
  not in this repository; the references record how each result was
  obtained.
- Simulation: NVC 1.23 and Verilator 5.x benches in `sim/`. The MAME
  reference traces need MAME 0.288 and your own files; the trace scripts
  are in `tools/mame/`. Game-derived data from these runs stays in
  gitignored folders.

## License and credits

The files I wrote carry GPL-2.0-or-later headers, the same as PSX_MiSTer's
PSX.sv, so they can go back upstream unchanged. The combined core and its
bitstream are GPL-3.0-or-later, because the MiSTer framework files are
([docs/licensing.md](docs/licensing.md)). `LICENSE` holds PSX_MiSTer's
GPLv2 text and `LICENSE-GPL3` the GPLv3 text. Files from other projects
keep their own licences and headers.

- **PSX_MiSTer** by Robert Peip is the base of the core: CPU, GTE, GPU,
  SPU and the rest of the PlayStation hardware. The MiSTer framework is by
  Sorgelig and contributors.
- **MAME** is the behavioural reference for everything without a better
  source: the taitogn, zn and taito_zm drivers and the zsg2, tms57002,
  mn10200, psx, cat702, rf5c296, ataflash and mb3773 devices, by smf,
  Olivier Galibert, R. Belmont, hap, superctr, cam900, Aaron Giles,
  pSXAuthor and the other MAME developers. The core follows superctr's
  later ZSG-2 fix (MAME commit 61c7940).
- **psx-spx** (Martin "nocash" Korth and contributors) for the PlayStation
  hardware, and JaCzekanski's **ps1-tests** for GPU behaviour.
- **Datasheet and manual authors:** Texas Instruments (TMS57002 User's
  Guide), Fujitsu (MB3773, MB87078), Intel (28F160S5, 28F160S3, 28F400B5),
  Ricoh (RF5C296), Analog Devices (ADM708), IDT (R3051/R3052), LSI Logic
  (CW33000), Panasonic (MN102H and MN102L manuals), Mitsubishi (M66220),
  Atmel (AT28C16), Sanyo (LC321664), the CompactFlash Association, and
  Taito (the G-NET operator manual).
- **Board photos and recordings:** System 16, bytestorm and the
  arcade-projects forum members whose traces and notes are cited in
  docs/ACCURACY.md, westtrade, Gamers Bay and The Obsolete Geek for PCB
  footage.
- XelaNotPu's ZN-1 and ZN-2 cores informed my feasibility study and the
  area budget (measured fits); no code was taken from them.

Development used [Claude Code](https://claude.com/claude-code), Anthropic's AI coding tool.
