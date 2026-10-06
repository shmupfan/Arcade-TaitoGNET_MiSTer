#!/usr/bin/env python3
"""Check a G-NET hardware test package before it goes to the MiSTer.

  tools/gnet/check_test_package.py [<package dir>]   (default gnet_games/test_z1)

The package holds _Arcade/*.mra, _Arcade/cores/<rbf>_<date>.rbf and
games/mame/*.zip, laid out as on the SD card. For every MRA it checks:
  - the file parses as XML and has setname, rbf and at least one rom;
  - a core <rbf>_*.rbf is in _Arcade/cores;
  - every named part exists in its zip, with the CRC when the MRA gives one;
    parts without a name are inline hex data (times repeat= when given),
    and a rom without a zip may hold only inline data;
  - the bytes each ioctl index receives match docs/zn2_layer_design.md
    13.5: 0 BIOS 524,288; 2 CAT702 keys 16; 3 flash area 10,485,760;
    4 card metadata 1,024; 5 card 40,960,000; 7 game configuration 1.
Then it lists zips in games/mame that no MRA uses. Exit status 1 on any error.
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIZES = {"0": 524288, "2": 16, "3": 0xA00000, "4": 1024, "7": 1}
CARD_MAX = 64 << 20   # index 5, the card image: whole sectors, up to the core's 64 MB window


def main():
    pkg = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "gnet_games", "test_z1")
    zdir = os.path.join(pkg, "games", "mame")
    cores = [os.path.basename(p) for p in glob.glob(os.path.join(pkg, "_Arcade", "cores", "*.rbf"))]
    zips, used, errors = {}, set(), 0
    mras = sorted(glob.glob(os.path.join(pkg, "_Arcade", "*.mra")))
    for mra in mras:
        name, errs = os.path.basename(mra), []
        try:
            root = ET.parse(mra).getroot()
        except ET.ParseError as e:
            print(f"FAIL {name}: XML {e}")
            errors += 1
            continue
        setname, rbf = root.findtext("setname"), root.findtext("rbf")
        if not setname or not rbf or root.find("rom") is None:
            errs.append("missing setname, rbf or rom")
        # MiSTer matches the core name case-insensitively, with or without the "Arcade-" prefix
        if rbf and not any(c.lower().startswith((rbf.lower() + "_", "arcade-" + rbf.lower() + "_")) for c in cores):
            errs.append(f"no core {rbf}_*.rbf in _Arcade/cores")
        for rom in root.findall("rom"):
            idx, zname, total = rom.get("index"), rom.get("zip"), 0
            members = None
            if zname:
                used.add(zname)
                if zname not in zips:
                    zp = os.path.join(zdir, zname)
                    zips[zname] = ({i.filename: i for i in zipfile.ZipFile(zp).infolist()}
                                   if os.path.exists(zp) else None)
                members = zips[zname]
                if members is None:
                    errs.append(f"index {idx}: {zname} not in games/mame")
                    continue
            for part in rom.findall("part"):
                if part.get("name") is None:
                    # inline hex data, repeated when the part has repeat=
                    try:
                        data = bytes.fromhex("".join((part.text or "").split()))
                    except ValueError:
                        errs.append(f"index {idx}: inline part is not hex: {part.text!r}")
                        continue
                    total += len(data) * (int(part.get("repeat"), 0) if part.get("repeat") else 1)
                    continue
                if members is None:
                    errs.append(f"index {idx}: part {part.get('name')} without a zip")
                    continue
                info = members.get(part.get("name"))
                if info is None:
                    errs.append(f"index {idx}: {part.get('name')} not in {zname}")
                    continue
                total += info.file_size
                crc = part.get("crc")
                if crc and int(crc, 16) != info.CRC:
                    errs.append(f"index {idx}: {part.get('name')} CRC {info.CRC:08x}, MRA says {crc}")
            if idx in SIZES and total != SIZES[idx]:
                errs.append(f"index {idx}: {total} bytes, expected {SIZES[idx]}")
            if idx == "5" and (total == 0 or total % 512 or total > CARD_MAX):
                errs.append(f"index 5: {total} bytes, expected whole 512-byte sectors up to {CARD_MAX}")
        print(("FAIL " if errs else "ok   ") + f"{name} ({setname}, {rbf})")
        for e in errs:
            print("       " + e)
        errors += bool(errs)
    for z in sorted(set(os.listdir(zdir)) - used if os.path.isdir(zdir) else []):
        print(f"note: games/mame/{z} is not used by any MRA")
    print(f"{len(mras)} MRAs, {errors} with errors")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
