#!/usr/bin/env python3
"""M1: GPU command streams of JaCzekanski/ps1-tests gpu/* (MIT, cloned at
https://github.com/JaCzekanski/ps1-tests at f727802, cloned into the gitignored
reference/ps1-tests) for sim/m1/tb_gpu_replay.vhd.

There is no PS1 toolchain or BIOS here, so each test's main.c is re-expressed
in Python and emits the same GP0/GP1 words its PS-EXE sends. The library
calls are taken from the PSn00bSDK sources of the time (Lameguy64/PSn00bSDK
82a441e, 2019-08-17, and afffa97, 2021-01-08; SetDefDrawEnv, PutDrawEnv,
ResetGraph, LoadImage, rand and isin are identical in both):
  ResetGraph(0)     GP1(00) reset, GP1(01) command buffer reset
  PutDispEnv        GP1(05..08) display area and mode (no effect on VRAM)
  SetDefDrawEnv     clip = (x, y, w, h), offset 0, tpage 0x0A, dtd 1, dfe 0
  PutDrawEnv        E3 draw area top-left, E4 bottom-right (x+w-1, y+h-1),
                    E5 offset, E1 = tpage | dtd << 9 | dfe << 10 (no E2)
  LoadImage         GP1(04)=0, GP0 01 (cache clear), A0, xy, wh, GP1(04)=2,
                    pixel data by DMA
  getTPage(tp, abr, x, y) = (x & 0x3ff) >> 6 | (y >> 8) << 4 | abr << 5 | tp << 7
  setDrawTPage(dfe, dtd, tpage) = E1 | tpage | dtd << 9 | dfe << 10

Each vram.png was committed with a particular version of main.c; the stream
follows that version (git history on GitHub, checked 2026-10-05):
  quad          image 603a536 (2019-09-22): draw area 320x240, white clear
                (two fills 1023 x 256), PutDrawEnv called twice
  transparency  image da6b472 (2019-09-24): draw area 320x240, white clear
  lines         image d1a63ee (2019-09-30): draw area 320x240, white clear
  rectangles    image 86a6f3c (2019-10-06): draw area 320x240, white clear
  triangle      image 78ab568 (2021-01-14): common/gpu.cpp, draw area 1024x512
  uv-interpolation image eb10e45 (2021-01-24): common/gpu.cpp, draw area 1024x512
The drawing code of each test is the same in those versions and in f727802.

Output format (tools/gpu_stream.py write_text): "KK FFFFFFFF WWWWWWWW" per
word, KK 01 = GP1, 00 = GP0 CPU write (only LoadImage's header, sent
while the DMA direction is off), 02 = GP0 word through the DMA port (the testbench sends a
DMA word only while the GPU requests data, i.e. while its FIFO is empty, so
no word is lost; the PS-EXE sends the same words in the same order by CPU
writes and DMA). Everything is sent in frame 0.

  tools/ps1test_stream.py <test> <out.txt>
  tools/ps1test_stream.py --list
"""
import struct
import sys

import numpy as np

PS1T = 'reference/ps1-tests'


class Stream:
    def __init__(self):
        self.recs = []

    def gp0(self, *words):
        for w in words:
            self.recs.append((2, w & 0xffffffff))

    def gp0_cpu(self, *words):
        for w in words:
            self.recs.append((0, w & 0xffffffff))

    def gp1(self, w):
        self.recs.append((1, w & 0xffffffff))

    def write(self, path, frame=0):
        with open(path, 'w') as f:
            for k, w in self.recs:
                f.write('%02x %08x %08x\n' % (k, frame, w))
        return len(self.recs)


def xy(x, y):
    return ((y & 0xffff) << 16) | (x & 0xffff)


def rgb(r, g, b):
    return (b & 0xff) << 16 | (g & 0xff) << 8 | (r & 0xff)


def get_tpage(tp, abr, x, y):
    return ((x & 0x3ff) >> 6) | ((y >> 8) << 4) | ((abr & 3) << 5) | ((tp & 3) << 7)


def e1(dfe, dtd, tpage):
    return 0xe1000000 | tpage | (dtd << 9) | (dfe << 10)


def init_video(s, draw_w, draw_h):
    """ResetGraph(0); SetDefDispEnv(0,0,320,240) + PutDispEnv;
    SetDefDrawEnv(0,0,draw_w,draw_h) + PutDrawEnv; SetDispMask(1)."""
    s.gp1(0x00000000)                 # reset
    s.gp1(0x01000000)                 # command buffer reset
    s.gp1(0x04000002)                 # DMA direction CPU -> GP0 (testbench feeds GP0 by DMA)
    # display: 320x240 NTSC from VRAM (0, 0); display values do not reach VRAM
    s.gp1(0x05000000)
    s.gp1(0x06000000 | (0xc60 << 12) | 0x260)
    s.gp1(0x07000000 | (0x100 << 10) | 0x010)
    s.gp1(0x08000001)
    put_draw_env(s, draw_w, draw_h)
    s.gp1(0x03000000)                 # SetDispMask(1): display on


