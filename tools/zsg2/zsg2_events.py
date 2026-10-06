#!/usr/bin/env python3
"""Turn a zsg2_trace.lua log into the replay stream for sim/zsg2/tb.cpp.

Sample positions (checked on the raycris canary, docs/zsg2_rtl.md 4.1):
an access at MAME time t comes after the ZSG-2 sample k = floor(t * 32552)
and before sample k + 1, and the TMS57002 inputs logged at k are the ZSG-2
outputs of sample k. A read tap sees the post-update m_sample_count, so
k - cnt is the offset of the current Zoom reset segment; a write tap may see
cnt one lower (the update runs in the handler, after the tap).

Output lines, in replay order:
  X                      Zoom reset
  W <addr> <data>        CPU write, addr = word offset 0x000-0x3ff (hex)
  R <addr> <data>        CPU read, data = what MAME returned (hex)
  T <k>                  render sample k
  O <k> <o0> <o1> <o2> <o3>  MAME's four ZSG-2 outputs of sample k (signed)

  zsg2_events.py <zsg2.log> <out.ev>
"""
import sys

RATE = 32552


def sext24(v):
    return v - (1 << 24) if v & 0x800000 else v


def main():
    log, outp = sys.argv[1:3]
    acc = []          # (pos, cnt, rw, addr, data)
    outs = {}         # k -> (o0..o3)
    offs = []         # segment offsets in order of appearance
    bad = 0
    for line in open(log):
        p = line.split()
        if p[0] == 'A':
            t = float(p[1])
            pos = int(t * RATE)
            off = int(p[3], 16)
            if int(p[5], 16) != 0xffff:
                bad += 1
                continue
            acc.append((pos, int(p[7]), p[2], (off - 0x800000) >> 1, int(p[4], 16)))
            if p[2] == 'R':
                o = pos - int(p[7])
                if o not in offs:
                    offs.append(o)
        elif p[0] == 'S':
            k, c = int(p[1]), int(p[2])
            si = [sext24(int(x)) for x in p[3:7]]
            vals = [si[0] / 128, si[1] / 128, si[2] / 256, si[3] / 256]
            if any(v != int(v) for v in vals):
                print('non-integer output at', k, si)
            outs[k] = tuple(int(v) for v in vals)
            o = k - c
            if o not in offs:
                offs.append(o)
    offs.sort()
    # segment of each access: k - cnt is off (reads, most writes) or off + 1
    seg_acc = []
    for a in acc:
        d = a[0] - a[1]
        s = None
        for i, o in enumerate(offs):
            if d == o or (a[2] == 'W' and d == o + 1):
                s = i
        if s is None:
            raise SystemExit('access with no segment: %r (offsets %r)' % (a, offs))
        seg_acc.append((a[0], s, a))
    starts = [o + 1 for o in offs]          # first sample of each segment
    k0 = starts[0]
    kend = max([a[0] for a in acc] + list(outs)) + 1
    # group accesses by position, keep file order (MN10200 execution order)
    bypos = {}
    for pos, s, a in seg_acc:
        bypos.setdefault(pos, []).append((s, a))
    n = {'W': 0, 'R': 0, 'T': 0, 'O': 0, 'X': 0}
    with open(outp, 'w') as f:
        f.write('X\n'); n['X'] += 1
        seg = 0
        for k in range(k0, kend + 1):
            # accesses after sample k - 1, with a reset before the first
            # access of the next segment
            for s, a in bypos.get(k - 1, []):
                while seg < s:
                    seg += 1
                    f.write('X\n'); n['X'] += 1
                f.write('%s %03x %04x\n' % (a[2], a[3], a[4])); n[a[2]] += 1
            while seg + 1 < len(starts) and starts[seg + 1] == k:
                seg += 1
                f.write('X\n'); n['X'] += 1
            f.write('T %d\n' % k); n['T'] += 1
            if k in outs:
                f.write('O %d %d %d %d %d\n' % ((k,) + outs[k])); n['O'] += 1
    print('segments (first sample):', starts, 'samples', k0, '-', kend, n, 'bad masks', bad)


if __name__ == '__main__':
    main()
