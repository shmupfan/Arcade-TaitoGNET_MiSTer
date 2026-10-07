#!/usr/bin/env python3
"""Make the game zips the Taito G-NET MiSTer core needs, from your own MAME files.

MiSTer cannot read MAME's hard-disk CHD files, so each game's PC card is
converted once on a computer. You need Python 3 only: the CHD files are read
by chd.py (in this folder). MAME's chdman is optional: pass --chdman <path>
to have it read the CHDs instead (the output is the same).

  python3 gnet_tester_zips.py --roms <your MAME roms folder> --out <output folder>
          [--sets raycris shikigam ...] [--chdman <path to chdman>] [--no-quick]

The roms folder must hold the MAME 0.288 sets as MAME uses them:
  coh3002t.zip                (the G-NET BIOS set)
  <set>/<chd>.chd             (the game's card image, e.g. shikigam/shikigam.chd;
                               some CHDs are named differently from their set,
                               e.g. chaoshea/chaosheat.chd, and a clone's CHD may
                               be in its parent's folder)

Every MAME 0.288 G-NET set on a Taito card is known: Taito Type 1 and Type 2
PC cards and the Taito CompactFlash card (MAME taitopccard1, taitopccard2,
taitocf). The 2011 conversions (plain ATA card) and Mawasunda are not.

For every game it finds, it writes <out>/gnet_<set>.zip with
  <set>.img     the card image (its size varies by card: 38.6 MB to 64.2 MB)
  <set>.meta    the card's identity data, unlock key and card type (1,024 bytes;
                IDENTIFY at 000h, CIS at 200h, key at 300h, card type at 3F0h:
                01 Type 1, 02 Type 2, 03 CompactFlash)
  <set>.flash   the flash chips as the BIOS leaves them after its first-boot
                copy, built from your card and BIOS files (10 MB), used by the
                "quick start" MRAs (skip it with --no-quick)
Copy every gnet_<set>.zip and your coh3002t.zip to /media/fat/games/mame/ on
the MiSTer SD card.

The output is game data made from your own files: keep it to yourself.
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(1, os.path.dirname(HERE))      # in the repository build_flash.py is in tools/
import build_flash  # noqa: E402  (tester package: same folder)
import chd  # noqa: E402  (chd.py: same folder here and in the tester package)

# set -> (title, CHD name, CHD SHA1, card type, parent set), from MAME 0.288
# taitogn.cpp (card type: 1 taitopccard1, 2 taitopccard2, 3 taitocf)
SETS = {
    "chaoshea": ('Chaos Heat (V2.09O 1998/10/02 17:00)', "chaosheat", "c13b7d7025eee05f1f696d108801c7bafb3f1356", 1, ""),
    "chaosheaj": ('Chaos Heat (V2.08J 1998/09/25 17:00)', "chaosheatj", "2f211ac08675ea8ec33c7659a13951db94eaa627", 1, "chaoshea"),
    "raycris": ('Ray Crisis (V2.03O 1998/11/15 15:43)', "raycris", "9d255710c87c3286542d357820d828807cc6ca07", 1, ""),
    "raycrisj": ('Ray Crisis (V2.03J 1998/11/15 15:43)', "raycrisj", "015cb0e6c4421cc38809de28c4793b4491386aee", 1, "raycris"),
    "spuzbobl": ('Super Puzzle Bobble (V2.05O 1999/2/24 18:00)', "spuzbobl", "1b1c72fb7e5656021485fefaef8f2ba48e2b4ea8", 2, ""),
    "spuzboblj": ('Super Puzzle Bobble (V2.04J 1999/2/17 02:10)', "spuzbobj", "dac433cf88543d2499bf797d7406b82ae4338726", 2, "spuzbobl"),
    "gobyrc": ('Go By RC (V2.03O 1999/05/25 13:31)', "gobyrc", "0bee1f495fc8b033fd56aad9260ae94abb35eb58", 2, ""),
    "rcdego": ('RC De Go (V2.03J 1999/05/22 19:29)', "rcdego", "9e177f2a3954cfea0c8c5a288e116324d10f5dd1", 1, "gobyrc"),
    "flipmaze": ('Flip Maze (V2.04J 1999/09/02 20:00)', "flipmaze", "423b6c06f4f2d9a608ce20b61a3ac11687d22c40", 1, ""),
    "shikigam": ('Shikigami no Shiro (V2.03J 2001/08/07 18:11)', "shikigam", "fa49a0bc47f5cb7c30d7e49e2c3696b21bafb840", 1, ""),
    "shikigama": ('Shikigami no Shiro - internal build (V1.02J 2001/09/27 18:45)', "shikigama", "a6fe194c86730963301be9710782ca4ac1bf3e8d", 1, ""),
    "sianniv": ('Space Invaders Anniversary (V2.02J 2003/09/12 20:00)', "sianniv", "1e08b813190a9e1baf29bc16884172d6c8da7ae3", 1, ""),
    "kollon": ('Kollon (V2.04JA 2003/11/01 12:00)', "kollon", "d8ea5b5b0ee99004b16ef89883e23de6c7ddd7ce", 1, ""),
    "kollonc": ('Kollon (V2.04JC 2003/11/01 12:00)', "kollonc", "ce62181659701cfb8f7c564870ab902be4d8e060", 3, "kollon"),
    "otenamih": ('Otenami Haiken (V2.04J 1999/02/01 18:00:00)', "otenamih", "b3babe3a1876c43745616ee1e7d87276ce7dad0b", 1, ""),
    "psyvaria": ('Psyvariar -Medium Unit- (V2.02O 2000/02/22 13:00)', "psyvaria", "3c7fca5180356190a8bf94b22a847fdd2e6a4e13", 1, ""),
    "psyvarij": ('Psyvariar -Medium Unit- (V2.04J 2000/02/15 11:00)', "psyvarij", "b981a42a10069322b77f7a268beae1d409b4156d", 1, "psyvaria"),
    "psyvarrv": ('Psyvariar -Revision- (V2.04J 2000/08/11 22:00)', "psyvarrv", "277c4f52502bcd7acc1889840962ec80d56465f3", 1, ""),
    "zokuoten": ('Zoku Otenamihaiken (V2.05J 2003/05/12 18:00)', "zokuoten", "116e58c90f39a3c18ca6fe0216c998ba02c58814", 2, ""),
    "zokuotena": ('Zoku Otenamihaiken (V2.03J 2001/02/16 16:00)', "zokuotena", "5ce13db00518f96af64935176c71ec68d2a51938", 1, "zokuoten"),
    "zooo": ('Zooo (V2.01JA 2004/04/13 12:00)', "zooo", "e275b3141b2bc49142990e6b497a5394a314a30b", 1, ""),
    "otenamhf": ('Otenami Haiken Final (V2.07JC 2005/04/20 15:36)', "otenamhf", "5b15c33bf401e5546d78e905f538513d6ffcf562", 3, ""),
    "mahjngoh": ('Mahjong Oh (V2.06J 1999/11/23 08:52:22)', "mahjngoh", "3ef1110d15582d7c0187438d7ad61765dd121cff", 1, ""),
    "shanghss": ('Shanghai Shoryu Sairin (V2.03J 2000/05/26 12:45:28)', "shanghss", "7964f71ec5c81d2120d83b63a82f97fbad5a8e6d", 1, ""),
    "soutenry": ('Soutenryu (V2.07J 2000/12/14 11:13:02)', "soutenry", "9204d0be833d29f37b8cd3fbdf09da69b622254b", 1, ""),
    "usagi": ('Usagi (V2.02J 2001/10/02 12:41:19)', "usagi", "edf9dd271957f6cb06feed238ae21100514bef8e", 2, ""),
    "shangtou": ('Shanghai Sangokuhai Tougi (Ver 2.01J 2002/01/18 18:26:58)', "shanghaito", "9901db5a9aae77e3af4157aa2c601eaab5b7ca85", 1, ""),
    "nightrai": ('Night Raid (V2.03J 2001/02/26 17:00)', "nightrai", "74d0458f851cbcf10453c5cc4c47bb4388244cdf", 1, ""),
    "otenki": ('Otenki Kororin (V2.01J 2001/07/02 10:00)', "otenki", "7e745ca4c4570215f452fd09cdd56a42c39caeba", 1, ""),
    "xiistag": ('XII Stag (V2.01J 2002/6/26 22:27)', "xiistag", "586e37c8d926293b2bd928e5f0d693910cfb05a2", 1, ""),
}
CARD_TYPE_NAME = {1: "Type 1", 2: "Type 2", 3: "CompactFlash"}

# files the MRAs load from coh3002t.zip, with their CRC32 in MAME 0.288
BIOS_PARTS = {"m534002c-60.ic353": 0x03967FA7, "tt10.ic652": 0x235510B1, "tt16.u17": 0x6BB167B3,
              "flash.u30": 0xC48C8236}
CARD_MAX = 64 << 20        # the core's card window in DDR3 (64 MB)


def fail(msg):
    sys.exit("error: " + msg)


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode:
        fail(f"{' '.join(cmd)} failed:\n{r.stdout}")
    return r.stdout


def check_bios(path):
    if not os.path.exists(path):
        fail(f"{path} not found (the MAME 0.288 coh3002t set)")
    with zipfile.ZipFile(path) as z:
        crcs = {i.filename: i.CRC for i in z.infolist()}
    for name, crc in BIOS_PARTS.items():
        if crcs.get(name) != crc:
            fail(f"{path}: {name} missing or not the MAME 0.288 version (CRC {crcs.get(name, 0):08x}, want {crc:08x})")


class ChdmanCard:
    """the CHD read with MAME's chdman (--chdman)"""

    def __init__(self, chdman, path):
        self.chdman, self.path = chdman, path
        self.sha1 = self.logical_bytes = None
        for line in run([chdman, "info", "-i", path]).splitlines():
            k, _, v = line.strip().partition(":")
            if k == "SHA1":
                self.sha1 = v.strip().lower()
            elif k == "Logical size":
                self.logical_bytes = int(v.split()[0].replace(",", ""))

    def extract(self, img):
        run([self.chdman, "extractraw", "-f", "-i", self.path, "-o", img])

    def metadata(self, tag, t):
        p = os.path.join(t, "meta.bin")
        run([self.chdman, "dumpmeta", "-f", "-i", self.path, "-t", tag, "-o", p])
        with open(p, "rb") as f:
            return f.read()