def put_draw_env(s, w, h):
    s.gp0(0xe3000000,
          0xe4000000 | ((w - 1) & 0x3ff) | (((h - 1) & 0x1ff) << 10),
          0xe5000000,
          e1(0, 1, 0x0a))             # SetDefDrawEnv: tpage 0x0A, dtd 1, dfe 0


def fill(s, x, y, w, h, r, g, b):
    s.gp0(0x02000000 | rgb(r, g, b), xy(x, y), xy(w, h))


def clear_screen_color(s, r, g, b):
    fill(s, 0, 0, 512, 256, r, g, b)
    fill(s, 512, 0, 512, 256, r, g, b)
    fill(s, 0, 256, 512, 256, r, g, b)
    fill(s, 512, 256, 0x3f1, 256, r, g, b)


# ---------------------------------------------------------------- tests

def t_transparency(s):
    # image da6b472: draw area 320x240, clearScreen() fills white
    init_video(s, 320, 240)
    clear_screen_color(s, 0xff, 0xff, 0xff)
    bg = [0, 64, 128, 255]
    # loop body (idempotent: the strips are refilled every frame)
    for i in range(4):
        fill(s, 320 // 4 * i, 0, 320 // 4, 240, bg[i], bg[i], bg[i])
    for mode in range(4):
        s.gp0(e1(1, 0, get_tpage(0, mode, 0, 0)))
        for x in range(32):
            S = 8
            r, g, b = 128 * (x & 1), 128 * ((x >> 1) & 1), 128 * ((x >> 2) & 1)
            s.gp0(0x62000000 | rgb(r, g, b), xy(1 + (S + 2) * x, 64 + (S + 16) * mode), xy(S, S))


def tri_vertices(cx, cy, a):
    f32 = np.float32
    h = f32(a) * f32(0.866025)
    h2 = h / f32(2)
    x = [cx - a // 2, cx + a // 2, cx]
    y = [int(f32(cy) + h2), int(f32(cy) + h2), int(f32(cy) - h2)]   # C float->int truncates
    return x, y


def poly_g3(s, xs, ys, cols):
    s.gp0(0x30000000 | rgb(*cols[0]), xy(xs[0], ys[0]),
          rgb(*cols[1]), xy(xs[1], ys[1]),
          rgb(*cols[2]), xy(xs[2], ys[2]))


def t_triangle(s):
    init_video(s, 1024, 512)
    clear_screen_color(s, 0xff, 0xff, 0xff)
    cols = [(255, 0, 0), (0, 255, 0), (0, 0, 255)]
    s.gp0(e1(1, 0, get_tpage(0, 0, 0, 0)))
    poly_g3(s, *tri_vertices(160, 120, 240), cols)
    poly_g3(s, *tri_vertices(768, 256, 500), cols)
    s.gp0(e1(1, 1, get_tpage(0, 0, 0, 0)))
    poly_g3(s, *tri_vertices(160, 240 + 120, 240), cols)


def vram_put(s, x, y, pix):
    s.gp0(0xa0000000, xy(x, y), xy(1, 1), pix & 0xffff)


def t_uv_interpolation(s):
    init_video(s, 1024, 512)
    clear_screen_color(s, 0, 0, 0)
    s.gp0(e1(1, 0, get_tpage(0, 0, 0, 0)))
    U, V = 512, 0
    vram_put(s, U, V, 0x001f)
    vram_put(s, U + 1, V, 0x03e0)
    tpage = get_tpage(2, 0, U, V)                     # 0x108
    u0, u1, v0 = U & 0xff, (U + 1) & 0xff, V & 0xff   # setUV4 stores unsigned char
    for i in range(256):                              # interpolateUv(0, 0)
        x, y, w = 0, i, i
        s.gp0(0x2c000000 | rgb(0x80, 0x80, 0x80),
              xy(x, y), (0 << 16) | (v0 << 8) | u0,          # clut not set by the test (unused at 15 bit)
              xy(x + w, y), (tpage << 16) | (v0 << 8) | u1,
              xy(x, y + 1), (v0 << 8) | u0,
              xy(x + w, y + 1), (v0 << 8) | u1)

    def interp_color(X, Y):
        for i in range(256):
            x, y, w = X, Y + i, i
            s.gp0(0x38000000 | rgb(0xff, 0, 0), xy(x, y),
                  rgb(0, 0xff, 0), xy(x + w, y),
                  rgb(0xff, 0, 0), xy(x, y + 1),
                  rgb(0, 0xff, 0), xy(x + w, y + 1))
    interp_color(0, 256)
    s.gp0(e1(1, 1, get_tpage(0, 0, 0, 0)))
    interp_color(256, 256)


def t_quad(s):
    # image 603a536: draw area 320x240; clearScreen = two white fills 1023 x 256;
    # PutDrawEnv again before drawing; no E1 from the test (PutDrawEnv's E1:
    # tpage 0x0A, semi-transparency mode 0, dither on)
    init_video(s, 320, 240)
    fill(s, 0, 0, 1023, 256, 0xff, 0xff, 0xff)
    fill(s, 0, 256, 1023, 256, 0xff, 0xff, 0xff)
    put_draw_env(s, 320, 240)

    def f4(c, v):
        s.gp0(0x2a000000 | rgb(*c), *[xy(a, b) for a, b in v])
    X = [48, 176, 64, 208]
    Y = [48, 32, 144, 160]
    W, H = 320, 240
    f4((0, 0, 0), list(zip(X, Y)))
    f4((0xff, 0, 0), [(0, 0), (X[0], Y[0]), (0, H), (X[2], Y[2])])
    f4((0, 0xff, 0), [(0, 0), (W, 0), (X[0], 48), (X[1], Y[1])])
    f4((0, 0, 0xff), [(X[1], Y[1]), (W, 0), (X[3], Y[3]), (W, H)])
    f4((0xff, 0, 0xff), [(X[2], Y[2]), (X[3], Y[3]), (0, H), (W, H)])
    for y in range(2):
        for x in range(8):
            S = 16
            c = 0xa0 if y == 0 else 0xff
            f4((c * (x & 1), c * ((x >> 1) & 1), c * ((x >> 2) & 1)),
               [(64 + S * x, 192 + S * y), (64 + S * x + S, 192 + S * y),
                (64 + S * x, 192 + S + S * y), (64 + S * x + S, 192 + S + S * y)])


def isin(x):
    """PSn00bSDK psxgte/isin.c (32-bit int arithmetic)."""
    def i32(v):
        v &= 0xffffffff
        return v - (1 << 32) if v & 0x80000000 else v
    qN, qA, B, C = 10, 12, 19900, 3516
    c = i32(x << (30 - qN))
    x = i32(x - (1 << qN))
    x = i32(x << (31 - qN))
    x = x >> (31 - qN)
    x = i32(x * x) >> (2 * qN - 14)
    y = B - (i32(x * C) >> 14)
    y = (1 << qA) - (i32(x * y) >> 16)
    return y if c >= 0 else -y


def icos(x):
    return isin(x + 1024)


def cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def t_lines(s):
    # image d1a63ee: draw area 320x240, clearScreen white every frame
    init_video(s, 320, 240)
    clear_screen_color(s, 0xff, 0xff, 0xff)

    def setE1(mode, dith):
        s.gp0(e1(1, dith, get_tpage(0, mode, 0, 0)))

    def f2(c, x0, y0, x1, y1, code=0x40):
        s.gp0((code << 24) | rgb(*c), xy(x0, y0), xy(x1, y1))
    setE1(0, 0)
    for y in range(10):
        f2((0, 0, 0), 16, 16 + y * 8, 16 + 80, 16 + y * 8 + y)
    for x in range(10):
        f2((0, 0, 0), 110 + x * 8, 16, 110 + x * 8 + x, 16 + 80)
    for y in range(20):
        f2((0, 0, 0), 200, 16 + y * 4, 200 + y, 16 + y * 4 + 1)

    def flat_lines(X, Y):
        for i in range(64):
            f2((0xaa, 0, 0), X, Y + i, X + i, Y + i)

    def gouraud_lines(X, Y):
        for i in range(64):
            s.gp0(0x50000000 | rgb(0, 0, 0), xy(X, Y + i), rgb(0xff, 0, 0), xy(X + i, Y + i))
    setE1(0, 0)
    flat_lines(16, 100)
    gouraud_lines(16, 166)
    setE1(0, 1)
    flat_lines(84, 100)
    gouraud_lines(84, 166)

    def flat_multi(X, Y, t):
        s.gp0(((0x4c | (2 if t else 0)) << 24) | rgb(0xaa, 0, 0),
              xy(X, Y), xy(X + 32, Y), xy(X + 32, Y + 32), xy(X, Y), 0x55555555)

    def gouraud_multi(X, Y, t):
        # r3/g3/b3 are never set in the test (stack contents): sent as 0 here,
        # so the last segment (back to the start) is not comparable
        s.gp0(((0x5c | (2 if t else 0)) << 24) | rgb(0xff, 0, 0), xy(X, Y),
              rgb(0, 0xff, 0), xy(X + 32, Y),
              rgb(0, 0xff, 0xff), xy(X + 32, Y + 32),
              rgb(0, 0, 0), xy(X, Y), 0x55555555)
    flat_multi(150, 100, False)
    flat_multi(210, 100, True)
    gouraud_multi(150, 140, False)
    gouraud_multi(210, 140, True)
    PI = 4096 // 2
    segs, cx, cy, scale = 16, 200, 200, 140
    A = 2 * PI // segs
    HA = A // 2
    for k in range(segs):
        f2((0, 0, 0), cx + cdiv(icos(A * k - HA), scale), cy + cdiv(isin(A * k - HA), scale),
           cx + cdiv(icos(A * k + HA), scale), cy + cdiv(isin(A * k + HA), scale))


class Rand:
    """PSn00bSDK libc/rand.s: seed = seed * 0x41c64e6d + 12345, return seed & 0x7fff."""
    def __init__(self, seed=1):
        self.seed = seed

    def __call__(self):
        self.seed = (self.seed * 0x41c64e6d + 12345) & 0xffffffff
        return self.seed & 0x7fff


def lena_tim():
    import re
    txt = open(PS1T + '/gpu/rectangles/lena.h').read()
    b = bytes(int(h, 16) for h in re.findall(r'0x([0-9a-fA-F]{2})', txt))
    magic, flags = struct.unpack_from('<II', b, 0)
    assert magic == 0x10 and flags == 2, (magic, flags)        # 16 bpp, no CLUT
    ln, x, y, w, h = struct.unpack_from('<IHHHH', b, 8)
    data = b[20:20 + w * h * 2]
    assert len(data) == w * h * 2
    return x, y, w, h, data


def t_rectangles(s, iterations=16):
    # image 86a6f3c: draw area 320x240, white clear once; the loop is NOT
    # idempotent (semi-transparent rectangles blend over the previous frame),
    # so the loop body is repeated until the blends reach their fixed point
    init_video(s, 320, 240)
    clear_screen_color(s, 0xff, 0xff, 0xff)
    tx, ty, tw, th, data = lena_tim()
    s.gp1(0x04000000)                                       # LoadImage: DMA off,
    s.gp0_cpu(0x01000000, 0xa0000000, xy(tx, ty), xy(tw, th))   # header by CPU writes
    s.gp1(0x04000002)
    s.gp0(*struct.unpack('<%dI' % (len(data) // 4), data))
    rnd = Rand()

    def rcol(i):
        r = (32 + (i * 1831) % 192) & 0xff
        g = (32 + (i * 2923) % 192) & 0xff
        b = (32 + (i * 5637) % 192) & 0xff
        return r | g << 8 | b << 16

    def draw(X, Y):
        for y in range(12):
            for x in range(16):
                t = 0x60 + y * 16 + x
                if t > 0x7f:
                    return
                words = [(t << 24) | rcol(t), (((Y + y * 20) & 0xffff) << 16) | ((X + x * 20) & 0xffff)]
                if t & 4:
                    u = rnd() % 64
                    v = rnd() % 64
                    words.append((0 << 16) | (v << 8) | u)
                if ((t & 0x18) >> 3) == 0:
                    w = 10 + rnd() % 10
                    h = 10 + rnd() % 10
                    words.append((h << 16) | w)
                s.gp0(*words)
    for _ in range(iterations):
        rnd.seed = 321
        for mode, dith, Y in ((0, 0, 0), (1, 1, 64), (2, 1, 128), (3, 1, 192)):
            s.gp0(e1(1, dith, get_tpage(2, mode, tx, ty)))
            draw(0, Y)


TESTS = {
    'transparency': t_transparency,
    'triangle': t_triangle,
    'uv-interpolation': t_uv_interpolation,
    'quad': t_quad,
    'lines': t_lines,
    'rectangles': t_rectangles,
}


def main():
    if '--list' in sys.argv:
        print('\n'.join(TESTS))
        return
    name, out = sys.argv[1], sys.argv[2]
    s = Stream()
    TESTS[name](s)
    n = s.write(out)
    print(f'{name}: {n} words written to {out}')


if __name__ == '__main__':
    main()
