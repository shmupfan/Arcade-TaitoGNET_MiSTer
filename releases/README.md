# Releases

Released bitstreams and MRA files, in the MiSTer arcade layout.

Copy `Arcade-TaitoGNET_YYYYMMDD.rbf` to `/media/fat/_Arcade/cores/` and
everything else in this folder, subfolders included, to `/media/fat/_Arcade/`
as it is laid out here:

| Folder | Batch | Copy to |
|---|---|---|
| `releases/` | 1: played on hardware | `/media/fat/_Arcade/` |
| `releases/_alternatives/_<Game>/` | 1: first-boot MRAs | `/media/fat/_Arcade/_alternatives/_<Game>/` |
| `releases/_Taito G-NET batch 2 (boots)/` | 2: boots on hardware, expect bugs | `/media/fat/_Arcade/_Taito G-NET batch 2 (boots)/` |
| `releases/_Taito G-NET batch 3 (new features)/` | 3: new core features, untested on hardware, expect bugs | `/media/fat/_Arcade/_Taito G-NET batch 3 (new features)/` |

Each batch folder holds one quick start MRA per set, and its first-boot
MRAs in `_alternatives/_<Game>/` inside that folder.

Each game also needs `coh3002t.zip` (MAME 0.288) and a `gnet_<set>.zip`
made from your own MAME 0.288 files with `tools/gnet/gnet_tester_zips.py`,
both in `/media/fat/games/mame/` (see the main README, Installation). No
game data is included here. The card type (Type 1, Type 2 or CompactFlash)
is stored in the zip, not in the MRA: zips made with the converter from
the first alpha mark every card as Type 1, which is right for the Type 1
sets, so the Type 2 and CompactFlash sets need zips made with the current
converter.

| File | md5 | Notes |
|------|-----|-------|
| `Arcade-TaitoGNET_20261007.rbf` | `3713d5dfa5bb7e2a2b7921abc8ca30b8` | Alpha. Revision GNET_Z1FULLO, Quartus 17.0.2, every clock met timing (worst setup slack +0.168 ns, worst hold slack +0.064 ns). Adds the Taito Type 2 and CompactFlash cards, the no Zoom board setting (config bit 1), the mahjong panel and RC wheel (config bits 3:2) and the ZN-2 read overlap. SFX Level default 0.3 (MAME). Replaces `Arcade-TaitoGNET_20261006.rbf` (first public alpha, revision GNET_Z1FULL, md5 `e7d7995ed20a1568f1636d73ed46c5e0`, SFX Level default 0.7). |

| MRA | Loads |
|---|---|
| `<Game>.mra` (quick start) | the flash as the BIOS leaves it after its first-boot copy (`<set>.flash` from the game zip); starts in a few seconds |
| `_alternatives/_<Game>/<Game> (first boot).mra` | `flash.u30` from `coh3002t.zip` and erased chips, so the BIOS copies the card into the flash (about 2.5 minutes) at every load |

## Games by batch

Only batch 1 is tested. Batches 2 and 3 run on the same hardware paths as
batch 1, but I have only seen batch 2 reach its title or attract screen,
and batch 3 not at all, so expect bugs in both. Reports are welcome
([docs/TESTING_GUIDE.md](../docs/TESTING_GUIDE.md)).

Status: **played** = played on my MiSTer; **boots** = reached the title or
attract screen on my MiSTer on 2026-10-06, not played further (Ray Crisis
(V2.03O) and XII Stag also run to their attract mode in full-system
simulation, and I played the Japanese Ray Crisis, raycrisj); **untested** = not yet
run on hardware.

Config is the game configuration byte (MRA rom index 7): bit 0 vertical
(MAME ROT270), bit 1 no Taito Zoom sound board (MAME `init_nozoom`), bits
3:2 controls (0 stick and 3 buttons, 1 mahjong panel and P1 stick, 2
mahjong panel only, 3 RC wheel and trigger).

