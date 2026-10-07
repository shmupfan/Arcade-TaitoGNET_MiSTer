# Releases

The released core and its MRA files, in the MiSTer arcade layout.

| File | md5 |
|---|---|
| `Arcade-TaitoGNET_20261007.rbf` | `3713d5dfa5bb7e2a2b7921abc8ca30b8` |

Revision GNET_Z1FULLO, Quartus 17.0.2, every clock met timing (worst
setup slack +0.168 ns, worst hold slack +0.064 ns).

## Layout

| Path | Copy to | Holds |
|---|---|---|
| `Arcade-TaitoGNET_20261007.rbf` | `/media/fat/_Arcade/cores/` | the core |
| `<Game>.mra` | `/media/fat/_Arcade/` | one quick start MRA per game, for MAME's parent set |
| `_alternatives/_<Game>/` | `/media/fat/_Arcade/_alternatives/_<Game>/` | quick start MRAs for the game's other versions, and the first boot MRAs |

- **Quick start** MRAs load `<set>.flash` from the game zip: the flash
  chips as the BIOS leaves them after its first-boot copy. The game starts
  in a few seconds.
- **First boot** MRAs (`... (first boot).mra`) load `flash.u30` from
  `coh3002t.zip` and erased chips, so the BIOS copies the card into the
  flash (about 2.5 minutes) at every load.

