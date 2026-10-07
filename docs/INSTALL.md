# Installing the Taito G-NET core

This guide takes you from a MAME set to a game running on your MiSTer.
Follow the steps in order. Most problems people have reported come from
skipping step 3 or doing it by hand.

No BIOS, card or game data comes with the core. You make the game files
yourself, from your own MAME files, with a converter that runs on your
computer: a web page you open in your browser, or a Python script.

## What you need

- A MiSTer, with Update All (or you can copy the files by hand).
- From your own MAME 0.288 set:
  - `coh3002t.zip`, the G-NET BIOS set.
  - The CHD file of each game you want to play.
- A computer (Windows, Mac or Linux) with Chrome, Firefox or Safari, or
  with Python 3 (3.7 or newer). MAME's `chdman` is not needed.

## 1. Get the core

### With Update All

The core is in the shmupfan database. Add these two lines to
`/media/fat/downloader.ini` on your MiSTer SD card:

```ini
[shmupfan]
db_url = https://raw.githubusercontent.com/shmupfan/Distribution/main/db.json
```

Run Update All. It installs the core (RBF) and every MRA, including the
`_alternatives` folder. You do not copy any of those by hand. You only
add `coh3002t.zip` and the converted game zips (steps 2 to 4).

### By hand

From the [releases](../releases/) folder of this repository:

1. Copy `Arcade-TaitoGNET_20261007.rbf` to `/media/fat/_Arcade/cores/`.
2. Copy every `.mra` file to `/media/fat/_Arcade/`.
3. Copy the `_alternatives` folder to `/media/fat/_Arcade/`, keeping the
   folders inside it as they are.

## 2. Lay out your MAME files

Put `coh3002t.zip` and the game CHDs in one folder. The CHDs can sit
directly in it or in subfolders, as MAME keeps them. The converter
matches each CHD to its game by its SHA1 (a fingerprint of the file), so
folder and file names do not matter.

```
roms/
  coh3002t.zip            <- the BIOS set, still zipped
  raycris/
    raycris.chd
  chaosheat.chd           <- a CHD outside a folder is found too
```

Points to check:

- Leave `coh3002t.zip` zipped. Do not add files to it.
- Use the MAME 0.288 CHDs listed below. A CHD from another version is
  used only if it is in its MAME folder under its MAME name (for example
  `chaoshea/chaosheat.chd`), and the converter warns about it.
- You do not need every game. The converter skips the ones it does not
  find.

The games and their MAME CHD file names:

| Game | Version | Set | CHD file |
|---|---|---|---|
| Chaos Heat | V2.09O | chaoshea | `chaosheat.chd` |
| Chaos Heat | V2.08J | chaosheaj | `chaosheatj.chd` |
| Flip Maze | V2.04J | flipmaze | `flipmaze.chd` |
| Go By RC | V2.03O | gobyrc | `gobyrc.chd` |
| Kollon | V2.04JA | kollon | `kollon.chd` |
| Kollon | V2.04JC | kollonc | `kollonc.chd` |
| Mahjong Oh | V2.06J | mahjngoh | `mahjngoh.chd` |
| Night Raid | V2.03J | nightrai | `nightrai.chd` |
| Otenami Haiken | V2.04J | otenamih | `otenamih.chd` |
| Otenami Haiken Final | V2.07JC | otenamhf | `otenamhf.chd` |
| Otenki Kororin | V2.01J | otenki | `otenki.chd` |
| Psyvariar -Medium Unit- | V2.02O | psyvaria | `psyvaria.chd` |
| Psyvariar -Medium Unit- | V2.04J | psyvarij | `psyvarij.chd` |
| Psyvariar -Revision- | V2.04J | psyvarrv | `psyvarrv.chd` |
| RC De Go | V2.03J | rcdego | `rcdego.chd` |
| Ray Crisis | V2.03O | raycris | `raycris.chd` |
| Ray Crisis | V2.03J | raycrisj | `raycrisj.chd` |
| Shanghai Sangokuhai Tougi | Ver 2.01J | shangtou | `shanghaito.chd` |
| Shanghai Shoryu Sairin | V2.03J | shanghss | `shanghss.chd` |
| Shikigami no Shiro | V2.03J | shikigam | `shikigam.chd` |
| Shikigami no Shiro | V1.02J internal build | shikigama | `shikigama.chd` |
| Soutenryu | V2.07J | soutenry | `soutenry.chd` |
| Space Invaders Anniversary | V2.02J | sianniv | `sianniv.chd` |
| Super Puzzle Bobble | V2.05O | spuzbobl | `spuzbobl.chd` |
| Super Puzzle Bobble | V2.04J | spuzboblj | `spuzbobj.chd` |
| Usagi | V2.02J | usagi | `usagi.chd` |
| XII Stag | V2.01J | xiistag | `xiistag.chd` |
| Zoku Otenamihaiken | V2.05J | zokuoten | `zokuoten.chd` |
| Zoku Otenamihaiken | V2.03J | zokuotena | `zokuotena.chd` |
| Zooo | V2.01JA | zooo | `zooo.chd` |

