#!/usr/bin/env python3
"""M1: Python transcription of the MAME 0.288 psxgpu.cpp rasteriser
(src/devices/video/psx.cpp, docs/mame_sources.md) for the commands the ps1-tests streams use,
to see what MAME draws for the same input without running MAME:
  02 fill (FrameBufferRectangleDraw), A0 CPU to VRAM (pixel data copied),
  E1 (decode_tpage, type 2 bit layout), E3/E4/E5 (type 2: y at bit 10),
  20-23/28-2B flat polygons (FlatPolygon), 2C-2F flat textured (FlatTexturedPolygon,
  15-bit textures, no texture window), 30-33/38-3B Gouraud (GouraudPolygon),
  60-63 flat rectangles (FlatRectangle).
The polygon walk, 16.16 fixed point, int32 truncating divisions, the shade
and blend lookup tables and the draw area checks follow the C++ line by line.
Mask bit handling (E6) is not modelled (no test sets it). MAME has no dither.
Checked 2026-10-05 against MAME 0.288 itself (tools/mame/ps1test_replay.lua):
identical VRAM (lines 0-511, colour bits) for quad, triangle, transparency
and uv-interpolation.

  tools/mame_gpu_model.py <test> <out_vram.bin>     (test as in ps1test_stream.py)
"""
import sys

import numpy as np

import ps1test_stream as ps

