#!/usr/bin/env python3
"""Compare the web converter's gnet_<set>.zip files with reference zips (for
example the command-line converter's output, made with chdman or chd.py):
every member (.img, .meta, .flash) must be byte-identical. Python's zipfile
reads both sides and checks each member's CRC32.

  python3 web/converter/test/compare_zips.py <web output folder> <reference folder>
"""
import glob
import hashlib
import os
import sys
import zipfile


def members(path):
    with zipfile.ZipFile(path) as z:
        if z.testzip() is not None:
            raise SystemExit(f"{path}: bad CRC")
        return {i.filename: hashlib.sha1(z.read(i)).hexdigest() for i in z.infolist()}


def main():
    web, ref = sys.argv[1:3]
    bad = 0
    n = 0
    for p in sorted(glob.glob(os.path.join(web, "gnet_*.zip"))):
        r = os.path.join(ref, os.path.basename(p))
        if not os.path.exists(r):
            print(f"{os.path.basename(p)}: no reference zip")
            continue
        a, b = members(p), members(r)
        same = a == b
        n += 1
        bad += not same
        detail = ", ".join(f"{k} {'same' if a.get(k) == v else 'DIFFERENT'}" for k, v in sorted(b.items()))
        extra = sorted(set(a) - set(b))
        print(f"{os.path.basename(p)}: {'IDENTICAL' if same else 'DIFFERENT'} ({detail}"
              f"{', extra ' + ' '.join(extra) if extra else ''})")
    print(f"{n - bad} of {n} identical")
    sys.exit(1 if bad or not n else 0)


if __name__ == "__main__":
    main()
