#!/usr/bin/env python3
"""Write the release MRAs for every G-NET set the converter knows into releases/.

  tools/gnet/make_release_mras.py [--rbf TaitoGNET] [--out releases]

The release layout (releases/README.md), the MiSTer arcade convention:
  releases/<Game>.mra
      the quick start MRA of each game's main set (the MAME parent);
  releases/_alternatives/_<Game>/<Game> (<version>).mra
      the quick start MRA of every other set of that game (MAME clones, and
      the Shikigami no Shiro internal build);
  releases/_alternatives/_<Game>/<Game> (<version>) (first boot).mra
      the first boot MRA of every set on a Type 1 or Type 2 card.
A quick start MRA loads <set>.flash, the flash chips as the BIOS leaves them
after its first-boot copy. A first boot MRA loads only flash.u30 from
coh3002t.zip into the flash area (the other chips erased), so the BIOS does
its first-boot copy of the card into the flash chips (about 2.5 minutes) on
every start. CompactFlash sets have no first boot MRA: on a CompactFlash card
the BIOS runs its v2 sub-BIOS, which a real board installs into U30 from the
BIOS EPROM in flash-initialise mode, and the core has no EPROM.

The sets, their titles and card types are the converter's SETS table
(tools/gnet/gnet_tester_zips.py); the script stops if the two lists differ.
The card type is carried in the zip's .meta (byte 3F0h), not in the MRA.
Year, manufacturer, rotation, init_nozoom and the input port are from the
MAME 0.288 taitogn.cpp GAME lines (1353 to 1388, docs/mame_sources.md).
Left out: mawasunda (ZN-1 board, coh1002t) and the 2011 conversions
(coh3002t_bl, plain ATA card and the modified BIOS).

Fields follow the MiSTer arcade MRA layout used by the Dooyong core
(dooyong-mister/releases): name, setname, rbf, mameversion, year,
manufacturer, category, players, joystick, rotation, switches, buttons,
roms, nvram.

Loads (docs/zn2_layer_design.md 13.5, docs/m4_shell.md 3):
  index 0  BIOS m534002c-60.ic353 (coh3002t.zip)
  index 2  CAT702 keys tt10.ic652, tt16.u17 (coh3002t.zip)
  index 3  flash area <set>.flash (gnet_<set>.zip, quick start), or
           flash.u30 and 8 MB of FFh (first boot)
  index 4  card metadata <set>.meta, index 5 card image <set>.img
  index 6  EEPROM, 2048 bytes (nvram)
  index 7  game configuration byte: bit 0 = vertical set (MAME ROT270);
           bit 1 = no Taito Zoom board (MAME init_nozoom); bits 3:2 =
           controls (PSX.sv gnet_inmode): 0 joysticks, 1 mahjong panel and
           P1 joystick (mahjngoh), 2 mahjong panel (usagi), 3 RC wheel and
           trigger (gobyrc, rcdego); the mahjong keys are on the keyboard
           (MAME defaults)
  index 254 switches, byte 0: bits 3-0 DIP S551 (active low, all Off, MAME
           DSW 0Fh), bit 4 JP1 (BIOS Flash). JP1 is 0 (open) for every set
           and not offered in the OSD: with JP1 closed the BIOS runs the
           EPROM flasher on every boot and the game never starts (MAME
           taitogn_jp1 defaults it closed for kollonc and otenamhf; the core
           has no EPROM in bank 2). docs/gnet_set_survey.md 2.3.
gnet_<set>.zip is made from the user's own MAME set with
tools/gnet/gnet_tester_zips.py (MiSTer cannot read the CHD).
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gnet_tester_zips import SETS as CONVERTER_SETS  # noqa: E402

# set: (file name, year, manufacturer, ROT270, init_nozoom, controls, category)
# year, manufacturer, rotation, init_nozoom and input port from MAME 0.288
# taitogn.cpp GAME lines; controls from the input port (taitogn 0,
# mahjngoh 1, usagi 2, gobyrc 3); category is the game's genre.
RELEASE = {
    "raycris": ("Ray Crisis (V2.03O)", "1998", "Taito", False, False, 0, "Shooter"),
    "raycrisj": ("Ray Crisis (V2.03J)", "1998", "Taito", False, False, 0, "Shooter"),
    "chaoshea": ("Chaos Heat (V2.09O)", "1998", "Taito", False, False, 0, "Third-person shooter"),
    "chaosheaj": ("Chaos Heat (V2.08J)", "1998", "Taito", False, False, 0, "Third-person shooter"),
    "psyvaria": ("Psyvariar -Medium Unit- (V2.02O)", "2000", "Success", True, False, 0, "Shooter"),
    "psyvarij": ("Psyvariar -Medium Unit- (V2.04J)", "2000", "Success", True, False, 0, "Shooter"),
    "psyvarrv": ("Psyvariar -Revision- (V2.04J)", "2000", "Success", True, False, 0, "Shooter"),
    "xiistag": ("XII Stag (V2.01J)", "2002", "Triangle Service", True, False, 0, "Shooter"),
    "shikigam": ("Shikigami no Shiro (V2.03J)", "2001", "Alfa System / Taito", True, False, 0, "Shooter"),
    "shikigama": ("Shikigami no Shiro - internal build (V1.02J)", "2001", "Alfa System / Taito", True, False, 0,
                  "Shooter"),
    "nightrai": ("Night Raid (V2.03J)", "2001", "Takumi", False, False, 0, "Shooter"),
    "flipmaze": ("Flip Maze (V2.04J)", "1999", "MOSS / Taito", False, False, 0, "Puzzle"),
    "kollon": ("Kollon (V2.04JA)", "2003", "Taito", False, False, 0, "Puzzle"),
    "kollonc": ("Kollon (V2.04JC)", "2003", "Taito", False, False, 0, "Puzzle"),
    "shanghss": ("Shanghai Shoryu Sairin (V2.03J)", "2000", "Warashi", False, False, 0, "Puzzle"),
    "soutenry": ("Soutenryu (V2.07J)", "2000", "Warashi", False, False, 0, "Puzzle"),
    "shangtou": ("Shanghai Sangokuhai Tougi (Ver 2.01J)", "2002", "Warashi / Sunsoft / Taito", False, False, 0,
                 "Puzzle"),
    "otenki": ("Otenki Kororin (V2.01J)", "2001", "Takumi", False, False, 0, "Puzzle"),
    "otenamih": ("Otenami Haiken (V2.04J)", "1999", "Success", False, True, 0, "Minigames"),
    "otenamhf": ("Otenami Haiken Final (V2.07JC)", "2005", "Success / Warashi", False, True, 0, "Minigames"),
    "zokuoten": ("Zoku Otenamihaiken (V2.05J)", "2003", "Success", False, True, 0, "Minigames"),
    "zokuotena": ("Zoku Otenamihaiken (V2.03J)", "2001", "Success", False, True, 0, "Minigames"),
    "zooo": ("Zooo (V2.01JA)", "2004", "Success", False, True, 0, "Puzzle"),
    "sianniv": ("Space Invaders Anniversary (V2.02J)", "2003", "Taito", True, True, 0, "Shooter"),
    "spuzbobl": ("Super Puzzle Bobble (V2.05O)", "1999", "Taito", False, False, 0, "Puzzle"),
    "spuzboblj": ("Super Puzzle Bobble (V2.04J)", "1999", "Taito", False, False, 0, "Puzzle"),
    "gobyrc": ("Go By RC (V2.03O)", "1999", "Taito", False, False, 3, "Driving"),
    "rcdego": ("RC De Go (V2.03J)", "1999", "Taito", False, False, 3, "Driving"),
    "mahjngoh": ("Mahjong Oh (V2.06J)", "1999", "Warashi / Mahjong Kobo / Taito", False, False, 1, "Mahjong"),
    "usagi": ("Usagi (V2.02J)", "2001", "Warashi / Mahjong Kobo / Taito", False, False, 2, "Mahjong"),
}

# Sets that are not their game's main MRA, and the main set they go under.
# Every MAME clone (the converter's parent column) is here; MAME lists the
# Shikigami no Shiro internal build as a separate game, but it is the same game.
ALT_OF = {
    "raycrisj": "raycris",
    "chaosheaj": "chaoshea",
    "psyvarij": "psyvaria",
    "shikigama": "shikigam",
    "kollonc": "kollon",
    "spuzboblj": "spuzbobl",
    "zokuotena": "zokuoten",
    "rcdego": "gobyrc",
}


def game_of(s):
    """the game's name (folder name in _alternatives): the main set's title without the version"""
    return RELEASE[ALT_OF.get(s, s)][0].split(" (")[0]


# per controls value: players, joystick, button names (J1 bits 4-11)
CONTROLS = {
    0: ("2", "8-way", "Button 1,Button 2,Button 3,Start,Coin,Service,Test,Pause"),
    1: ("1", "8-way", "Button 1,Button 2,Button 3,Start,Coin,Service,Test,Pause"),
    2: ("1", "none", "(unused),(unused),(unused),Start,Coin,Service,Test,Pause"),
    3: ("1", "analog (wheel X, trigger Y)", "(unused),(unused),(unused),Start,Coin,Service,Test,Pause"),
}

FLASH_WARM = """    <rom index="3" zip="gnet_{set}.zip" md5="none">
        <part name="{set}.flash" />
    </rom>
