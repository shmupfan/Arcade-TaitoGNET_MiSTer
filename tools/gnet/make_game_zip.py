#!/usr/bin/env python3
"""Prepare the per-game zip the G-NET MRAs load (docs/zn2_layer_design.md 13.5).

MiSTer cannot read the hard-disk CHDs MAME uses for the PC cards, so the
card image and its metadata are extracted once per game:

  tools/extract_card.sh <set>              (CHD -> sim/cards/<set>.img/.idnt/.cis/.key)
  tools/gnet/make_game_zip.py <set> <coh3002t.zip> <outdir> [--card-dir sim/cards] [--warm]

writes <outdir>/gnet_<set>.zip with
  <set>.img     raw card image, 40,960,000 bytes (MRA ioctl index 5)
  <set>.meta    1,024 bytes: IDNT at 000h, CIS at 200h, KEY at 300h (index 4)
  <set>.flash   with --warm only: 10 MB flash area as the core holds it in
                SDRAM 0x1000000-0x19FFFFF (U30 at 0, U27 at 0x200000, U56
                0x400000, U55 0x600000, U29 0x800000; FFh elsewhere), little-
                endian 16-bit words, built by tools/build_flash.py from the
                card and the BIOS zip (index 3). Without it the MRA loads
                flash.u30 and erased chips and the BIOS does the first-boot copy.

The Taito Zoom board (revision GNET_Z1_ZOOM, docs/zoom_board_design.md 14)
needs nothing more: it reads U27 (its program) and the wave flashes straight
from this flash area, 64-bit lines at SDRAM 0x1000000 + 0x200000 (U27) and
+ 0x400000 (waves), so a warm zip holds everything it plays, and a cold boot
gets them from the BIOS's first-boot copy before the game releases the Zoom.

The output is game data: keep it out of the repository (the default
location gnet_games/ is gitignored) and never distribute it.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def swap16(b):
    a = bytearray(b)
    a[0::2], a[1::2] = b[1::2], b[0::2]
    return bytes(a)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("bios_zip")
    ap.add_argument("outdir")
    ap.add_argument("--card-dir", default=os.path.join(ROOT, "sim", "cards"))
    ap.add_argument("--warm", action="store_true")
    a = ap.parse_args()

    cd = a.card_dir
    img = os.path.join(cd, a.set + ".img")
    idnt = open(os.path.join(cd, a.set + ".idnt"), "rb").read()
    cis = open(os.path.join(cd, a.set + ".cis"), "rb").read()
    key = open(os.path.join(cd, a.set + ".key"), "rb").read()
    if os.path.getsize(img) != 40960000:
        sys.exit(f"{img}: {os.path.getsize(img)} bytes, expected 40960000")
    if len(idnt) != 512 or len(cis) > 256 or len(key) != 5:
        sys.exit(f"metadata sizes: IDNT {len(idnt)}, CIS {len(cis)}, KEY {len(key)}")
    meta = bytearray(1024)
    meta[0:512] = idnt
    meta[0x200:0x200 + len(cis)] = cis
    meta[0x300:0x305] = key

    os.makedirs(a.outdir, exist_ok=True)
    out = os.path.join(a.outdir, f"gnet_{a.set}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(img, a.set + ".img")
        z.writestr(a.set + ".meta", bytes(meta))
        if a.warm:
            with tempfile.TemporaryDirectory() as t:
                subprocess.run([sys.executable, os.path.join(ROOT, "tools", "build_flash.py"), img, a.bios_zip, t],
                               check=True)
                area = bytearray(b"\xff" * 0xA00000)
                # build_flash.py writes MAME's NVRAM layout (big-endian words);
                # the core stores little-endian words like the ROM files
                for name, off, size in (("firm", 0x000000, 0x200000), ("zoomprog", 0x200000, 0x80000),
                                        ("wave0", 0x400000, 0x200000), ("wave1", 0x600000, 0x200000),
                                        ("wave2", 0x800000, 0x200000)):
                    p = os.path.join(t, name)
                    if os.path.exists(p):
                        d = swap16(open(p, "rb").read())
                        assert len(d) == size, (name, len(d))
                        area[off:off + size] = d
                z.writestr(a.set + ".flash", bytes(area))
    print("wrote", out)


if __name__ == "__main__":
    main()
