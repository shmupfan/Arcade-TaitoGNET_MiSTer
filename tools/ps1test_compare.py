#!/usr/bin/env python3
"""M1: compare a VRAM dump of a ps1-tests replay with the test's vram.png
(reference/ps1-tests/gpu/<test>/vram.png, a gitignored local clone of
https://github.com/JaCzekanski/ps1-tests).

Dumps: the core's (sim/m1/tb_gpu_replay, VRAM_Y_BITS = 9: 1 MB) or MAME's
(tools/mame/ps1test_replay.lua, 2 MB) or tools/mame_gpu_model.py output;
16-bit little-endian, 1024 wide; lines 0-511 are compared. The PNGs hold
8-bit channels equal to the 5-bit value << 3 (every value in the six images
is a multiple of 8, asserted on load), so the dump is compared as 5-bit
channels; the mask bit is not in the PNGs and is ignored.

  tools/ps1test_compare.py <vram.bin> <test> [--detail] [--out prefix]
Prints differing pixels for the whole of lines 0-511 and per region of the
test (REGIONS), split by the largest 5-bit channel difference (1, 2, >2).
--detail adds the per-test breakdowns used in docs/m1_gpu_zn2.md 2d.
--out writes <prefix>_diff.png (red = differing) and <prefix>_side.png.
"""
import collections
import sys

import numpy as np
from PIL import Image

PNG = 'reference/ps1-tests/gpu/%s/vram.png'

# (name, x0, y0, x1, y1) inclusive
REGIONS = {
    'quad': [('five seam quads + 16 small quads', 0, 0, 319, 239),
             ('16 small quads (y 192-223)', 64, 192, 191, 223)],
    'triangle': [('triangle 1, dither off', 0, 0, 319, 239),
                 ('triangle 2, dither off', 512, 0, 1023, 511),
                 ('triangle 3, dither on', 0, 240, 319, 511)],
    'uv-interpolation': [('FT4 UV rows (x 0-255, y 0-255)', 0, 0, 255, 255),
                         ('G4 rows, dither off', 0, 256, 255, 511),
                         ('G4 rows, dither on', 256, 256, 511, 511)],
    'transparency': [('strips and tiles', 0, 0, 319, 239)],
    'lines': [('h/v lines, dither off', 16, 16, 220, 98),
              ('flat lines, dither off', 16, 100, 79, 163),
              ('Gouraud lines, dither off', 16, 166, 79, 229),
              ('flat lines, dither on', 84, 100, 147, 163),
              ('Gouraud lines, dither on', 84, 166, 147, 229),
              ('polylines', 150, 100, 243, 172),
              ('circle', 168, 168, 232, 232)],
    'rectangles': [('mode 0 band', 0, 0, 319, 39), ('mode 1 band', 0, 64, 319, 103),
                   ('mode 2 band', 0, 128, 319, 167), ('mode 3 band', 0, 192, 319, 231)],
}


def lines_excluded():
    """lines: the last segment of the two Gouraud polylines ends at a colour
    the test never sets (LINE_G4 r3/g3/b3 left as stack contents), so the
    diagonals (150..182, 140..172) and (210..242, 140..172) are excluded."""
    m = np.zeros((512, 1024), bool)
    for k in range(33):
        m[140 + k, 150 + k] = m[140 + k, 210 + k] = True
    return m


def core_rgb(path):
    a = np.fromfile(path, dtype='<u2')[:1024 * 512].reshape(512, 1024)
    return np.dstack([a & 31, (a >> 5) & 31, (a >> 10) & 31]).astype(int)


def ref_rgb(test):
    p = np.array(Image.open(PNG % test).convert('RGB')).astype(int)
    assert (p % 8 == 0).all(), 'reference not a 5-bit << 3 image'
    return p >> 3


def row(name, d):
    return '%-36s %7d of %7d   1 LSB %6d   2 LSB %5d   >2 %6d' % (
        name, int((d > 0).sum()), d.size, int((d == 1).sum()), int((d == 2).sum()), int((d > 2).sum()))


