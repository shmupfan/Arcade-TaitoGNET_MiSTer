#!/usr/bin/env python3
"""Compare the core's writes to the flash bank window (0x1F000000 to
0x1F7FFFFF: flash command sequences, card attribute writes) with MAME's
(tools/mame/oracle.lua flash.log), byte by byte in order, runs of identical
accesses folded. Same lane convention as sim/zn2/system/compare_ata.py on the
zn2-layer branch.

    compare_flash.py <core zn.log> <MAME flash.log>
"""
import sys


def fold(s):
    """s: (time, bytes) per access, bytes = ((address, value), ...). Runs of
    identical accesses fold to one (MAME's log folds them), then the bytes
    are listed one by one."""
    out, last = [], None
    for t, bs in s:
        if bs != last:
            out += [(t, a, v) for a, v in bs]
        last = bs
    return out


def core(path):
    ev = []
    for line in open(path):
        p = line.split()
        if len(p) < 5 or p[1] != '1':
            continue
        a = int(p[2], 16)
        if not 0x1F000000 <= a < 0x1F800000:
            continue
        be, d = int(p[3], 16), int(p[4], 16)
        ev.append((float(p[0]) / 1e6, tuple((a + b, (d >> (8 * b)) & 0xFF) for b in range(4) if (be >> b) & 1)))
    return fold(ev)


def mame(path):
    ev = []
    for line in open(path):
        p = line.split()
        if len(p) < 6 or p[2] != 'W':
            continue
        a = int(p[3], 16) & ~3
        if not 0x1F000000 <= a < 0x1F800000:
            continue
        d, m = int(p[4], 16), int(p[5], 16)
        ev.append((float(p[0]), tuple((a + b, (d >> (8 * b)) & 0xFF) for b in range(4) if (m >> (8 * b)) & 0xFF)))
    return fold(ev)


def main():
    c, m = core(sys.argv[1]), mame(sys.argv[2])
    n = min(len(c), len(m))
    k = next((i for i in range(n) if c[i][1:] != m[i][1:]), n)
    print(f'core {len(c):,} folded byte writes (last at {c[-1][0]:.3f} s), MAME {len(m):,}; first {k:,} equal'
          + (f' (MAME time of the last equal write {m[k - 1][0]:.3f} s)' if k else ''))
    for i in range(max(0, k - 3), min(n, k + 4)):
        print(f'  {i:>8,} core {c[i][0]:.6f} {c[i][1]:08X} {c[i][2]:02X} | MAME {m[i][0]:.6f} {m[i][1]:08X} {m[i][2]:02X}{"  <--" if i == k else ""}')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main()