class PyCard:
    """the CHD read with chd.py (default)"""

    def __init__(self, path):
        try:
            self.c = chd.open(path)
        except chd.ChdError as e:
            fail(f"{path}: {e}")
        self.path = path
        self.sha1, self.logical_bytes = self.c.sha1, self.c.logical_bytes

    def extract(self, img):
        h = hashlib.sha1()
        try:
            with open(img, "wb") as f:
                for b in self.c.iter_raw():
                    h.update(b)
                    f.write(b)
        except chd.ChdError as e:
            fail(f"{self.path}: {e}")
        if h.hexdigest() != self.c.raw_sha1:
            fail(f"{self.path}: card image SHA1 {h.hexdigest()} is not the CHD's data SHA1 {self.c.raw_sha1}")

    def metadata(self, tag, t):
        try:
            return self.c.metadata(tag)
        except chd.ChdError as e:
            fail(f"{self.path}: {e}")


def find_chd(roms, s):
    title, name, sha1, ctype, parent = SETS[s]
    for d in (s, parent):
        if d:
            p = os.path.join(roms, d, name + ".chd")
            if os.path.exists(p):
                return p
    return None


def make(chdman, roms, out, s, quick):
    title, _, sha1, ctype, _ = SETS[s]
    chd_path = find_chd(roms, s)
    if not chd_path:
        print(f"  {s}: no CHD found, skipped")
        return False
    card = ChdmanCard(chdman, chd_path) if chdman else PyCard(chd_path)
    got, card_bytes = card.sha1, card.logical_bytes
    if got != sha1:
        other = [k for k, v in SETS.items() if v[2] == got]
        if other:
            ctype = SETS[other[0]][3]
            print(f"  {s}: warning, this CHD is MAME 0.288's {other[0]} (SHA1 {got}), not {s}; "
                  f"using its card type ({CARD_TYPE_NAME[ctype]})")
        else:
            print(f"  {s}: warning, CHD SHA1 {got} is not MAME 0.288's {sha1}; continuing")
    if not card_bytes or card_bytes > CARD_MAX or card_bytes % 512:
        fail(f"{s}: card size {card_bytes} bytes is not a whole number of sectors up to {CARD_MAX}")
    with tempfile.TemporaryDirectory() as t:
        img = os.path.join(t, s + ".img")
        card.extract(img)
        if os.path.getsize(img) != card_bytes:
            fail(f"{s}: card image is {os.path.getsize(img)} bytes, the CHD says {card_bytes}")
        meta = bytearray(1024)
        parts = {}
        for tag, key in (("IDNT", "idnt"), ("KEY ", "key"), ("CIS ", "cis")):
            parts[key] = card.metadata(tag, t)
        if len(parts["idnt"]) != 512 or len(parts["key"]) != 5 or len(parts["cis"]) > 256:
            fail(f"{s}: unexpected card metadata sizes {[len(v) for v in parts.values()]}")
        meta[0:512] = parts["idnt"]
        meta[0x200:0x200 + len(parts["cis"])] = parts["cis"]
        meta[0x300:0x305] = parts["key"]
        meta[0x3f0] = ctype
        lba = int.from_bytes(parts["idnt"][120:124], "little")   # IDENTIFY words 60-61
        if lba * 512 != card_bytes:
            fail(f"{s}: IDENTIFY gives {lba} sectors, the card has {card_bytes // 512}")
        os.makedirs(out, exist_ok=True)
        zpath = os.path.join(out, f"gnet_{s}.zip")
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(img, s + ".img")
            z.writestr(s + ".meta", bytes(meta))
            if quick:
                imgs, _ = build_flash.build(img, os.path.join(roms, "coh3002t.zip"), cf=ctype == 3)
                area = bytearray(b"\xff" * 0xA00000)
                for name, off, size in (("firm", 0x000000, 0x200000), ("zoomprog", 0x200000, 0x80000),
                                        ("wave0", 0x400000, 0x200000), ("wave1", 0x600000, 0x200000),
                                        ("wave2", 0x800000, 0x200000)):
                    if name in imgs:
                        d = build_flash.swap16(imgs[name])      # MAME NVRAM words -> the core's order
                        if len(d) != size:
                            fail(f"{s}: {name} is {len(d)} bytes, expected {size}")
                        area[off:off + size] = d
                z.writestr(s + ".flash", bytes(area))
    print(f"  {s}: wrote {zpath} ({title}, {CARD_TYPE_NAME[ctype]} card, {card_bytes:,} bytes)")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--roms", required=True, help="your MAME roms folder")
    ap.add_argument("--out", required=True, help="folder for the gnet_<set>.zip files")
    ap.add_argument("--sets", nargs="*", default=list(SETS), help="sets to convert (default: every known set found)")
    ap.add_argument("--chdman", default=None,
                    help="optional: read the CHDs with MAME's chdman at this path instead of chd.py")
    ap.add_argument("--no-quick", action="store_true", help="leave out the quick-start flash data")
    a = ap.parse_args()
    chdman = None
    if a.chdman:
        chdman = shutil.which(a.chdman) or (a.chdman if os.path.isfile(a.chdman) else None)
        if not chdman:
            fail(f"chdman not found at {a.chdman}")
    for s in a.sets:
        if s not in SETS:
            fail(f"unknown set {s}; known: {', '.join(SETS)}")
    check_bios(os.path.join(a.roms, "coh3002t.zip"))
    print("coh3002t.zip OK")
    made = sum(make(chdman, a.roms, a.out, s, not a.no_quick) for s in a.sets)
    print(f"{made} game zip(s) written to {a.out}")
    print("Copy them and coh3002t.zip to /media/fat/games/mame/ on the MiSTer SD card.")


if __name__ == "__main__":
    main()
