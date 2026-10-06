#!/usr/bin/env python3
"""Compare a displayed frame from the M1 replay (video_<f>.ppm, the GPU's
video output as captured by sim/m1/tb_gpu_replay.vhd) with MAME's snapshot
of a frame (snap/f<frame>.png from tools/mame/oracle.lua).

The two images can differ in size: MAME snapshots the visible area it
computes, the testbench writes every pixel between blanking. The tool
searches a small window of x/y offsets for the alignment with the fewest
differing pixels, then reports the differences inside the overlap.

  tools/video_compare.py <core.ppm> <mame.png> [outprefix] [--search N]

Writes <outprefix>_side.png (core | MAME | diff mask) when outprefix is
given.
"""
import sys

from PIL import Image, ImageChops


def load(p):
    return Image.open(p).convert('RGB')


def overlap(a, b, dx, dy):
    """crop a and b to their overlap when b is placed at (dx, dy) in a"""
    x0, y0 = max(0, dx), max(0, dy)
    x1, y1 = min(a.width, dx + b.width), min(a.height, dy + b.height)
    if x1 <= x0 or y1 <= y0:
        return None, None
    return a.crop((x0, y0, x1, y1)), b.crop((x0 - dx, y0 - dy, x1 - dx, y1 - dy))


def count_diff(a, b):
    d = ImageChops.difference(a, b).convert('L').point(lambda v: 255 if v else 0)
    return sum(1 for v in d.getdata() if v), d


def main():
    args = [x for x in sys.argv[1:] if not x.startswith('--')]
    search = 8
    if '--search' in sys.argv:
        search = int(sys.argv[sys.argv.index('--search') + 1])
        args = [x for x in args if x != str(search)]
    core, mame = load(args[0]), load(args[1])
    out = args[2] if len(args) > 2 else None
    print(f'core {core.width}x{core.height}  MAME {mame.width}x{mame.height}')
    if (mame.width, mame.height) == (core.height, core.width) and core.width != core.height:
        # MAME snapshots rotated games as displayed; the GPU output is
        # unrotated. Undo the rotation that matches best.
        cands = [mame.transpose(Image.ROTATE_90), mame.transpose(Image.ROTATE_270)]
        mame = min(cands, key=lambda m: count_diff(core.crop((0, 0, m.width, m.height)), m)[0])
        print('  MAME snapshot is rotated: compared after undoing the rotation')
    if core.width != mame.width:
        # different horizontal resolution; compare after scaling MAME to the
        # core's width (nearest), reported separately as a size difference
        print(f'  width differs: MAME scaled to {core.width} for the comparison')
        mame = mame.resize((core.width, mame.height), Image.NEAREST)
    best = None
    for dy in range(-search, search + 1):
        for dx in range(-search, search + 1):
            a, b = overlap(core, mame, dx, dy)
            if a is None or a.width * a.height < 0.8 * mame.width * mame.height:
                continue
            n, d = count_diff(a, b)
            if best is None or n < best[0]:
                best = (n, dx, dy, a, b, d)
    n, dx, dy, a, b, d = best
    total = a.width * a.height
    print(f'  best offset dx={dx} dy={dy}: {n} of {total} pixels differ ({100.0 * n / total:.3f}%)')
    if n:
        diffs = [abs(p - q) for pa, pb in zip(a.getdata(), b.getdata()) if pa != pb for p, q in zip(pa, pb)]
        big = sum(1 for v in diffs if v > 8)
        print(f'  channel deltas: max {max(diffs)}, over 8: {big} channel values')
    if out:
        side = Image.new('RGB', (a.width * 3, a.height))
        side.paste(a, (0, 0))
        side.paste(b, (a.width, 0))
        side.paste(d.convert('RGB'), (a.width * 2, 0))
        side.save(out + '_side.png')


if __name__ == '__main__':
    main()
