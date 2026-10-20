# Taito G-NET core, alpha 4

Core: `Arcade-TaitoGNET_YYYYMMDD.rbf` (md5 TO FILL, see
[README.md](README.md)).
<!-- TO CONFIRM: RBF date and md5. -->

## Fixes

- **Space Invaders Anniversary: a triangle hid half the playfield
  ([#10](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/10)).**
  The graphics chip gave up on the big rotated picture the game draws in
  the coloured band mode. It now always finishes it. This mode may now run
  slower than on a real board; board footage of it would help.
- **Scandoubler Fx: no picture with any setting other than None
  ([#11](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/11)).**
  The scandoubled output had no vertical sync since alpha 1. HQ2x and the
  CRT scanline settings now work over HDMI and on 31 kHz monitors, and so
  does `forced_scandoubler=1`. A 15 kHz CRT still needs Fx None.

## New

- **Faster loading
  ([#12](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/12)).**
  The MRAs load each game's card image straight into memory through
  MiSTer's DDR3 load path, instead of one word at a time. I expect Ray
  Crisis to load in about 12 to 13 s instead of about 35 s. The new MRAs
  need a Main_MiSTer from March 2021 or later. The 10 MB of flash still
  loads the old way; loading it into DDR3 as well is for a later release.
  <!-- TO CONFIRM: replace the estimate with the measured load time. -->

## Please test and report on GitHub

- Load times, and any game that doesn't start with the new MRAs.
- Scandoubler Fx settings over HDMI, direct video and 31 kHz monitors.
- Space Invaders Anniversary: the coloured band and Earth modes, and how
  the speed compares with MAME or a board.

## Known issues

- **Psyvariar settings changed in the service menu are not kept after a
  reload ([#9](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/9)).**
  Psyvariar stores its settings on the game card, and the core doesn't
  save card writes yet. Games that keep their settings in the board's
  EEPROM, such as the Go By RC calibration, are saved when you open the
  OSD.
  <!-- TO CONFIRM: the EEPROM save sentence is not hardware-checked; drop it if the check fails. -->
- Zooo in 480i over HDMI can show a slight line shake; try Weave and Bob.
  <!-- TO CONFIRM: keep this line only if it still applies on the alpha 4 RBF. -->
