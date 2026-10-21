# Taito G-NET core, alpha 4

<!-- TO CONFIRM: release name. Alpha 4 was staged but never published; this release is built from the development line after it (dev branch beta-cand). If it is called alpha 5, rename this file and the "alpha 4" mentions in README.md, releases/README.md and docs/TESTING_GUIDE.md. -->

Core: `Arcade-TaitoGNET_20261021.rbf` (md5 `8623149b677c03d2333e42bc2a225d58`, see
[README.md](README.md)).

I would like the release after this one to be the first beta, so test
reports on this one are the ones that decide it.
<!-- TO CONFIRM: keep or drop the beta sentence. -->

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
- **Settings a game keeps on its card are saved
  ([#9](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/9)).**
  Psyvariar stores its service menu settings, such as
  the screen direction, on the game card, not in the board's EEPROM. The
  core now saves the card sectors a game writes in the NVRAM file
  (`config/nvram/<MRA name>.nvm`) together with the EEPROM. As with other
  MiSTer arcade cores, the file is written when you open the OSD after
  the game has changed something. The file is now 268,288 bytes for every
  game instead of 2 KB; an existing 2 KB file still loads, and the EEPROM
  settings in it are kept. On my MiSTer, with this RBF, Psyvariar
  -Medium Unit- (V2.02O) kept a service menu change (Free Play) across
  a reload of the MRA, and a test core with the same save kept Go By
  RC's calibration (an EEPROM setting), the first time I have checked
  the EEPROM save on hardware. I have not yet checked a power cycle, so
  please tell me whether your settings survive one.
- **High scores for Super Puzzle Bobble (V2.05O).** The core saves its
  ranking table in the same NVRAM file and puts it back after the game
  has booted. It uses MAME's high score list (hiscore.dat), which has
  Super Puzzle Bobble as its only G-NET game, so the other games and the
  Japanese version (V2.04J) get no high score save. The real board and
  MAME do not keep these scores when the power goes off. There is no OSD
  option to turn the save off. MiSTer may write a new score only when
  you open the OSD a second time, rather than the first time after the
  score. On my MiSTer, with this RBF, a new ranking entry was kept
  across a reload of the MRA; I have not yet checked a power cycle, or
  which OSD opening saves it.
- **Louder sound.** The whole mix is 6 dB louder. In my simulation of six
  games the core played about 7 to 17 dB below the reference level I use
  for my cores (Final Star Force on the Tecmo 16 core, about -16.4 dBFS).
  The balance between music and effects (SFX Level) is unchanged, and the
  OSD Volume steps (Normal, +6 dB, -6 dB, -12 dB) are the same as before,
  now on top of the louder mix. The loudest game in that simulation,
  Psyvariar, now peaks at -3.9 dBFS at Normal.
  <!-- TO CONFIRM: listen check on hardware. At +6 dB the same Psyvariar peak would be about +2.1 dBFS, which the core limits to full scale (gnet_volume.sv saturates). -->
- **Button names.** XII Stag's button 1 is now called Shot (the game's
  how-to screen), and Night Raid's buttons Shoot, Wave and Bomb (the
  game's arcade-history entry). MAME gives no names, so the other games
  keep Button 1 to 3.

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
- Psyvariar: change a setting in the service menu, save it, open and
  close the OSD, reload the MRA, and check the setting is kept.
- Super Puzzle Bobble: get a score into the ranking, open the OSD (once
  or twice), power off, load it again and check the ranking.
- Sound: whether the new level sounds right, and any distortion,
  especially with Volume at +6 dB.
- Scandoubler Fx settings over HDMI, direct video and 31 kHz monitors.
- Space Invaders Anniversary: the coloured band and Earth modes, and how
  the speed compares with MAME or a board.

## Known issues

- **XII Stag's intro flash runs too long.** After the Triangle Service
  logo, the flash in the intro lasts about 1.8 s on a real board (board
  footage), but more than 5 s on the core in my simulation, and it is
  dimmer. The cause is
  the texture timing I matched to Ray Crisis and Shikigami no Shiro board
  recordings in alpha 3 (issue
  [#5](https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer/issues/5)): it
  slows this scene more than the board does. I have not yet measured
  whether it affects XII Stag's gameplay. I am working on it for the beta.
- Zooo in 480i over HDMI can show a slight line shake; try Weave and Bob.
  <!-- TO CONFIRM: keep this line only if it still applies on the release RBF. -->
  <!-- TO CONFIRM: XII Stag flash length on hardware with the release RBF (the "more than 5 s" figure is from the alpha 3 settings in simulation, regress-a3 docs/regression_a3_tier2.md; board ~1.8 s from YouTube j-iAwFKdZNs). -->
