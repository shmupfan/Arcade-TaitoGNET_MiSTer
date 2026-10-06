#!/usr/bin/env python3
"""M1: compare a core VRAM dump (sim/m1 tb_gpu_replay, 1 MB = 1024x512) with a
MAME VRAM dump (oracle ORACLE_VRAM_DUMPS, 2 MB = 1024x1024 on the ZN-2).
Both are 16-bit little-endian PS1 pixels (bit 15 = mask). Compares as many
lines as both dumps hold (512 for a 1 MB core dump, 1024 for 2 MB), reports mismatching pixels, their bounding boxes per 64x64 tile,
and writes side-by-side and diff PNGs.
  tools/vram_compare.py <core.bin> <mame.bin> <out_prefix> [--mask]
  --mask  include bit 15 in the comparison (default: colour bits only)
"""
import sys
import numpy as np

try:
    from PIL import Image
except ImportError:
    Image = None


def load(path, lines):
    a = np.fromfile(path, dtype='<u2')
    return a[:1024 * lines].reshape(lines, 1024)


def to_rgb(v):
    r = (v & 31) << 3
    g = ((v >> 5) & 31) << 3
    b = ((v >> 10) & 31) << 3
    return np.dstack([r, g, b]).astype(np.uint8)


def main():
    core, mame, out = sys.argv[1:4]
    use_mask = '--mask' in sys.argv
    import os
    lines = min(os.path.getsize(core), os.path.getsize(mame)) // 2048
    c = load(core, lines)
    m = load(mame, lines)
    cm, mm = (c, m) if use_mask else (c & 0x7fff, m & 0x7fff)
    diff = cm != mm
    n = int(diff.sum())
    print(f'pixels differing: {n} of {diff.size} ({100 * n / diff.size:.3f}%)')
    if n:
        ys, xs = np.nonzero(diff)
        print(f'bounding box x {xs.min()}-{xs.max()} y {ys.min()}-{ys.max()}')
        tiles = {}
        for y, x in zip(ys // 64, xs // 64):
            tiles[(x, y)] = tiles.get((x, y), 0) + 1
        top = sorted(tiles.items(), key=lambda t: -t[1])[:8]
        print('worst 64x64 tiles (tile x, tile y): count', top)
    if Image:
        side = np.concatenate([to_rgb(c), to_rgb(m)], axis=1)
        Image.fromarray(side).save(out + '_side.png')
        d = np.zeros((lines, 1024, 3), np.uint8)
        d[diff] = (255, 0, 0)
        Image.fromarray(d).save(out + '_diff.png')
    sys.exit(0 if n == 0 else 1)


if __name__ == '__main__':
    main()