## 3. Convert the game cards

MiSTer cannot read CHD files. The converter turns each game's CHD into
one `gnet_<set>.zip` (for example `gnet_raycris.zip`). You do this once
per game. Use the browser converter or the Python script: both write the
same files.

### In your browser

1. Open [tools/gnet_converter.html](../tools/gnet_converter.html) on
   GitHub and click **Download raw file** (the download icon above the
   file).
2. Open the downloaded file in Chrome, Firefox or Safari. It runs on your
   computer: nothing is uploaded.
3. Choose `coh3002t.zip`, then your CHD files or the folder that holds
   them.
4. Click **Convert** and keep the tab in view. Save each zip, or use
   **Download all as one zip** and unzip it.

Then go to step 4.

### With Python

#### Download the converter

1. Open the repository page on GitHub:
   <https://github.com/shmupfan/Arcade-TaitoGNET_MiSTer>
2. Click the green **Code** button, then **Download ZIP**.
3. Unzip it. You get a folder called `Arcade-TaitoGNET_MiSTer-main`.

The folder you need is the one that holds `README.md` and the `tools`
folder. Windows "Extract All" often makes the same folder twice, one
inside the other. In that case use the inner one.

#### Windows

Use Command Prompt. Do not type the commands into the Python window (the
one with the `>>>` prompt): that gives `SyntaxError: invalid syntax`.

1. Install Python 3 from python.org if you do not have it. In the
   installer, tick **Add python.exe to PATH**.
2. Open the `Arcade-TaitoGNET_MiSTer-main` folder in File Explorer.
   Click the address bar, type `cmd` and press Enter. A Command Prompt
   opens in that folder.
3. Type this, with your own paths, and press Enter:

```
python tools\gnet\gnet_tester_zips.py --roms "C:\MAME\roms" --out "C:\gnet-zips"
```

- `--roms` is your roms folder from step 2.
- `--out` is a new folder for the zips. The converter makes it for you.
- Put quotes around every path. A path with a space in it, such as
  `C:\Users\Your Name\MAME\roms`, does not work without them.
- If `python` is not found, use `py` instead:
  `py tools\gnet\gnet_tester_zips.py ...`

If you opened Command Prompt some other way, go to the repository folder
first. `cd /d` also changes the drive if needed:

```
cd /d "C:\Users\Your Name\Downloads\Arcade-TaitoGNET_MiSTer-main"
```

You can also give the full path to the script instead:

```
python "C:\Users\Your Name\Downloads\Arcade-TaitoGNET_MiSTer-main\tools\gnet\gnet_tester_zips.py" --roms "C:\MAME\roms" --out "C:\gnet-zips"
```

#### Mac and Linux

1. Open Terminal and go to the repository folder. On a Mac without
   Python 3, the first `python3` command offers to install it.

```
cd ~/Downloads/Arcade-TaitoGNET_MiSTer-main
```

2. Run the converter, with your own paths:

```
python3 tools/gnet/gnet_tester_zips.py --roms "/path/to/MAME/roms" --out "/path/to/gnet-zips"
```

- Put quotes around paths with spaces. On a Mac you can drag a folder
  from Finder into Terminal to type its path.

To convert only some games, add `--sets` and the set names, for example
`--sets raycris shikigam`.

#### What it prints when it works

The converter checks `coh3002t.zip` first, then prints one line for each
of the 30 sets. Games you do not have say `no CHD found, skipped`. That
is normal. For example, with three games:

```
coh3002t.zip OK
  chaoshea: no CHD found, skipped
  chaosheaj: no CHD found, skipped
  raycris: wrote C:\gnet-zips\gnet_raycris.zip (Ray Crisis (V2.03O 1998/11/15 15:43), Type 1 card, 40,960,000 bytes)
  raycrisj: no CHD found, skipped
  spuzbobl: no CHD found, skipped
  spuzboblj: wrote C:\gnet-zips\gnet_spuzboblj.zip (Super Puzzle Bobble (V2.04J 1999/2/17 02:10), Type 2 card, 38,600,704 bytes)
  ...
  zooo: wrote C:\gnet-zips\gnet_zooo.zip (Zooo (V2.01JA 2004/04/13 12:00), Type 1 card, 40,960,000 bytes)
3 game zip(s) written to C:\gnet-zips
Copy them and coh3002t.zip to /media/fat/games/mame/ on the MiSTer SD card.
```

