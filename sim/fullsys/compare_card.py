#!/usr/bin/env python3
"""Compare the core's accesses to the RF5C296 / ATA window (0x1FB00000 to
0x1FB0FFFF) with MAME's (tools/mame/oracle.lua ata.log), in order: reads and
writes, byte by byte (offset, value). Runs of identical consecutive accesses
are folded on both sides (status polling counts depend on timing; MAME's
log folds them too). Reads of the ATA status register (task file offset 7)
are left out unless --all: how often the BIOS polls depends on CPU and card
timing.

    compare_card.py <core zn.log> <MAME ata.log> [--context N] [--all]

The data port reads are compared run by run (count, first, last and sum of
each run of reads with the same byte enables), because MAME's log folds
them that way.
"""
import sys

LO, HI = 0x1FB00000, 0x1FB0FFFF


ALL = '--all' in sys.argv


def keep(d, a):
    """Writes, and reads other than the status register (offset 7) and the
    data port (offsets 0 and 1: MAME's ata.log folds data reads into runs;
    check_data_runs() compares those)."""
    return d == 'W' or (a & 0xFFFF) not in ((0, 1) if ALL else (0, 1, 7))


def fold(seq):
    out = []
    for e in seq:
        if not out or out[-1][1:] != e[1:]:
            out.append(e)
    return out


def core(path):
    ev = []
    for line in open(path):
        p = line.split()
        if len(p) < 7:
            continue
        a = int(p[2], 16)
        if not LO <= a <= HI:
            continue
        we, be = p[1] == '1', int(p[3], 16)
        d = int(p[4], 16) if we else int(p[6], 16)
        for b in range(4):
            if (be >> b) & 1 and keep('W' if we else 'R', a + b):
                ev.append((float(p[0]) / 1e6, 'W' if we else 'R', a + b, (d >> (8 * b)) & 0xFF))
    return fold(ev)


def mame(path):
    ev = []
    for line in open(path):
        p = line.split()
        if len(p) < 6 or p[2] not in ('R', 'W'):
            continue
        a = int(p[3], 16) & ~3
        if not LO <= a <= HI:
            continue
        d, m = int(p[4], 16), int(p[5], 16)
        for b in range(4):
            if (m >> (8 * b)) & 0xFF and keep(p[2], a + b):
                ev.append((float(p[0]), p[2], a + b, (d >> (8 * b)) & 0xFF))
    return fold(ev)


def data_runs_core(path):
    """Runs of consecutive reads of the ATA data port (0x1FB00000) with the
    same byte enables: (mask, count, first, last, sum), as MAME logs them."""
    runs, cur = [], None
    for line in open(path):
        p = line.split()
        if len(p) < 7:
            continue
        a = int(p[2], 16)
        if not LO <= a <= HI:
            continue
        key = (p[1], a, int(p[3], 16))
        if key[0] == '0' and a == LO:
            v = int(p[6], 16)
            mask = sum(0xFF << (8 * b) for b in range(4) if (key[2] >> b) & 1)
            if cur and cur[0] == key:
                cur[1][1] += 1; cur[1][3] = v; cur[1][4] = (cur[1][4] + v) & 0xFFFFFFFF
                continue
            cur = (key, [mask, 1, v, v, v])
            runs.append(cur[1])
        else:
            cur = None
    return [tuple(r) for r in runs]


def data_runs_mame(path):
    runs = []
    for line in open(path):
        p = line.split()
        if len(p) < 8 or p[2] != 'R' or int(p[3], 16) != LO or p[6] != 'o=0':
            continue
        mask, first = int(p[5], 16), int(p[4], 16)
        if len(p) > 8 and p[8].startswith('x'):
            n = int(p[8][1:])
            last = int(p[10].split('=')[1], 16); sm = int(p[11].split('=')[1], 16)
        else:
            n, last, sm = 1, first, first
        runs.append((mask, n, first, last, sm))
    return runs


def check_data_runs(core_log, mame_log):
    c, m = data_runs_core(core_log), data_runs_mame(mame_log)
    n = min(len(c), len(m))
    k = next((i for i in range(n) if c[i] != m[i]), n)
    words = sum(r[1] for r in c[:k])
    print(f'ATA data port: core {len(c):,} read runs, MAME {len(m):,}; first {k:,} equal '
          f'(count, first, last and sum of every run; {words:,} reads)')
    if k < n:
        print(f'   core #{k}: mask %08X n %d first %08X last %08X sum %08X' % c[k])
        print(f'   MAME #{k}: mask %08X n %d first %08X last %08X sum %08X' % m[k])


def main():
    ctx = int(sys.argv[sys.argv.index('--context') + 1]) if '--context' in sys.argv else 4
    c, m = core(sys.argv[1]), mame(sys.argv[2])
    n = min(len(c), len(m))
    k = next((i for i in range(n) if c[i][1:] != m[i][1:]), n)
    print(f'core {len(c):,} folded byte accesses (last at {c[-1][0] if c else 0:.3f} s), MAME {len(m):,}; first {k:,} equal')
    for i in range(max(0, k - ctx), min(n, k + ctx + 1)):
        print(f'  {i:>7,} core {c[i][0]:.6f} {c[i][1]} {c[i][2]:08X} {c[i][3]:02X} | MAME {m[i][0]:.6f} {m[i][1]} {m[i][2]:08X} {m[i][3]:02X}{"  <--" if i == k else ""}')
    check_data_runs(sys.argv[1], sys.argv[2])


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main()
