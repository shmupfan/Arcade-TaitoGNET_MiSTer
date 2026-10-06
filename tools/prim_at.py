#!/usr/bin/env python3
"""List the GP0 primitives that touch a VRAM pixel in an M1 replay stream.

Reads the testbench input written by tools/gpu_stream.py --text
("KK FFFFFFFF WWWWWWWW": kind, frame, word; kinds 0, 2, 3 are GP0 words),
tracks the draw offset (E5) and draw area (E3/E4), and prints every
polygon, rectangle, line, fill or copy whose screen bounding box, clipped to
the draw area, contains the pixel, newest last. Bounding boxes only: a
listed polygon may not cover the pixel itself.

  tools/prim_at.py <stream.txt> <x> <y> [--from F] [--to F] [--last N]
"""
import sys

from gpu_stream import gp0_len


def s11(v):
    v &= 0x7ff
    return v - 0x800 if v & 0x400 else v


def words(path):
    for line in open(path):
        k, f, w = line.split()
        if k in ('00', '02', '03'):
            yield int(f, 16), int(w, 16)


def main():
    path, px, py = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    opt = lambda n, d: int(sys.argv[sys.argv.index(n) + 1]) if n in sys.argv else d
    f0, f1, last = opt('--from', 0), opt('--to', 1 << 30), opt('--last', 20)
    ox = oy = 0
    area = (0, 0, 1023, 1023)
    hits = []
    it = words(path)
    for fr, w in it:
        op = w >> 24
        n, kind = gp0_len(w)
        if kind == 'polyline':
            pkt = [w]
            for _, x in it:
                pkt.append(x)
                if len(pkt) > 2 and (x & 0xf000f000) == 0x50005000:
                    break
        elif kind == 'cpu_to_vram':
            pkt = [w] + [next(it)[1] for _ in range(2)]
            wh = pkt[2]
            cnt = (((wh & 0xffff) or 0x400) * ((wh >> 16) or 0x200) + 1) // 2
            for _ in range(cnt):
                next(it)
        else:
            pkt = [w] + [next(it)[1] for _ in range(n - 1)]
        if kind == 'env':
            if op == 0xe3:
                area = (w & 0x3ff, (w >> 10) & 0x3ff, area[2], area[3])
            elif op == 0xe4:
                area = (area[0], area[1], w & 0x3ff, (w >> 10) & 0x3ff)
            elif op == 0xe5:
                ox, oy = s11(w), s11(w >> 11)
            continue
        if not (f0 <= fr <= f1):
            continue
        xs, ys = [], []
        if kind == 'polygon':
            verts = 4 if op & 8 else 3
            i = 1
            for v in range(verts):
                if op & 0x10 and v > 0:
                    i += 1
                xs.append(s11(pkt[i]) + ox)
                ys.append(s11(pkt[i] >> 16) + oy)
                i += 1 + (1 if op & 4 else 0)
        elif kind == 'rect':
            x, y = s11(pkt[1]) + ox, s11(pkt[1] >> 16) + oy
            size = (op >> 3) & 3
            if size == 0:
                wh = pkt[-1]
                wd, ht = wh & 0x3ff, (wh >> 16) & 0x1ff
            else:
                wd = ht = {1: 1, 2: 8, 3: 16}[size]
            xs, ys = [x, x + wd - 1], [y, y + ht - 1]
        elif kind in ('line', 'polyline'):
            step = 2 if op & 0x10 else 1
            for i in range(1, len(pkt) - (1 if kind == 'polyline' else 0), step):
                if kind == 'line' and op & 0x10 and i == 1:
                    pass
                xs.append(s11(pkt[i]) + ox)
                ys.append(s11(pkt[i] >> 16) + oy)
        elif kind == 'fill':
            x, y = pkt[1] & 0x3f0, (pkt[1] >> 16) & 0x3ff
            wd, ht = ((pkt[2] & 0x3ff) + 15) & ~15, (pkt[2] >> 16) & 0x1ff
            if x <= px < x + wd and y <= py < y + ht:
                hits.append((fr, kind, op, pkt))
            continue
        elif kind == 'vram_copy':
            dx, dy = pkt[2] & 0x3ff, (pkt[2] >> 16) & 0x3ff
            wd, ht = pkt[3] & 0x3ff, (pkt[3] >> 16) & 0x3ff
            if dx <= px < dx + wd and dy <= py < dy + ht:
                hits.append((fr, kind, op, pkt))
            continue
        else:
            continue
        if not xs:
            continue
        x0, x1 = max(min(xs), area[0]), min(max(xs), area[2])
        y0, y1 = max(min(ys), area[1]), min(max(ys), area[3])
        if x0 <= px <= x1 and y0 <= py <= y1:
            hits.append((fr, kind, op, pkt))
    for fr, kind, op, pkt in hits[-last:]:
        flags = []
        if kind in ('polygon', 'rect', 'line', 'polyline'):
            if kind == 'polygon' and op & 0x10:
                flags.append('gouraud')
            if kind in ('line', 'polyline') and op & 0x10:
                flags.append('gouraud')
            if op & 4 and kind in ('polygon', 'rect'):
                flags.append('textured')
                if op & 1:
                    flags.append('raw')
            if op & 2:
                flags.append('semi')
        print(f'frame {fr:4d} {kind:9s} {op:02x} {" ".join(flags):24s} ' + ' '.join(f'{x:08x}' for x in pkt[:12]))
    print(f'{len(hits)} primitives touch ({px},{py})')


if __name__ == '__main__':
    main()