"""
FLASH_COLD = """    <rom index="3" zip="coh3002t.zip" md5="none">
        <part name="flash.u30" crc="c48c8236" />
        <part repeat="0x800000">FF</part>
    </rom>
"""
TEMPLATE = """<misterromdescription>
    <name>{title}</name>
    <setname>{set}</setname>
    <rbf>{rbf}</rbf>
    <mameversion>0288</mameversion>
    <year>{year}</year>
    <manufacturer>{mfr}</manufacturer>
    <category>{cat}</category>
    <players>{players}</players>
    <joystick>{joy}</joystick>
    <rotation>{rot}</rotation>
    <switches default="0F">
        <dip name="Unknown (S551:1)" bits="0" ids="On,Off" />
        <dip name="Service Mode (S551:2)" bits="1" ids="On,Off" />
        <dip name="Unknown (S551:3)" bits="2" ids="On,Off" />
        <dip name="Test Mode (S551:4)" bits="3" ids="On,Off" />
    </switches>
    <buttons names="{buttons}" default="A,B,X,Start,Select,L,R" />
    <rom index="0" zip="coh3002t.zip" md5="none">
        <part name="m534002c-60.ic353" crc="03967fa7" />
    </rom>
    <rom index="2" zip="coh3002t.zip" md5="none">
        <part name="tt10.ic652" crc="235510b1" />
        <part name="tt16.u17" crc="6bb167b3" />
    </rom>
{flash}    <rom index="4" zip="gnet_{set}.zip" md5="none">
        <part name="{set}.meta" />
    </rom>
    <rom index="5" zip="gnet_{set}.zip" md5="none">
        <part name="{set}.img" />
    </rom>
    <rom index="7">
        <part>{cfg:02X}</part>
    </rom>
    <nvram index="6" size="2048" />
