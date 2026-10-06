#!/usr/bin/env python3
"""Match each VRAM dump of a system simulation (vram_<ms>.bin) to the MAME
VRAM dumps of an oracle run (vram_<frame>.bin, ORACLE_VRAM_DUMPS): for every
core dump, the MAME frames with the fewest differing pixels (colour bits,
whole 2 MB VRAM).

    match_vram.py <run dir> <MAME oracle dir>
"""
import glob
import os
import sys

import numpy as np


def num(path):
    return int(os.path.basename(path)[5:-4])


def main(run, mame):
    ms = {num(p): np.fromfile(p, "<u2")[:1 << 20].reshape(1024, 1024) & 0x7FFF
          for p in glob.glob(os.path.join(mame, "vram_*.bin"))}
    for p in sorted(glob.glob(os.path.join(run, "vram_*.bin")), key=num):
        core = np.fromfile(p, "<u2")[:1 << 20].reshape(1024, 1024) & 0x7FFF
        best = sorted((int((core != m).sum()), f) for f, m in ms.items())[:3]
        print(f"core {num(p):5d} ms:", ", ".join(f"MAME frame {f} differs in {d} pixels" for d, f in best))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
