# Taito G-NET core, alpha 4

<!-- TO CONFIRM: release name. Alpha 4 was staged but never published; this release is built from the development line after it. If it is called alpha 5, rename this file and the "alpha 4" mentions in README.md, releases/README.md and docs/TESTING_GUIDE.md. -->

Core: `Arcade-TaitoGNET_YYYYMMDD.rbf` (md5 TO FILL, see
[README.md](README.md)).
<!-- TO CONFIRM: RBF date and md5. -->

## New

- **Faster loading
  ([#12](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/12)).**
  The MRAs load each game's card image and its 10 MB of flash straight
  into memory through MiSTer's DDR3 load path, instead of one word at a
  time; the core then copies the flash into place itself. Games load much
  faster: Ray Crisis took about 35 s with the alpha 3 MRAs and now takes
  TODO s. The new MRAs need this RBF and a Main_MiSTer from March 2021 or
  later; with an older RBF the game does not start. The first boot MRAs
  still need the BIOS's 2.5 minute flash copy after loading.
  <!-- TODO: measured Ray Crisis load time on the release RBF. -->
- **Button names.** XII Stag's button 1 is now called Shot (the game's
  how-to screen), and Night Raid's buttons Shoot, Wave and Bomb (the
  game's arcade-history entry). MAME gives no names, so the other games
  keep Button 1 to 3.
<!-- TO CONFIRM (#9): keep the next item only if the card journal is in the release RBF and Lee's Psyvariar save test passed. Otherwise delete it and keep the #9 item under Known issues. -->
- **Psyvariar keeps its settings
  ([#9](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/9)).**
  Psyvariar stores its service menu settings, such as the screen
  direction, on the game card, not in the board's EEPROM. The core now
  saves the card sectors a game writes in the NVRAM file together with
  the EEPROM, when you open the OSD after a change. The NVRAM file grows
  from 2 KB to 268,288 bytes; an existing 2 KB file still loads, and the
  EEPROM in it is kept.

## Fixes

- **Space Invaders Anniversary: a triangle hid half the playfield
  ([#10](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/10)).**
  The graphics chip gave up on the big rotated picture the game draws in
  the coloured band mode. It now always finishes it, and on my MiSTer the
  attract shows the whole formation. This mode may now run slower than
  on a real board; board footage of it would help.
- **Scandoubler Fx: no picture with any setting other than None
  ([#11](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/11)).**
  The scandoubled output had no vertical sync since alpha 1. The fix is
  in this release, but I have not been able to check it over HDMI or with
  the scandoubler on my own setup, so please tell me whether HQ2x and the
  CRT scanline settings now work over HDMI and on 31 kHz monitors, and
  with `forced_scandoubler=1`. A 15 kHz CRT still needs Fx None.

## Other changes

- The release core no longer has the Debug overlay OSD item. I took it
  out to free space on the FPGA; I can still build it into test cores.
- README: the OSD options section now lists every option the core has,
  with its values and its page (Deinterlacing, Dim video after 10s,
  Service Menu and Reset were missing), and the loading and controls
  sections describe this release.
- PROVENANCE.md (new): where every part of the core comes from, and what
  I changed in PSX_MiSTer's files and why.

## Please test and report on GitHub

- Load times, and any game that doesn't start with the new MRAs.
- Scandoubler Fx settings over HDMI, direct video and 31 kHz monitors.
- Space Invaders Anniversary: the coloured band and Earth modes, and how
  the speed compares with MAME or a board.

## Known issues

<!-- TO CONFIRM (#9): keep this item only if the card journal is NOT in the release. -->
- **Psyvariar settings changed in the service menu are not kept after a
  reload ([#9](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/9)).**
  Psyvariar stores its settings on the game card, and the core doesn't
  save card writes yet. Games that keep their settings in the board's
  EEPROM, such as the Go By RC calibration, are saved when you open the
  OSD.
  <!-- TO CONFIRM: the EEPROM save sentence is not hardware-checked; drop it if the check fails. -->
- Zooo in 480i over HDMI can show a slight line shake; try Weave and Bob.
  <!-- TO CONFIRM: keep this line only if it still applies on the release RBF. -->
