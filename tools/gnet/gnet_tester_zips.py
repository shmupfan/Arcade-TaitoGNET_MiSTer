#!/usr/bin/env python3
"""Make the game zips the Taito G-NET MiSTer core needs, from your own MAME files.

MiSTer cannot read MAME's hard-disk CHD files, so each game's PC card is
converted once on a computer. You need Python 3 and MAME's chdman (it comes
with MAME; on Windows chdman.exe is in the MAME folder).

  python3 gnet_tester_zips.py --roms <your MAME roms folder> --out <output folder>
          [--sets raycris shikigam ...] [--chdman <path to chdman>] [--no-quick]

The roms folder must hold the MAME 0.288 sets as MAME uses them:
  coh3002t.zip                (the G-NET BIOS set)
  <set>/<set>.chd             (the game's card image, e.g. shikigam/shikigam.chd)

For every game it finds, it writes <out>/gnet_<set>.zip with
  <set>.img     the card image (40,960,000 bytes)
  <set>.meta    the card's identity data and unlock key (1,024 bytes)
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

# set -> (title, CHD SHA1 in MAME 0.288)
SETS = {
    "raycris": ("Ray Crisis", "9d255710c87c3286542d357820d828807cc6ca07"),
    "psyvaria": ("Psyvariar -Medium Unit-", "3c7fca5180356190a8bf94b22a847fdd2e6a4e13"),
    "psyvarrv": ("Psyvariar -Revision-", "277c4f52502bcd7acc1889840962ec80d56465f3"),
    "xiistag": ("XII Stag", "586e37c8d926293b2bd928e5f0d693910cfb05a2"),
    "shikigam": ("Shikigami no Shiro", "fa49a0bc47f5cb7c30d7e49e2c3696b21bafb840"),
    "nightrai": ("Night Raid", "74d0458f851cbcf10453c5cc4c47bb4388244cdf"),
}
# files the MRAs load from coh3002t.zip, with their CRC32 in MAME 0.288
BIOS_PARTS = {"m534002c-60.ic353": 0x03967FA7, "tt10.ic652": 0x235510B1, "tt16.u17": 0x6BB167B3,
              "flash.u30": 0xC48C8236}
CARD_SIZE = 40960000


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


def chd_sha1(chdman, chd):
    for line in run([chdman, "info", "-i", chd]).splitlines():
        if line.strip().startswith("SHA1:"):
            return line.split(":", 1)[1].strip().lower()
    return None


def make(chdman, roms, out, s, quick):
    title, sha1 = SETS[s]
    chd = os.path.join(roms, s, s + ".chd")
    if not os.path.exists(chd):
        print(f"  {s}: no {chd}, skipped")
        return False
    got = chd_sha1(chdman, chd)
    if got != sha1:
        print(f"  {s}: warning, CHD SHA1 {got} is not MAME 0.288's {sha1}; continuing")
    with tempfile.TemporaryDirectory() as t:
        img = os.path.join(t, s + ".img")
        run([chdman, "extractraw", "-f", "-i", chd, "-o", img])
        if os.path.getsize(img) != CARD_SIZE:
            fail(f"{s}: card image is {os.path.getsize(img)} bytes, expected {CARD_SIZE}")
        meta = bytearray(1024)
        parts = {}
        for tag, key in (("IDNT", "idnt"), ("KEY ", "key"), ("CIS ", "cis")):
            p = os.path.join(t, key)
            run([chdman, "dumpmeta", "-f", "-i", chd, "-t", tag, "-o", p])
            parts[key] = open(p, "rb").read()
        if len(parts["idnt"]) != 512 or len(parts["key"]) != 5 or len(parts["cis"]) > 256:
            fail(f"{s}: unexpected card metadata sizes {[len(v) for v in parts.values()]}")
        meta[0:512] = parts["idnt"]
        meta[0x200:0x200 + len(parts["cis"])] = parts["cis"]
        meta[0x300:0x305] = parts["key"]
        os.makedirs(out, exist_ok=True)
        zpath = os.path.join(out, f"gnet_{s}.zip")
        with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
            z.write(img, s + ".img")
            z.writestr(s + ".meta", bytes(meta))
            if quick:
                imgs, _ = build_flash.build(img, os.path.join(roms, "coh3002t.zip"))
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
    print(f"  {s}: wrote {zpath} ({title})")
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--roms", required=True, help="your MAME roms folder")
    ap.add_argument("--out", required=True, help="folder for the gnet_<set>.zip files")
    ap.add_argument("--sets", nargs="*", default=list(SETS), help="sets to convert (default: all six)")
    ap.add_argument("--chdman", default=None, help="path to chdman if it is not on the PATH")
    ap.add_argument("--no-quick", action="store_true", help="leave out the quick-start flash data")
    a = ap.parse_args()
    chdman = a.chdman or shutil.which("chdman") or shutil.which("chdman.exe")
    if not chdman:
        fail("chdman not found: install MAME, or pass --chdman <path>")
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
