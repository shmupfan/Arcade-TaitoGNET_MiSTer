#!/usr/bin/env python3
"""Compare the writes to the RF5C296 / ATA window (0x1FB00000-0x1FB0FFFF) and
to the card attribute window (0x1F200000-0x1F2FFFFF, flash bank 0) of a
system simulation (zn.log) with MAME 0.288's (oracle ata.log and flash.log),
in order: byte offset and byte value of every written byte.

    compare_ata.py <core zn.log> <MAME run dir> [max]
"""
import sys


def core_writes(path):
    out = []
    for line in open(path):
        p = line.split()
        if len(p) < 5 or p[1] != "'1'":
            continue
        a = int(p[2], 16)
        if not (0x1FB00000 <= a <= 0x1FB0FFFF or 0x1F200000 <= a <= 0x1F2FFFFF):
            continue
        be, d = int(p[3], 16), int(p[4], 16)
        for b in range(4):
            if (be >> b) & 1:
                out.append((a + b, (d >> (8 * b)) & 0xFF))
    return out


def mame_writes(run):
    ev = []
    for name in ("ata.log", "flash.log"):
        for line in open(f"{run}/{name}"):
            p = line.split()
            if len(p) < 6 or p[2] != "W":
                continue
            a = int(p[3], 16) & ~3    # flash.log logs the 16-bit lane address
            if name == "flash.log" and not (0x1F200000 <= a <= 0x1F2FFFFF):
                continue
            d, m = int(p[4], 16), int(p[5], 16)
            n = int(p[8][1:]) if name == "ata.log" and len(p) > 8 and p[8].startswith("x") else 1
            for _ in range(n):
                for b in range(4):
                    if (m >> (8 * b)) & 0xFF:
                        ev.append((float(p[0]), a + b, (d >> (8 * b)) & 0xFF))
    ev.sort(key=lambda e: e[0])
    return [(a, v) for _, a, v in ev]


def main(core, run, limit=10**9):
    c = core_writes(core)
    m = mame_writes(run)
    n = min(len(c), len(m), limit)
    bad = next((i for i in range(n) if c[i] != m[i]), None)
    print(f"core card writes {len(c)}, MAME {len(m)}, compared {n}, first difference {'none' if bad is None else bad}")
    if bad is not None:
        for i in range(max(0, bad - 4), min(n, bad + 6)):
            print(i, "core %08x %02x" % c[i], "MAME %08x %02x" % m[i])
    return bad is None


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sys.exit(0 if main(sys.argv[1], sys.argv[2], *(int(x) for x in sys.argv[3:])) else 1)
