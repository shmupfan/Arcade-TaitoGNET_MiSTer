#!/usr/bin/env python3
"""Vectors for the zn2_io replay testbench (sim/zn2/tb_zn2_io_replay.vhd)
from a ZN-2 map trace (tools/mame/zn2_map_trace.lua, zn2map.log).

  zn2io_vectors.py <zn2map.log> <at28c16 NVRAM file> <outdir>

Writes <outdir>/zn2io.vec, one access per line "R|W <word addr hex> <be bin>
<data hex>" (address as an offset from 0x1F000000, data lane-positioned as
MAME logged it), and <outdir>/ee.hex (2048 lines) with the EEPROM contents
MAME started from. Folded repeats (xN) are replayed once: every logged
register here reads the same value again on a repeat. The output is
game-derived: keep it under sim/ (gitignored).
"""
import sys

NAMES = {"p1p2svsys", "p3p4", "boardcfg", "znsecsel", "coin", "x1fa40000", "eeprom", "x1fb20000"}


def main(log, nv, out):
    n = 0
    with open(f"{out}/zn2io.vec", "w") as f:
        for line in open(log):
            p = line.split()
            if len(p) < 6 or p[1] not in NAMES:
                continue
            d, a, v, m = p[2], int(p[3], 16), int(p[4], 16), int(p[5], 16)
            be = "".join("1" if (m >> (8 * i)) & 0xFF else "0" for i in (3, 2, 1, 0))
            f.write(f"{d} {(a - 0x1F000000) & 0xFFFFFC:06x} {be} {v:08x}\n")
            n += 1
    # MAME's at28c16 NVRAM file is the 2048 data bytes followed by the 32
    # identification bytes (at28c16.cpp AT28C16_ID_BYTES)
    data = open(nv, "rb").read()
    assert len(data) in (2048, 2080), len(data)
    data = data[:2048]
    with open(f"{out}/ee.hex", "w") as f:
        f.write("\n".join(f"{b:02x}" for b in data) + "\n")
    print(f"{n} accesses")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(__doc__)
        sys.exit(2)
    main(*sys.argv[1:])