Every MRA also needs `coh3002t.zip` (MAME 0.288) and the set's
`gnet_<set>.zip`, both in `/media/fat/games/mame/`. Make the zips from
your own MAME 0.288 files with `tools/gnet/gnet_tester_zips.py` (see the
[main README](../README.md#installation)). No game data is included here.

## Sets

Config is the game configuration byte (MRA rom index 7): bit 0 vertical,
bit 1 no Taito Zoom board, bits 3:2 controls (0 stick, 1 mahjong panel and
P1 stick, 2 mahjong panel, 3 RC wheel and trigger). The card type is
stored in the zip, not the MRA.

| Set | Zip | Card | Config | Quick start MRA | First boot MRA |
|---|---|---|---|---|---|
| chaoshea | `gnet_chaoshea.zip` | Type 1 | 00 | `Chaos Heat (V2.09O).mra` | `_Chaos Heat` |
| chaosheaj | `gnet_chaosheaj.zip` | Type 1 | 00 | `_Chaos Heat` | `_Chaos Heat` |
| flipmaze | `gnet_flipmaze.zip` | Type 1 | 00 | `Flip Maze (V2.04J).mra` | `_Flip Maze` |
| gobyrc | `gnet_gobyrc.zip` | Type 2 | 0C | `Go By RC (V2.03O).mra` | `_Go By RC` |
| rcdego | `gnet_rcdego.zip` | Type 1 | 0C | `_Go By RC` | `_Go By RC` |
| kollon | `gnet_kollon.zip` | Type 1 | 00 | `Kollon (V2.04JA).mra` | `_Kollon` |
| kollonc | `gnet_kollonc.zip` | CompactFlash | 00 | `_Kollon` | none |
| mahjngoh | `gnet_mahjngoh.zip` | Type 1 | 04 | `Mahjong Oh (V2.06J).mra` | `_Mahjong Oh` |
| nightrai | `gnet_nightrai.zip` | Type 1 | 00 | `Night Raid (V2.03J).mra` | `_Night Raid` |
| otenamih | `gnet_otenamih.zip` | Type 1 | 02 | `Otenami Haiken (V2.04J).mra` | `_Otenami Haiken` |
| otenamhf | `gnet_otenamhf.zip` | CompactFlash | 02 | `Otenami Haiken Final (V2.07JC).mra` | none |
| otenki | `gnet_otenki.zip` | Type 1 | 00 | `Otenki Kororin (V2.01J).mra` | `_Otenki Kororin` |
| psyvaria | `gnet_psyvaria.zip` | Type 1 | 01 | `Psyvariar -Medium Unit- (V2.02O).mra` | `_Psyvariar -Medium Unit-` |
| psyvarij | `gnet_psyvarij.zip` | Type 1 | 01 | `_Psyvariar -Medium Unit-` | `_Psyvariar -Medium Unit-` |
| psyvarrv | `gnet_psyvarrv.zip` | Type 1 | 01 | `Psyvariar -Revision- (V2.04J).mra` | `_Psyvariar -Revision-` |
| raycris | `gnet_raycris.zip` | Type 1 | 00 | `Ray Crisis (V2.03O).mra` | `_Ray Crisis` |
| raycrisj | `gnet_raycrisj.zip` | Type 1 | 00 | `_Ray Crisis` | `_Ray Crisis` |
| shangtou | `gnet_shangtou.zip` | Type 1 | 00 | `Shanghai Sangokuhai Tougi (Ver 2.01J).mra` | `_Shanghai Sangokuhai Tougi` |
| shanghss | `gnet_shanghss.zip` | Type 1 | 00 | `Shanghai Shoryu Sairin (V2.03J).mra` | `_Shanghai Shoryu Sairin` |
| shikigam | `gnet_shikigam.zip` | Type 1 | 01 | `Shikigami no Shiro (V2.03J).mra` | `_Shikigami no Shiro` |
| shikigama | `gnet_shikigama.zip` | Type 1 | 01 | `_Shikigami no Shiro` | `_Shikigami no Shiro` |
| soutenry | `gnet_soutenry.zip` | Type 1 | 00 | `Soutenryu (V2.07J).mra` | `_Soutenryu` |
| sianniv | `gnet_sianniv.zip` | Type 1 | 03 | `Space Invaders Anniversary (V2.02J).mra` | `_Space Invaders Anniversary` |
| spuzbobl | `gnet_spuzbobl.zip` | Type 2 | 00 | `Super Puzzle Bobble (V2.05O).mra` | `_Super Puzzle Bobble` |
| spuzboblj | `gnet_spuzboblj.zip` | Type 2 | 00 | `_Super Puzzle Bobble` | `_Super Puzzle Bobble` |
| usagi | `gnet_usagi.zip` | Type 2 | 08 | `Usagi (V2.02J).mra` | `_Usagi` |
| xiistag | `gnet_xiistag.zip` | Type 1 | 01 | `XII Stag (V2.01J).mra` | `_XII Stag` |
| zokuoten | `gnet_zokuoten.zip` | Type 2 | 02 | `_Zoku Otenamihaiken` | `_Zoku Otenamihaiken` |
| zokuotena | `gnet_zokuotena.zip` | Type 1 | 02 | `Zoku Otenamihaiken (V2.03J).mra` | `_Zoku Otenamihaiken` |
| zooo | `gnet_zooo.zip` | Type 1 | 02 | `Zooo (V2.01JA).mra` | `_Zooo` |

A folder name such as `_Ray Crisis` means `_alternatives/_Ray Crisis/`.

## CompactFlash sets

Kollon (V2.04JC) and Otenami Haiken Final have a quick start MRA only. On
a CompactFlash card the BIOS runs its v2 sub-BIOS, which a real board
installs into U30 from the BIOS EPROM in flash-initialise mode. The core
has no EPROM, so a first boot cannot work. The converter writes the v2
sub-BIOS into the quick start flash from the `f35-01_m27c800.bin` in your
`coh3002t.zip`, byte-equal to MAME 0.288's flash after its copy. Zips made
with an earlier version of the converter can fail on the Type 2 and
CompactFlash sets (wrong card type, or SYSTEM ERROR): convert those sets
again.

## Making the MRAs

The MRAs are generated by `tools/gnet/make_release_mras.py`. Edit the
script, not the files. It takes its set list and titles from the
converter's table in `tools/gnet/gnet_tester_zips.py`.

To check a package before copying it to the SD card, run
`tools/gnet/check_test_package.py <dir>` (layout `_Arcade/` with its MRAs and
`_alternatives` folder, `_Arcade/cores/*.rbf`, `games/mame/*.zip`).