MAX_LEVEL, MAX_SHADE, MID_SHADE = 32, 0x100, 0x80
MID_LEVEL = (MAX_LEVEL // 2) << 8


def i32(v):
    v &= 0xffffffff
    return v - (1 << 32) if v & 0x80000000 else v


def cdiv(a, b):
    """C int32 division (truncates toward zero)."""
    a, b = i32(a), i32(b)
    q = abs(a) // abs(b)
    return i32(q if (a >= 0) == (b >= 0) else -q)


def sext11(v):
    v &= 0x7ff
    return v - 0x800 if v & 0x400 else v


def hi_s(d):          # PAIR .sw.h
    return i32(d) >> 16


def hi_u(d):          # PAIR .w.h
    return (d >> 16) & 0xffff


def _shade(idx, shift=0):
    assert 0 <= idx < MAX_LEVEL * MAX_SHADE, idx
    level, shade = idx >> 8, idx & 0xff
    v = (level * shade) // MID_SHADE
    v >>= shift
    return min(v, MAX_LEVEL - 1)


NEXT4, PREV4 = [1, 3, 0, 2], [2, 0, 3, 1]
NEXT4B, PREV4B = [0, 3, 1, 2], [0, 2, 3, 1]
NEXT3, PREV3 = [1, 2, 0], [2, 0, 1]


class MameGPU:
    def __init__(self):
        self.vram = np.zeros((1024, 1024), np.uint16)   # type 2 (2 MB) is 1024 lines; tests use 512
        self.x1 = self.y1 = 0
        self.x2 = self.y2 = 1023
        self.ox = self.oy = 0
        self.tx = self.ty = 0
        self.abr = 0
        self.tp = 0

    # ------------------------------------------------------------- state
    def decode_tpage(self, t):              # type 2
        self.tx = (t & 0x0f) << 6
        self.ty = ((t & 0x10) << 4) | ((t & 0x800) >> 2)
        self.abr = (t & 0x60) >> 5
        self.tp = (t & 0x180) >> 7

    # ------------------------------------------------------------- pixel output
    def blend_tables(self):
        shift = {0: 1, 1: 0, 2: 0, 3: 2}[self.abr]
        half_b = self.abr == 0
        sub = self.abr == 2
        return shift, half_b, sub

    def solid_pixel(self, y, x, r, g, b, trans):
        """SOLIDFILL body for one pixel: r/g/b are the .w.h colour values."""
        if not trans:
            p = _shade(MID_LEVEL | r) | _shade(MID_LEVEL | g) << 5 | _shade(MID_LEVEL | b) << 10
        else:
            shift, half_b, sub = self.blend_tables()
            bg = int(self.vram[y, x])
            out = 0
            for sh, c in ((0, r), (5, g), (10, b)):
                f = _shade(MID_LEVEL | c, shift)
                bb = (bg >> sh) & 31
                if half_b:
                    bb //= 2
                v = max(bb - f, 0) if sub else min(bb + f, 31)
                out |= v << sh
            p = out
        self.vram[y, x] = p

    def tex_pixel(self, y, x, texel, r, g, b, trans):
        """SHADEDPIXEL / TRANSPARENTPIXEL for 15-bit textures."""
        if texel == 0:
            return
        lv = [(texel & 31) * 256, ((texel >> 5) & 31) * 256, ((texel >> 10) & 31) * 256]
        if trans and texel & 0x8000:
            shift, half_b, sub = self.blend_tables()
            bg = int(self.vram[y, x])
            out = 0x8000
            for i, (sh, c) in enumerate(((0, r), (5, g), (10, b))):
                f = _shade(lv[i] | c, shift)
                bb = (bg >> sh) & 31
                if half_b:
                    bb //= 2
                v = max(bb - f, 0) if sub else min(bb + f, 31)
                out |= v << sh
            self.vram[y, x] = out
        else:
            self.vram[y, x] = (_shade(lv[0] | r) | _shade(lv[1] | g) << 5 | _shade(lv[2] | b) << 10
                               | (texel & 0x8000))

    # ------------------------------------------------------------- primitives
    def fill(self, w0, w1, w2):
        r, g, b = w0 & 0xff, (w0 >> 8) & 0xff, (w0 >> 16) & 0xff
        p = _shade(MID_LEVEL | r) | _shade(MID_LEVEL | g) << 5 | _shade(MID_LEVEL | b) << 10
        y = (w1 >> 16) & 0xffff
        y = y - 0x10000 if y & 0x8000 else y         # COORD_Y = sw.h (int16)
        n_h = (w2 >> 16) & 0xffff
        while n_h > 0:
            x = w1 & 0xffff
            x = x - 0x10000 if x & 0x8000 else x
            n = w2 & 0xffff
            while n > 0:
                self.vram[y & 1023, x & 1023] = p
                x = (x + 1) & 0xffff
                x = x - 0x10000 if x & 0x8000 else x
                n -= 1
            y += 1
            n_h -= 1

    def flat_rect(self, w0, w1, w2):
        cmd = w0 >> 24
        r, g, b = w0 & 0xff, (w0 >> 8) & 0xff, (w0 >> 16) & 0xff
        x, y = sext11(w1), sext11(w1 >> 16)
        n_h = (w2 >> 16) & 0xffff
        while n_h > 0:
            n = w2 & 0xffff
            dy = y + self.oy
            if n > 0 and self.y1 <= dy <= self.y2:
                dx = x + self.ox
                if self.x1 - dx > 0:
                    n -= self.x1 - dx
                    dx = self.x1
                if n > self.x2 - dx + 1:
                    n = self.x2 - dx + 1
                while n > 0:
                    self.solid_pixel(dy & 1023, dx & 1023, r, g, b, cmd & 2)
                    dx += 1
                    n -= 1
            y += 1
            n_h -= 1

    def polygon(self, cmd, verts, kind):
        """verts: list of dict(x, y, r, g, b, u, v). kind: 'flat', 'gouraud', 'tex'."""
        n_points = len(verts)
        X = [v['x'] for v in verts]
        Y = [v['y'] for v in verts]

        def cull(a, b):
            return (not -1023 <= Y[a] - Y[b] <= 1023) or (not -1023 <= X[a] - X[b] <= 1023)

        def cull_tri(s):
            return cull(s, s + 1) or cull(s + 1, s + 2) or cull(s + 2, s)
        left = 0
        if n_points == 4:
            if cull_tri(0):
                if cull_tri(1):
                    return
                rl, ll = NEXT4B, PREV4B
                left += 1
            elif cull_tri(1):
                rl, ll = NEXT3, PREV3
                n_points -= 1
            else:
                rl, ll = NEXT4, PREV4
        elif cull_tri(0):
            return
        else:
            rl, ll = NEXT3, PREV3
        for p in range(left + 1, n_points):
            if Y[p] < Y[left] or (Y[p] == Y[left] and X[p] < X[left]):
                left = p
        right = left
        # attribute channels interpolated: x always, then colour or uv
        chans = {'flat': [], 'gouraud': ['r', 'g', 'b'], 'tex': ['u', 'v']}[kind]
        c1 = {'x': 0, **{c: 0 for c in chans}}
        c2 = dict(c1)
        d1 = dict(c1)
        d2 = dict(c1)
        n_y = Y[right]
        if kind == 'flat':
            fr, fg, fb = verts[0]['r'], verts[0]['g'], verts[0]['b']
        if kind == 'tex':
            mod = (0x80, 0x80, 0x80) if cmd & 1 else (verts[0]['r'], verts[0]['g'], verts[0]['b'])
        while True:
            if n_y == Y[left]:
                while n_y == Y[ll[left]]:
                    left = ll[left]
                    if left == right:
                        break
                c1['x'] = i32(X[left] << 16)
                for c in chans:
                    c1[c] = verts[left][c] << 16
                left = ll[left]
                dist = Y[left] - n_y
                if dist < 1:
                    break
                d1['x'] = cdiv(i32(X[left] << 16) - c1['x'], dist)
                for c in chans:
                    d1[c] = cdiv((verts[left][c] << 16) - c1[c], dist)
            if n_y == Y[right]:
                while n_y == Y[rl[right]]:
                    right = rl[right]
                    if right == left:
                        break
                c2['x'] = i32(X[right] << 16)
                for c in chans:
                    c2[c] = verts[right][c] << 16
                right = rl[right]
                dist = Y[right] - n_y
                if dist < 1:
                    break
                d2['x'] = cdiv(i32(X[right] << 16) - c2['x'], dist)
                for c in chans:
                    d2[c] = cdiv((verts[right][c] << 16) - c2[c], dist)
            drawy = n_y + self.oy
            xa, xb = hi_s(c1['x']), hi_s(c2['x'])
            if xa != xb and self.y1 <= drawy <= self.y2:
                if xa < xb:
                    n_x, dist, lo, hi = xa, xb - xa, c1, c2
                else:
                    n_x, dist, lo, hi = xb, xa - xb, c2, c1
                cur = {c: lo[c] for c in chans}
                dc = {c: cdiv(hi[c] - lo[c], dist) for c in chans}
                drawx = n_x + self.ox
                if self.x1 - drawx > 0:
                    for c in chans:
                        cur[c] = i32(cur[c] + dc[c] * (self.x1 - drawx))
                    dist -= self.x1 - drawx
                    drawx = self.x1
                if dist > self.x2 - drawx + 1:
                    dist = self.x2 - drawx + 1
                yy = drawy & 1023
                while dist > 0:
                    if kind == 'flat':
                        self.solid_pixel(yy, drawx, fr, fg, fb, cmd & 2)
                    elif kind == 'gouraud':
                        self.solid_pixel(yy, drawx, hi_u(cur['r']), hi_u(cur['g']), hi_u(cur['b']), cmd & 2)
                    else:
                        assert self.tp == 2, 'only 15-bit textures modelled'
                        tu, tv = hi_u(cur['u']), hi_u(cur['v'])
                        texel = int(self.vram[(self.ty + tv) & 1023, (self.tx + tu) & 1023])
                        self.tex_pixel(yy, drawx, texel, *mod, cmd & 2)
                    drawx += 1
                    for c in chans:
                        cur[c] = i32(cur[c] + dc[c])
                    dist -= 1
            c1['x'] = i32(c1['x'] + d1['x'])
            c2['x'] = i32(c2['x'] + d2['x'])
            for c in chans:
                c1[c] = i32(c1[c] + d1[c])
                c2[c] = i32(c2[c] + d2[c])
            n_y += 1

    # ------------------------------------------------------------- command parser
    def run(self, words):
        i = 0
        n = len(words)
        while i < n:
            w = words[i]
            op = w >> 24
            if op in (0x00, 0x01):
                i += 1
            elif op == 0x02:
                self.fill(*words[i:i + 3]); i += 3
            elif op == 0xa0:
                xy, wh = words[i + 1], words[i + 2]
                x0, y0 = xy & 0x3ff, (xy >> 16) & 0x3ff
                ww, hh = (wh & 0xffff) or 0x400, (wh >> 16) or 0x400
                cnt = (ww * hh + 1) // 2
                data = words[i + 3:i + 3 + cnt]
                pix = []
                for d in data:
                    pix += [d & 0xffff, d >> 16]
                k = 0
                for yy in range(hh):
                    for xx in range(ww):
                        self.vram[(y0 + yy) & 1023, (x0 + xx) & 1023] = pix[k]; k += 1
                i += 3 + cnt
            elif op == 0xe1:
                self.decode_tpage(w & 0xffffff); i += 1
            elif op == 0xe2:
                assert w & 0xfffff == 0, 'texture window not modelled'
                i += 1
            elif op == 0xe3:
                self.x1, self.y1 = w & 1023, (w >> 10) & 1023; i += 1
            elif op == 0xe4:
                self.x2, self.y2 = w & 1023, (w >> 10) & 1023; i += 1
            elif op == 0xe5:
                self.ox, self.oy = sext11(w), sext11(w >> 11); i += 1
            elif op == 0xe6:
                assert w & 3 == 0, 'mask bit not modelled'
                i += 1
            elif 0x60 <= op <= 0x63:
                self.flat_rect(*words[i:i + 3]); i += 3
            elif 0x20 <= op <= 0x2b and not op & 4:
                nv = 4 if op & 8 else 3
                c = words[i]
                vs = [dict(x=sext11(words[i + 1 + k]), y=sext11(words[i + 1 + k] >> 16),
                           r=c & 0xff, g=(c >> 8) & 0xff, b=(c >> 16) & 0xff) for k in range(nv)]
                self.polygon(op, vs, 'flat'); i += 1 + nv
            elif op in (0x2c, 0x2d, 0x2e, 0x2f):
                c = words[i]
                vs = []
                for k in range(4):
                    p, t = words[i + 1 + 2 * k], words[i + 2 + 2 * k]
                    vs.append(dict(x=sext11(p), y=sext11(p >> 16), u=t & 0xff, v=(t >> 8) & 0xff,
                                   r=c & 0xff, g=(c >> 8) & 0xff, b=(c >> 16) & 0xff))
                self.decode_tpage(words[i + 4] >> 16)
                self.polygon(op, vs, 'tex'); i += 9
            elif 0x30 <= op <= 0x3b and not op & 4:
                nv = 4 if op & 8 else 3
                vs = []
                for k in range(nv):
                    c, p = words[i + 2 * k], words[i + 2 * k + 1]
                    vs.append(dict(x=sext11(p), y=sext11(p >> 16),
                                   r=c & 0xff, g=(c >> 8) & 0xff, b=(c >> 16) & 0xff))
                self.polygon(op, vs, 'gouraud'); i += 2 * nv
            else:
                raise NotImplementedError('GP0 %08x' % w)


def main():
    name, out = sys.argv[1], sys.argv[2]
    s = ps.Stream()
    ps.TESTS[name](s)
    g = MameGPU()
    words = [w for k, w in s.recs if k in (0, 2)]
    # GP1(00) reset is the first record of every stream; nothing else of GP1 reaches drawing
    g.run(words)
    g.vram[:512].astype('<u2').tofile(out)
    print(f'{name}: MAME 0.288 model VRAM (lines 0-511) written to {out}')


if __name__ == '__main__':
    main()
