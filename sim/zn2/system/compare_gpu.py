#!/usr/bin/env python3
"""Compare the CPU's GP0/GP1 writes of a system simulation (gpu.log from
tb_zn2_system) with MAME 0.288's (oracle gpu.log, CPU writes to 0x1F801810
and 0x1F801814; folded repeats "xN" expanded). DMA transfers to the GPU are
not in either list.

    compare_gpu.py <core gpu.log> <MAME gpu.log> [max]
"""
import sys


def core(path):
    out = []
    for line in open(path):
        p = line.split()
        if len(p) == 3:
            out.append((p[1], int(p[2], 16)))
    return out


def mame(path, limit):
    out = []
    for line in open(path):
        p = line.split()
        if len(p) < 6 or p[2] != "W":
            continue
        a = int(p[3], 16)
        if a not in (0x1F801810, 0x1F801814):
            continue
        n = int(p[6][1:]) if len(p) > 6 and p[6].startswith("x") else 1
        out.extend([("GP0" if a == 0x1F801810 else "GP1", int(p[4], 16))] * n)
        if len(out) >= limit:
            break
    return out


def main(c_path, m_path, limit=10**9):
    c = core(c_path)
    m = mame(m_path, max(limit, len(c)) + 10)
    n = min(len(c), len(m), limit)
    bad = next((i for i in range(n) if c[i] != m[i]), None)
    print(f"core GPU writes {len(c)}, compared {n}, first difference {'none' if bad is None else bad}")
    if bad is not None:
        for i in range(max(0, bad - 3), min(n, bad + 6)):
            print(i, "core", c[i][0], "%08x" % c[i][1], "MAME", m[i][0], "%08x" % m[i][1])
    return bad is None


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    sys.exit(0 if main(sys.argv[1], sys.argv[2], *(int(x) for x in sys.argv[3:])) else 1)
