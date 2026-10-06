#!/usr/bin/env python3
"""Write the release MRAs for the six target sets into releases/.

  tools/gnet/make_release_mras.py [--rbf TaitoGNET] [--out releases] [--boot warm|cold] [--suffix " (first boot)"]

The release layout (releases/README.md): --boot warm without a suffix
writes the main MRAs into releases/; --boot cold --suffix " (first boot)"
--alternatives writes each first-boot MRA into
releases/_alternatives/_<game>/.

--boot cold loads only flash.u30 from coh3002t.zip into the flash area (the
other chips erased), so the BIOS does its first-boot copy of the card into
the flash chips (about 2.5 minutes) on every start; it needs no <set>.flash
in gnet_<set>.zip. --boot warm (default) loads <set>.flash.

Fields follow the MiSTer arcade MRA layout used by the Dooyong core
(dooyong-mister/releases): name, setname, rbf, mameversion, year,
manufacturer, category, players, joystick, rotation, switches, buttons,
roms, nvram. Per-set data is from MAME 0.288 (`mame -listxml`,
taitogn.cpp GAME lines, docs/mame_sources.md); docs/gnet_games_test_matrix.md
has the table.

Loads (docs/zn2_layer_design.md 13.5, docs/m4_shell.md 3):
  index 0  BIOS m534002c-60.ic353 (coh3002t.zip)
  index 2  CAT702 keys tt10.ic652, tt16.u17 (coh3002t.zip)
  index 3  flash area <set>.flash (gnet_<set>.zip, warm: the flash chips as
           the BIOS leaves them after the first-boot copy)
  index 4  card metadata <set>.meta, index 5 card image <set>.img
  index 6  EEPROM, 2048 bytes (nvram)
  index 7  game configuration byte: bit 0 = vertical set (MAME ROT270)
DIP switches: S551, active low, all Off by default (MAME DSW 0Fh).
gnet_<set>.zip is made from the user's own MAME set with
tools/gnet/make_game_zip.py --warm (MiSTer cannot read the CHD).
"""
import argparse
import os

SETS = [
    # set, file name, title (MAME description without the time), year, manufacturer, ROT270
    ("raycris", "Ray Crisis (V2.03O)", "Ray Crisis (V2.03O 1998/11/15)", "1998", "Taito", False),
    ("psyvaria", "Psyvariar -Medium Unit- (V2.02O)", "Psyvariar -Medium Unit- (V2.02O 2000/02/22)", "2000", "Success", True),
    ("psyvarrv", "Psyvariar -Revision- (V2.04J)", "Psyvariar -Revision- (V2.04J 2000/08/11)", "2000", "Success", True),
    ("xiistag", "XII Stag (V2.01J)", "XII Stag (V2.01J 2002/6/26)", "2002", "Triangle Service", True),
    ("shikigam", "Shikigami no Shiro (V2.03J)", "Shikigami no Shiro (V2.03J 2001/08/07)", "2001", "Alfa System / Taito", True),
    ("nightrai", "Night Raid (V2.03J)", "Night Raid (V2.03J 2001/02/26)", "2001", "Takumi", False),
]

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
    <category>Shooter</category>
    <players>2</players>
    <joystick>8-way</joystick>
    <rotation>{rot}</rotation>
    <switches default="0F">
        <dip name="Unknown (S551:1)" bits="0" ids="On,Off" />
        <dip name="Service Mode (S551:2)" bits="1" ids="On,Off" />
        <dip name="Unknown (S551:3)" bits="2" ids="On,Off" />
        <dip name="Test Mode (S551:4)" bits="3" ids="On,Off" />
    </switches>
    <buttons names="Button 1,Button 2,Button 3,Start,Coin,Service,Test,Pause" default="A,B,X,Start,Select,L,R" />
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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rbf", default="TaitoGNET")
    ap.add_argument("--boot", choices=("warm", "cold"), default="warm")
    ap.add_argument("--suffix", default="", help="added to each file name, e.g. ' (first boot)'")
    ap.add_argument("--alternatives", action="store_true",
                    help="write each MRA into <out>/_alternatives/_<game>/")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__)))), "releases"))
    a = ap.parse_args()
    for s, fname, title, year, mfr, vert in SETS:
        d = os.path.join(a.out, "_alternatives", "_" + fname.split(" (")[0]) if a.alternatives else a.out
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, fname + a.suffix + ".mra")
        flash = (FLASH_WARM if a.boot == "warm" else FLASH_COLD).format(set=s)
        open(p, "w").write(TEMPLATE.format(title=title + a.suffix, set=s, rbf=a.rbf, year=year, mfr=mfr, flash=flash,
                                           rot="vertical (ccw)" if vert else "horizontal", cfg=int(vert)))
        print("wrote", p)


if __name__ == "__main__":
    main()