</misterromdescription>
"""


def title_of(s):
    """MAME description without the time of day, as in the earlier MRAs"""
    t = CONVERTER_SETS[s][0]
    head, _, ver = t.rpartition(" (")
    words = [w for w in ver.rstrip(")").split() if ":" not in w]
    return f"{head} ({' '.join(words)})"


def config_byte(s):
    _, _, _, vert, nozoom, ctl, _ = RELEASE[s]
    return int(vert) | (int(nozoom) << 1) | (ctl << 2)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rbf", default="TaitoGNET")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), "releases"))
    a = ap.parse_args()
    if set(RELEASE) != set(CONVERTER_SETS):
        sys.exit(f"error: release sets and converter SETS differ: only here {sorted(set(RELEASE) - set(CONVERTER_SETS))}, "
                 f"only in the converter {sorted(set(CONVERTER_SETS) - set(RELEASE))}")
    for s in CONVERTER_SETS:
        parent = CONVERTER_SETS[s][4]
        if parent and ALT_OF.get(s) != parent:
            sys.exit(f"error: {s} is a MAME clone of {parent}; ALT_OF must place it under {parent}")
    n = 0
    for s in CONVERTER_SETS:
        fname, year, mfr, vert, nozoom, ctl, cat = RELEASE[s]
        players, joy, buttons = CONTROLS[ctl]
        alt = os.path.join(a.out, "_alternatives", "_" + game_of(s))
        # CompactFlash cards need the v2 sub-BIOS in U30, which the BIOS installs from
        # its EPROM in flash-initialise mode; the core has no EPROM, so only quick start
        boots = (("warm", ""),) if CONVERTER_SETS[s][3] == 3 else (("warm", ""), ("cold", " (first boot)"))
        for boot, suffix in boots:
            d = a.out if boot == "warm" and s not in ALT_OF else alt
            os.makedirs(d, exist_ok=True)
            p = os.path.join(d, fname + suffix + ".mra")
            flash = (FLASH_WARM if boot == "warm" else FLASH_COLD).format(set=s)
            with open(p, "w") as f:
                f.write(TEMPLATE.format(title=title_of(s) + suffix, set=s, rbf=a.rbf, year=year, mfr=mfr,
                                        cat=cat, players=players, joy=joy, buttons=buttons, flash=flash,
                                        rot="vertical (ccw)" if vert else "horizontal", cfg=config_byte(s)))
            print("wrote", os.path.relpath(p, a.out))
            n += 1
    print(n, "MRAs")

if __name__ == "__main__":
    main()
