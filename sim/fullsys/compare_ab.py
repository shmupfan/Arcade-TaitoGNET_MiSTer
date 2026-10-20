#!/usr/bin/env python3
"""Compare two full-system runs from their final reset release on
(docs/i12_ddr3_load.md 6.2): the same core booting after two different
download paths must do the same thing.

    compare_ab.py <run dir A> <run dir B> [--until S]

T0 of each run is its last "psx reset 0" in progress.log (the release after
the last download). Compared, in order, with times taken relative to T0:
  card    RF5C296 / ATA window accesses (compare_card.core: status reads left
          out, runs folded) and the ATA data port read runs (count, first,
          last, sum), as compare_card.py does against MAME;
  flash   every access to the flash bank window 0x1F000000-0x1F7FFFFF, reads
          with the data returned (the flash contents the CPU sees) and
          writes (command sequences), identical consecutive accesses folded;
  zn      every ZN-2 bus access (address, direction, enables, write data,
          read data), runs of identical accesses folded;
  gpu     the GP0/GP1 word stream (gpu.log, CPU and DMA words);
  frames  frames.tsv crc555 per frame after T0;
  screens whole pictures (239 or 240 lines) with consecutive equal frames
          folded: the sequence of distinct pictures, independent of how
          many frames each lasts and of mode-change transition frames;
  zn-sel  the zn stream without 0x1FA10300 (CAT702 / SIO0 select, bit-banged
          by the BIOS with timing-dependent retries; see
          docs/i12_ddr3_load.md 7), compared as a prefix: the shorter
          stream must be the start of the longer.
--until S: only events up to S seconds after T0 (default: up to the shorter
run's end).
"""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compare_card  # noqa: E402


def t0_of(run):
    t0, end = None, 0.0
    for line in open(os.path.join(run, 'progress.log')):
        p = line.split()
        if len(p) >= 5 and p[2] == 'psx' and p[3] == 'reset' and p[4] == '0':
            t0 = float(p[0]) / 1e6
        if line.startswith('done:'):
            end = float(p[1]) / 1e3
        elif p and p[0].replace('.', '').isdigit() and len(p) > 1 and p[1] == 'us':
            end = max(end, float(p[0]) / 1e6)
    return t0, end


def zn_events(run, t0, until):
    """(card, data runs, flash, zn) after t0, times relative to t0"""
    fl, zn = [], []
    path = os.path.join(run, 'zn.log')
    for line in open(path):
        p = line.split()
        if len(p) < 7:
            continue
        t = float(p[0]) / 1e6 - t0
        if t < 0:
            continue
        if t > until:
            break
        a = int(p[2], 16)
        key = (p[1], a, p[3], p[4] if p[1] == '1' else '-', p[6])
        if not zn or zn[-1][1:] != key:
            zn.append((t,) + key)
        if 0x1F000000 <= a < 0x1F800000:
            if not fl or fl[-1][1:] != key:
                fl.append((t,) + key)
    return zn, fl


def card_after(run, t0, until):
    tmp = os.path.join(run, '.zn_after_t0.log')
    with open(os.path.join(run, 'zn.log')) as f, open(tmp, 'w') as g:
        for line in f:
            p = line.split(None, 1)
            if not p:
                continue
            t = float(p[0]) / 1e6 - t0
            if t < 0:
                continue
            if t > until:
                break
            g.write('%.3f %s' % (t * 1e6, p[1]))
    c, r = compare_card.core(tmp), compare_card.data_runs_core(tmp)
    os.unlink(tmp)
    return c, r


def gpu_after(run, t0, until):
    out = []
    for line in open(os.path.join(run, 'gpu.log')):
        p = line.split()
        if len(p) < 3:
            continue
        t = float(p[0]) / 1e6 - t0
        if t < 0:
            continue
        if t > until:
            break
        out.append((t, p[1], p[2]))
    return out


def frames_after(run, t0, until):
    out = []
    f = os.path.join(run, 'frames.tsv')
    if not os.path.exists(f):
        return out
    for line in open(f):
        if line.startswith('#'):
            continue
        p = line.split('\t')
        t = float(p[1]) - t0
        if 0 <= t <= until:
            out.append((t, p[2], p[3], p[4]))
    return out


def first_diff(a, b, n=1):
    m = min(len(a), len(b))
    return next((i for i in range(m) if a[i][n:] != b[i][n:]), m)


