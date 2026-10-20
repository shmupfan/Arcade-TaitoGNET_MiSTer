#!/usr/bin/env python3
"""Directed GPU test for textured rectangle X/Y flip (issue #6, E1 bits 12
and 13, gpu_rect.vhd RECT_FLIP) for sim/m1/tb_gpu_replay.vhd.

  tools/rect_flip_test.py stream <out.txt>     write the replay stream
  tools/rect_flip_test.py check <vram.bin> [--noflip]
                                               compare a core VRAM dump with
                                               the model (MAME 0.288 type 2
                                               FlatTexturedRectangle /
                                               Sprite8x8 / Sprite16x16 with
                                               SPRITESETUP); --noflip models
                                               the flip bits as ignored
                                               (RECT_FLIP = 0 control)

Stream (all words in frame 0, GP0 through the DMA port): reset, draw area
(100,100)-(400,300), offset 0, a 4-bit texture of 256 x 16 texels at tpage
(512,0) and a 16-entry CLUT at (768,300) loaded with A0h, then raw opaque
rectangles (65h variable size, 7Dh 16x16, 75h 8x8) with flip off, X, Y and
both, two clipped at the left or top edge of the draw area, one with U
wrapping through 0 and one with a texture window. A textured quad drawn with
flip off and with flip on (same shape, 64 pixels apart) checks that polygons
ignore the flip bits. Run with VRAM_Y_BITS = 10, DUMPS = 2, MAXFRAME = 3,
DITHER_OFF = '1' (see docs/m1_gpu_zn2.md section 6).
"""

import sys

import numpy as np

TPX, TPY = 512, 0          # texture page (4-bit: 64 halfwords = 256 texels wide)
CLX, CLY = 768, 300        # CLUT
AREA = (100, 100, 400, 300)  # draw area x1, y1, x2, y2


def texel(u, v):
    return (u * 7 + v * 3 + (u >> 4)) & 15


def clut(i):
    return ((i + 1) & 31) | ((15 - i) << 5) | ((i * 2) << 10)


def xy(x, y):
    return ((y & 0xffff) << 16) | (x & 0xffff)


def e1(flipx, flipy):
    # tpage x 512 (index 8), 4-bit (tp 0), dither off, draw to display on
    return 0xe1000000 | (TPX >> 6) | (1 << 10) | (flipx << 12) | (flipy << 13)


# (cmd, x, y, u, v, w, h, flipx, flipy, window) ; w/h ignored for 7Dh/75h
RECTS = [
    (0x65, 120, 110, 8, 0, 16, 16, 0, 0, 0),     # reference
    (0x65, 140, 110, 23, 0, 16, 16, 1, 0, 0),    # X flip, mirror of the reference
    (0x65, 160, 110, 8, 15, 16, 16, 0, 1, 0),    # Y flip
    (0x65, 180, 110, 23, 15, 16, 16, 1, 1, 0),   # X and Y flip
    (0x65, 92, 130, 23, 0, 16, 16, 1, 0, 0),     # X flip, 8 pixels clipped at the left
    (0x65, 92, 150, 8, 0, 16, 16, 0, 0, 0),      # same without flip
    (0x65, 120, 92, 40, 15, 16, 16, 0, 1, 0),    # Y flip, 8 lines clipped at the top
    (0x65, 140, 92, 55, 15, 16, 16, 1, 1, 0),    # both flips, clipped at the top
    (0x65, 200, 130, 3, 2, 16, 8, 1, 0, 0),      # X flip, U wraps 3..0, 255..244
    (0x65, 220, 130, 35, 3, 40, 12, 1, 0, 0),    # odd start U, wider than 16
    (0x7d, 270, 130, 99, 1, 16, 16, 1, 0, 0),    # 16x16 sprite, X flip
    (0x75, 290, 130, 77, 9, 8, 8, 0, 1, 0),      # 8x8 sprite, Y flip
    (0x65, 300, 150, 61, 7, 24, 8, 1, 0, 1),     # X flip with texture window
    (0x65, 330, 150, 61, 7, 24, 8, 0, 0, 1),     # same, no flip
    (0x65, 92, 92, 120, 14, 20, 20, 1, 1, 0),    # both flips, clipped left and top
]
# texture window: mask x 2 (U bit 4), offset x 2 (bits inside the mask, so
# the PS1 formula and MAME's base + mask agree), y mask 0
WINDOW = (0x2, 0x0, 0x2, 0x0)    # mask x, mask y, offset x, offset y (8-texel units)


def e2(win):
    mx, my, ox, oy = win
    return 0xe2000000 | mx | (my << 5) | (ox << 10) | (oy << 15)