Each game takes a few seconds. If a line says `warning`, read
[If something goes wrong](#if-something-goes-wrong).

The zips are made from your own files. Keep them to yourself.

## 4. Copy to the MiSTer

Copy these files to `/media/fat/games/mame/` (the `games/mame` folder on
the SD card):

- `coh3002t.zip`
- every `gnet_<set>.zip` the converter wrote

Nothing else goes there for this core. Do not unzip any of them, do not
rename them, and do not put the game files inside `coh3002t.zip`.

## 5. Play

Open the Arcade menu on the MiSTer.

- **`<Game>.mra`** is the main MRA for each game. Use this one. The
  game starts in a few seconds.
- **`_alternatives/_<Game>/`** holds the game's other versions, for
  example Ray Crisis (V2.03J) or RC De Go (in `_Go By RC`). Each MRA
  needs the zip of its own set: Ray Crisis (V2.03J) needs
  `gnet_raycrisj.zip`. [releases/README.md](../releases/README.md#sets)
  lists the zip for every MRA.
- **`... (first boot).mra`**, also in `_alternatives`, starts like a real
  board after a card swap. The BIOS copies the card into the flash chips,
  which takes about 2.5 minutes, and repeats at every load. Do not reset
  or power off during the copy. Kollon (V2.04JC) and Otenami Haiken Final
  have no first boot MRA. You do not need these MRAs to play.

Go By RC and RC De Go stop on a CALIBRATION screen the first time. Leave
the stick centred and press Start. The game saves the calibration.

The controls and OSD options are in the [README](../README.md#controls).

## If something goes wrong

### On the computer

| What you see | Cause | Fix |
|---|---|---|
| `SyntaxError: invalid syntax` and a `>>>` prompt | The command was typed into Python itself, not Command Prompt | Type `exit()` and press Enter. Open Command Prompt as in step 3 |
| `'python' is not recognized`, or the Microsoft Store opens | Python is not installed, or not on the PATH | Try `py` instead of `python`. Otherwise install Python from python.org with **Add python.exe to PATH** ticked |
| `can't open file ... gnet_tester_zips.py ... No such file or directory` | Command Prompt or Terminal is not in the repository folder | Go to the folder that holds `README.md` and `tools`, or give the full path to the script |
| `error: unrecognized arguments` | A path with a space in it has no quotes | Put quotes around every path |
| `error: ...coh3002t.zip not found` | `coh3002t.zip` is not in the `--roms` folder | Put it in that folder, still zipped |
| `error: ...coh3002t.zip: ... missing or not the MAME 0.288 version` | The BIOS zip is from another MAME version, or was changed | Use an unchanged `coh3002t.zip` from a MAME 0.288 set |
| `<set>: no CHD found, skipped` for a game you have | No CHD in the `--roms` folder is the MAME 0.288 file for that game | Check the CHD is inside the `--roms` folder and is the version in the table in step 2 |
| `warning, CHD SHA1 ... is not MAME 0.288's ...; continuing` | The CHD is not the one MAME 0.288 uses: another dump, a set from another MAME version, or a damaged file | The zip is still written, but the game may not start. Use the CHD from a MAME 0.288 set |
| `<set>: warning, ... has SHA1 ..., not MAME 0.288's ...` | The CHD in the game's MAME folder is another version | The zip is still written. If the game does not start, use the MAME 0.288 CHD |

### On the MiSTer

| What you see | Cause | Fix |
|---|---|---|
| The game does not load and MiSTer reports a missing file such as `raycris.meta` | The zip was made by hand, or renamed, or the game files were put inside `coh3002t.zip` | Delete it. Make the zip with the converter (step 3). Put back an unchanged `coh3002t.zip` |
| MiSTer reports a missing `gnet_<set>.zip` | There is no zip for the set this MRA loads (often an alternative version) | Convert that set, or load the MRA of a set you have |
| Nothing starts, no TAITO G-NET logo | `coh3002t.zip` is missing from `games/mame` | Copy it there, still zipped |
| SYSTEM ERROR after the TAITO G-NET logo | The game zip is wrong: made by hand, made from the wrong CHD, or made with an older version of the converter. Older versions fail on the Type 2 and CompactFlash sets, such as Super Puzzle Bobble | Convert again with the current converter (step 3). Check the converter printed no warnings |
| Go By RC or RC De Go stops on a CALIBRATION screen | Normal on a first boot | Leave the stick centred and press Start |
| A "Loading now." screen for about 2.5 minutes | You loaded a first boot MRA | Normal. Wait, or load the main MRA instead |

If none of these fits, the [testing guide](TESTING_GUIDE.md) explains
how to report a problem.

## Why a hand-made zip does not work

Turning the CHD into an `.img` file with `chdman` is not enough. The
converter writes three files into each `gnet_<set>.zip`:

- `<set>.img`: the card image.
- `<set>.meta`: the card's identity data, its CIS, its unlock key and the
  card type. These are stored in the CHD next to the image, and
  `chdman extractraw` or `extracthd` leaves them out.
- `<set>.flash`: the flash chips as the BIOS leaves them after it
  installs the game, built from your card and BIOS files.

The main MRAs load all three from `gnet_<set>.zip`. The first boot MRAs
load the `.img` and the `.meta`. If a file is missing, the MRA does not
load, and a zip with the wrong contents ends in SYSTEM ERROR. Use the
converter.