def report(name, a, b, show):
    k = first_diff(a, b)
    same = k == len(a) == len(b)
    print(f'{name:7s} A {len(a):>10,}  B {len(b):>10,}  first {k:,} equal' + ('  IDENTICAL' if same else ''))
    if not same and k < min(len(a), len(b)):
        print(f'        A[{k}] at {a[k][0]:.6f} s: {show(a[k])}')
        print(f'        B[{k}] at {b[k][0]:.6f} s: {show(b[k])}')
    return same


def main():
    A, B = sys.argv[1], sys.argv[2]
    ta, ea = t0_of(A)
    tb, eb = t0_of(B)
    until = min(ea - ta, eb - tb)
    if '--until' in sys.argv:
        until = min(until, float(sys.argv[sys.argv.index('--until') + 1]))
    print(f'A {A}: final reset release at {ta:.6f} s')
    print(f'B {B}: final reset release at {tb:.6f} s')
    print(f'compared: {until:.3f} s after each release')
    ok = True
    ca, ra = card_after(A, ta, until)
    cb, rb = card_after(B, tb, until)
    gate_ok = [True]
    gate_ok[0] &= report('card', ca, cb, lambda e: f'{e[1]} {e[2]:08X} {e[3]:02X}')
    gate_ok[0] &= report('ata', [(0,) + r for r in ra], [(0,) + r for r in rb], lambda e: 'mask %08X n %d first %08X last %08X sum %08X' % e[1:])
    za, fa = zn_events(A, ta, until)
    zb, fb = zn_events(B, tb, until)
    report('flash', fa, fb, lambda e: f'we {e[1]} {e[2]:08X} be {e[3]} w {e[4]} r {e[5]}')
    kf = first_diff(fa, fb)
    if kf == min(len(fa), len(fb)):
        print('        flash: the shorter stream is the start of the longer (same accesses, same data, same order)')
    else:
        gate_ok[0] = False
    ok &= report('zn', za, zb, lambda e: f'we {e[1]} {e[2]:08X} be {e[3]} w {e[4]} r {e[5]}')
    ok &= report('gpu', gpu_after(A, ta, until), gpu_after(B, tb, until), lambda e: f'{e[1]} {e[2]}')
    fra, frb = frames_after(A, ta, until), frames_after(B, tb, until)
    report('frames', fra, frb, lambda e: f'{e[1]}x{e[2]} {e[3]}')
    def screens(fr):
        o = []
        for e in fr:
            if not o or o[-1][1:] != e[1:]:
                o.append(e)
        return o
    # transitional frames of a video mode change (odd heights) depend on
    # where the change falls in the frame; only whole 239/240-line pictures
    sa = screens([e for e in fra if e[2] in ('239', '240')])
    sb = screens([e for e in frb if e[2] in ('239', '240')])
    n = min(len(sa), len(sb))
    ok_s = first_diff(sa, sb) >= n - 1
    report('screens', sa, sb, lambda e: f'{e[1]}x{e[2]} {e[3]}')
    neq = [i for i in range(n) if sa[i][1:] != sb[i][1:]]
    print(f'        {n - len(neq)} of {n} pictures equal in place' + (f'; differing: ' + ', '.join(
        f'#{i} A {sa[i][3]} B {sb[i][3]}' for i in neq[:6]) if neq else '') +
        (f'; last A {sa[-1][3]} at {sa[-1][0]:.3f} s, B {sb[-1][3]} at {sb[-1][0]:.3f} s' if n else ''))
    def nosel(z):
        o = []
        for e in z:
            if e[2] != 0x1FA10300 and (not o or o[-1][1:] != e[1:]):
                o.append(e)
        return o
    xa, xb = nosel(za), nosel(zb)
    k = first_diff(xa, xb)
    ok_z = k == min(len(xa), len(xb))
    print(f'zn-sel  A {len(xa):>10,}  B {len(xb):>10,}  first {k:,} equal' + ('  (prefix: identical as far as the shorter goes)' if ok_z else ''))
    if not ok_z:
        print(f'        A[{k}] at {xa[k][0]:.6f} s: we {xa[k][1]} {xa[k][2]:08X} be {xa[k][3]} w {xa[k][4]} r {xa[k][5]}')
        print(f'        B[{k}] at {xb[k][0]:.6f} s: we {xb[k][1]} {xb[k][2]:08X} be {xb[k][3]} w {xb[k][4]} r {xb[k][5]}')
    print('ALL STREAMS:', 'identical after reset release' if ok and gate_ok[0] else 'not all identical (see above)')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main()