def stream():
    recs = []

    def gp0(*ws):
        recs.extend((2, w & 0xffffffff) for w in ws)

    def gp1(w):
        recs.append((1, w & 0xffffffff))

    gp1(0x00000000)
    gp1(0x01000000)
    gp1(0x04000002)
    gp1(0x05000000)
    gp1(0x06000000 | (0xc60 << 12) | 0x260)
    gp1(0x07000000 | (0x100 << 10) | 0x010)
    gp1(0x08000001)
    gp1(0x03000000)
    x1, y1, x2, y2 = AREA
    gp0(0xe3000000 | x1 | (y1 << 10), 0xe4000000 | x2 | (y2 << 10), 0xe5000000, 0xe6000000)
    gp0(0x02000000, xy(0, 0), xy(512, 400))           # clear lines 0..399, x 0..511
    # texture: 64 x 16 halfwords, 4 texels each (low nibble = lowest U)
    gp0(0x01000000, 0xa0000000, xy(TPX, TPY), xy(64, 16))
    hw = []
    for v in range(16):
        for hx in range(64):
            h = 0
            for k in range(4):
                h |= texel(hx * 4 + k, v) << (4 * k)
            hw.append(h)
    gp0(*[hw[i] | (hw[i + 1] << 16) for i in range(0, len(hw), 2)])
    gp0(0xa0000000, xy(CLX, CLY), xy(16, 1))
    gp0(*[clut(i) | (clut(i + 1) << 16) for i in range(0, 16, 2)])
    cl = (CLX >> 4) | (CLY << 6)
    for cmd, x, y, u, v, w, h, fx, fy, win in RECTS:
        gp0(e2(WINDOW) if win else 0xe2000000)
        gp0(e1(fx, fy))
        gp0((cmd << 24) | 0x808080, xy(x, y), (cl << 16) | (v << 8) | u)
        if cmd == 0x65:
            gp0(xy(w, h))
    gp0(0xe2000000)
    # textured quad (2Dh raw, opaque) with the polygon's tpage = same page,
    # flip off then on, 64 pixels apart; the two must be identical
    tp = (TPX >> 6) | (1 << 10)
    for fx, ox in ((0, 0), (1, 64)):
        gp0(e1(fx, fx))
        x0, y0 = 120 + ox, 200
        gp0(0x2d808080,
            xy(x0, y0), (cl << 16) | (0 << 8) | 10,
            xy(x0 + 40, y0), (tp << 16) | (0 << 8) | 50,
            xy(x0, y0 + 30), (12 << 8) | 10,
            xy(x0 + 40, y0 + 30), (12 << 8) | 50)
    gp0(e1(0, 0))
    return recs


def model(noflip=False):
    """MAME 0.288 psxgpu.cpp FlatTexturedRectangle / Sprite8x8 / Sprite16x16
    for these rectangles: offset 0, raw texture, opaque, 4-bit, texel 0 never
    used as a colour (CLUT entries are all non-zero)."""
    x1, y1, x2, y2 = AREA
    img = {}
    for cmd, x, y, u0, v0, w, h, fx, fy, win in RECTS:
        if cmd == 0x7d:
            w = h = 16
        elif cmd == 0x75:
            w = h = 8
        if noflip:
            fx = fy = 0
        du = -1 if fx else 1
        dv = -1 if fy else 1
        if win:
            mx, my, ox, oy = WINDOW
            tww, twh = 255 - (mx << 3), 255 - (my << 3)
            twx, twy = ox << 3, oy << 3
        else:
            tww, twh, twx, twy = 255, 255, 0, 0
        n_v = v0
        for yy in range(y, y + h):
            n_u = u0
            dist = w
            if y1 <= yy <= y2:
                drawx = x
                if x1 - drawx > 0:
                    n_u = (n_u + (x1 - drawx) * du) & 255
                    dist -= x1 - drawx
                    drawx = x1
                dist = min(dist, x2 - drawx + 1)
                for k in range(max(dist, 0)):
                    uu = (n_u & tww) + twx
                    vv = (n_v & twh) + twy
                    # only texture lines 0..15 are loaded; VRAM below is 0
                    img[(drawx + k, yy)] = clut(texel(uu, vv) if vv < 16 else 0)
                    n_u = (n_u + du) & 255
            n_v = (n_v + dv) & 255
    return img


def check(path, noflip):
    vram = np.fromfile(path, dtype='<u2')
    vram = vram.reshape(-1, 1024)
    exp = model(noflip)
    bad = []
    for (x, y), c in sorted(exp.items(), key=lambda t: (t[0][1], t[0][0])):
        got = int(vram[y, x])
        if got != c:
            bad.append((x, y, got, c))
    # every rectangle on its own
    per = []
    for i, r in enumerate(RECTS):
        cmd, x, y, u, v, w, h, fx, fy, win = r
        if cmd == 0x7d:
            w = h = 16
        elif cmd == 0x75:
            w = h = 8
        n = sum(1 for b in bad if x <= b[0] < x + w and y <= b[1] < y + h)
        per.append(n)
    print(f'rect pixels {len(exp)}, differing {len(bad)}')
    for i, r in enumerate(RECTS):
        cmd, x, y, u, v, w, h, fx, fy, win = r
        print(f'  {i:2d} cmd {cmd:02x} at ({x},{y}) uv ({u},{v}) {w}x{h} flip x{fx} y{fy}'
              f' window {win}: {per[i]} differing')
    for b in bad[:8]:
        print('  x %d y %d core %04x model %04x' % b)
    # outside the rectangles, x 100..400, y 100..199: background 0
    mask = np.zeros((100, 301), bool)
    for (x, y) in exp:
        if 100 <= y < 200:
            mask[y - 100, x - 100] = True
    outside = vram[100:200, 100:401][~mask]
    print(f'non-zero pixels outside the rectangles (y 100..199): {int(np.count_nonzero(outside))}')
    a = vram[200:231, 120:161].astype(int)
    b = vram[200:231, 184:225].astype(int)
    print(f'quad flip off vs flip on: {int(np.count_nonzero(a != b))} differing of {a.size},'
          f' drawn pixels {int(np.count_nonzero(a))}')
    return 1 if bad else 0


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == 'stream':
        recs = stream()
        with open(sys.argv[2], 'w') as f:
            for k, w in recs:
                f.write('%02x %08x %08x\n' % (k, 0, w))
        print(f'{len(recs)} words written to {sys.argv[2]}')
        return 0
    if len(sys.argv) >= 3 and sys.argv[1] == 'check':
        return check(sys.argv[2], '--noflip' in sys.argv)
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main())