### Batch 1: `releases/`

| Game | Set | Zip | Card | Config | Status |
|---|---|---|---|---|---|
| Ray Crisis (V2.03O 1998/11/15) | raycris | `gnet_raycris.zip` | Type 1 | 00 | boots (simulation and hardware boot), not yet played |
| Ray Crisis (V2.03J 1998/11/15) | raycrisj | `gnet_raycrisj.zip` | Type 1 | 00 | played |
| Chaos Heat (V2.09O 1998/10/02) | chaoshea | `gnet_chaoshea.zip` | Type 1 | 00 | played |
| Psyvariar -Medium Unit- (V2.02O 2000/02/22) | psyvaria | `gnet_psyvaria.zip` | Type 1 | 01 | played |
| Psyvariar -Revision- (V2.04J 2000/08/11) | psyvarrv | `gnet_psyvarrv.zip` | Type 1 | 01 | played |
| XII Stag (V2.01J 2002/6/26) | xiistag | `gnet_xiistag.zip` | Type 1 | 01 | boots (simulation and hardware boot), not yet played |
| Shikigami no Shiro (V2.03J 2001/08/07) | shikigam | `gnet_shikigam.zip` | Type 1 | 01 | played |
| Night Raid (V2.03J 2001/02/26) | nightrai | `gnet_nightrai.zip` | Type 1 | 00 | played |

### Batch 2: `releases/_Taito G-NET batch 2 (boots)/`

| Game | Set | Zip | Card | Config | Status |
|---|---|---|---|---|---|
| Chaos Heat (V2.08J 1998/09/25) | chaosheaj | `gnet_chaosheaj.zip` | Type 1 | 00 | boots |
| Psyvariar -Medium Unit- (V2.04J 2000/02/15) | psyvarij | `gnet_psyvarij.zip` | Type 1 | 01 | untested |
| Shikigami no Shiro - internal build (V1.02J 2001/09/27) | shikigama | `gnet_shikigama.zip` | Type 1 | 01 | untested |
| Flip Maze (V2.04J 1999/09/02) | flipmaze | `gnet_flipmaze.zip` | Type 1 | 00 | boots |
| Kollon (V2.04JA 2003/11/01) | kollon | `gnet_kollon.zip` | Type 1 | 00 | boots |
| Shanghai Shoryu Sairin (V2.03J 2000/05/26) | shanghss | `gnet_shanghss.zip` | Type 1 | 00 | boots |
| Soutenryu (V2.07J 2000/12/14) | soutenry | `gnet_soutenry.zip` | Type 1 | 00 | boots |
| Shanghai Sangokuhai Tougi (Ver 2.01J 2002/01/18) | shangtou | `gnet_shangtou.zip` | Type 1 | 00 | boots |
| Otenki Kororin (V2.01J 2001/07/02) | otenki | `gnet_otenki.zip` | Type 1 | 00 | boots |

psyvarij and shikigama are in batch 2 because they are versions of batch
1 games on the same card type, but I have not run them on hardware yet.

### Batch 3: `releases/_Taito G-NET batch 3 (new features)/`

These use the core features added for this release: the no Zoom board
setting, Type 2 and CompactFlash cards, and the mahjong and RC controls.
On 2026-10-07 I boot-tested each set on my MiSTer with this release's RBF
(quick start MRAs, about 80 seconds each, not played). The two
CompactFlash sets have a quick start MRA only: on a CompactFlash card the
BIOS runs its v2 sub-BIOS, which a real board installs into U30 from the
BIOS EPROM in flash-initialise mode, and the core has no EPROM. The
converter writes the v2 sub-BIOS into the quick start flash from the
`f35-01_m27c800.bin` in your `coh3002t.zip`, byte-equal to MAME 0.288's
flash after its copy. Zips made with an older converter stop at SYSTEM
ERROR on these two sets; convert them again.