def detail(test, c, r, d):
    white = np.array([31, 31, 31])
    if test == 'triangle':
        for name, x0, y0, x1, y1 in REGIONS[test]:
            cc, rr = c[y0:y1 + 1, x0:x1 + 1], r[y0:y1 + 1, x0:x1 + 1]
            cw, rw = (cc == white).all(2), (rr == white).all(2)
            dd = cc - rr
            one = ~cw & ~rw & (np.abs(dd).max(2) == 1)
            print(f'  {name}: drawn only in reference {int((cw & ~rw).sum())}, only in dump '
                  f'{int((~cw & rw).sum())}; 1-LSB pixels {int(one.sum())}: channels lower in dump '
                  f'{int((dd[one] < 0).sum())}, higher {int((dd[one] > 0).sum())}')
    elif test == 'uv-interpolation':
        G, R = np.array([0, 31, 0]), np.array([31, 0, 0])
        n_rows = 0
        for w in (2, 3, 4, 5, 8, 9, 101, 255):
            rr, cc = r[w, :w], c[w, :w]
            print(f'  width {w}: reference red {int((rr == R).all(1).sum())} green {int((rr == G).all(1).sum())}'
                  f' | dump red {int((cc == R).all(1).sum())} green {int((cc == G).all(1).sum())}')
        for w in range(256):
            n_rows += (c[w, :w] == G).all(1).any()
        print(f'  rows with any green texel in dump: {n_rows} of 256')
    elif test == 'quad':
        cnt = collections.Counter()
        ys, xs = np.nonzero(d[:240, :320] > 2)
        for x, y in zip(xs, ys):
            cnt[(tuple(int(v) for v in r[y, x]), tuple(int(v) for v in c[y, x]))] += 1
        for (a, b), n in cnt.most_common():
            print(f'  >2 LSB: reference {a} dump {b}: {n}')
        ys, xs = np.nonzero(d[:240, :320] == 1)
        odd = sum(1 for x, y in zip(xs, ys) if (c[y, x] - r[y, x]).sum() < 0)
        print(f'  1-LSB pixels with the dump lower: {odd} of {len(xs)}')
    elif test == 'rectangles':
        cnt = collections.Counter()
        ys, xs = np.nonzero(d)
        for x, y in zip(xs, ys):
            band = y // 64
            t = 0x60 + ((y % 64) // 20) * 16 + x // 20
            lower = (c[y, x] - r[y, x]).sum() < 0
            cnt[(band, '%02X' % t, 'dump lower' if lower else 'dump higher')] += 1
        for k, n in sorted(cnt.items()):
            print(f'  mode band {k[0]} command {k[1]}h {k[2]}: {n}')


def main():
    args = sys.argv[1:]
    out = None
    if '--out' in args:
        i = args.index('--out')
        out = args[i + 1]
        del args[i:i + 2]
    det = '--detail' in args
    args = [a for a in args if a != '--detail']
    path, test = args[0], args[1]
    c, r = core_rgb(path), ref_rgb(test)
    d = np.abs(c - r).max(axis=2)
    print(row('whole VRAM lines 0-511', d))
    if test == 'lines':
        ex = lines_excluded()
        print(row('  of which excluded segments', d[ex]))
        d[ex] = 0
        print(row('whole, excluded segments removed', d))
    for name, x0, y0, x1, y1 in REGIONS.get(test, []):
        print(row('  ' + name, d[y0:y1 + 1, x0:x1 + 1]))
    if det:
        detail(test, c, r, d)
    if out:
        img = np.zeros((512, 1024, 3), np.uint8)
        img[d > 0] = (255, 0, 0)
        Image.fromarray(img).save(out + '_diff.png')
        Image.fromarray(np.concatenate([c << 3, r << 3], axis=1).astype(np.uint8)).save(out + '_side.png')


if __name__ == '__main__':
    main()