| Game | Set | Zip | Card | Config | Status | New feature |
|---|---|---|---|---|---|---|
| Otenami Haiken (V2.04J 1999/02/01) | otenamih | `gnet_otenamih.zip` | Type 1 | 02 | boots (title, attract) | no Zoom board |
| Zooo (V2.01JA 2004/04/13) | zooo | `gnet_zooo.zip` | Type 1 | 02 | boots (title, attract) | no Zoom board |
| Space Invaders Anniversary (V2.02J 2003/09/12) | sianniv | `gnet_sianniv.zip` | Type 1 | 03 | boots (attract) | no Zoom board |
| Zoku Otenamihaiken (V2.03J 2001/02/16) | zokuotena | `gnet_zokuotena.zip` | Type 1 | 02 | boots (title, attract) | no Zoom board |
| Zoku Otenamihaiken (V2.05J 2003/05/12) | zokuoten | `gnet_zokuoten.zip` | Type 2 | 02 | untested (V2.05J card not available) | Type 2 card, no Zoom board |
| Super Puzzle Bobble (V2.05O 1999/2/24) | spuzbobl | `gnet_spuzbobl.zip` | Type 2 | 00 | boots (attract) | Type 2 card |
| Super Puzzle Bobble (V2.04J 1999/2/17) | spuzboblj | `gnet_spuzboblj.zip` | Type 2 | 00 | boots (attract) | Type 2 card |
| Kollon (V2.04JC 2003/11/01) | kollonc | `gnet_kollonc.zip` | CompactFlash | 00 | boots (title), quick start only | CompactFlash card |
| Otenami Haiken Final (V2.07JC 2005/04/20) | otenamhf | `gnet_otenamhf.zip` | CompactFlash | 02 | boots (title, attract), quick start only | CompactFlash card, no Zoom board |
| Go By RC (V2.03O 1999/05/25) | gobyrc | `gnet_gobyrc.zip` | Type 2 | 0C | boots (calibration screen) | Type 2 card, RC wheel and trigger |
| RC De Go (V2.03J 1999/05/22) | rcdego | `gnet_rcdego.zip` | Type 1 | 0C | boots (calibration screen) | RC wheel and trigger |
| Mahjong Oh (V2.06J 1999/11/23) | mahjngoh | `gnet_mahjngoh.zip` | Type 1 | 04 | boots (attract) | mahjong panel and P1 stick |
| Usagi (V2.02J 2001/10/02) | usagi | `gnet_usagi.zip` | Type 2 | 08 | boots (attract) | Type 2 card, mahjong panel |

Not included: Mawasunda (it runs on the ZN-1 G-NET board, `coh1002t`) and
the 2011 conversions (G-Darius, Ray Storm, Aero Fighters Special, Brave
Blade, Flame Gunner, Fighters' Impact, Shanghai Matekibuyuu, The Block
Kuzushi), which boot from a modified BIOS on a plain card.

### JP1

The G-NET board's JP1 jumper (BIOS Flash) is bit 4 of the MRA switch
byte. Every MRA sets it open (switches default `0F`) and the OSD does not
offer it. With JP1 closed the BIOS runs its flash initialise on every
boot and the game never starts. MAME 0.288 sets JP1 closed by default for
Kollon (V2.04JC) and Otenami Haiken Final (input `taitogn_jp1`), so the
flasher can run first; these MRAs keep it open for a normal boot.

## Making the MRAs

The MRAs are generated by `tools/gnet/make_release_mras.py`; edit the
script, not the files:

```
tools/gnet/make_release_mras.py
```

It writes every batch, quick start and first boot, and takes its set list
and titles from the converter's table in `tools/gnet/gnet_tester_zips.py`.

Check a package before copying it to the SD card:
`tools/gnet/check_test_package.py <dir>` (layout `_Arcade/*.mra`,
`_Arcade/cores/*.rbf`, `games/mame/*.zip`).
