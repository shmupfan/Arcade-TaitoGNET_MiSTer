#!/usr/bin/env python3
"""R23: GPU drawing speed of the core against PS1 hardware, using the
primitives of JaCzekanski/ps1-tests gpu/bandwidth (MIT, reference/ps1-tests
f727802; hardware result in gpu/bandwidth/psx.log: 400 calls per test,
full-screen 320x240 primitives, timed with timer 1 in hblanks).

  tools/gpu_time_bench.py stream <out.txt> [N]
      replay stream for sim/m1/tb_gpu_replay.vhd (GTIME): setup in frame 0
      (initVideo: ResetGraph, display 320x240, draw area 0,0-1023,511,
      offset 0, E1 tpage 0x0A with dither), then per test k the
      clearScreen() fills in frame 4k+2 and N calls of the test's primitive
      in frame 4k+3. VRAM starts at zero, as after clearScreen() on the
      console, so every texel is 0 (transparent) in both.
  tools/gpu_time_bench.py compare <frames_time.txt> [N]
      per test: core time per primitive (span / N) against the console's
      dT / 400, and the ratio.
"""
import os
import sys

T2X_NS = 14.762
HLINE_HZ = 53693175 / 3413                               # NTSC line rate, 15,732 Hz
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PSXLOG = os.path.join(ROOT, 'reference/ps1-tests/gpu/bandwidth/psx.log')
W, H = 320, 240
CLUT = ((256 << 6) | (768 >> 4)) << 16                  # setClut(768, 256)
TPAGE_FT4 = ((512 >> 6) | (256 >> 8) << 4 | 0 << 5 | 2 << 7) << 16   # getTPage(2, 0, 512, 256)


def xy(x, y):
    return ((y & 0xffff) << 16) | (x & 0xffff)


def fill(x, y, w, h):
    return [0x02000000, xy(x, y), (h << 16) | w]


def tests():
    t = []
    t.append(('cpuToVram', lambda: [0xa0000000, xy(0, 0), (H << 16) | W] + [0] * (W * H // 2)))
    t.append(('vramToVram', lambda: [0x80000000, xy(0, 0), xy(320, 0), (H << 16) | W]))
    t.append(('FillScreen GP0(2)', lambda: [0x02404040, xy(0, 0), (H << 16) | W]))
    for semi, nm in ((0, 'Rectangle'), (1, 'Rectangle (semitransparent)')):
        t.append((nm, (lambda s: lambda: [0x60404040 | s << 25, xy(0, 0), (H << 16) | W])(semi)))
    for semi, nm in ((0, 'Rectangle textured'), (1, 'Rectangle textured (semi)')):
        t.append((nm, (lambda s: lambda: [0x64404040 | s << 25, xy(0, 0), CLUT, (H << 16) | W])(semi)))

    def quad(s, xo=0):
        return [0x28404040 | s << 25, xy(xo, 0), xy(xo + W, 0), xy(xo, H), xy(xo + W, H)]
    t.append(('Polygon quad', lambda: quad(0)))
    t.append(('Polygon quad (semi)', lambda: quad(1)))

    def quadt(s):
        return [0x2d808080 | s << 25, xy(0, 0), CLUT | 0x0000, xy(W, 0), TPAGE_FT4 | 0x00ff,
                xy(0, H), 0xff00, xy(W, H), 0xffff]
    t.append(('Polygon quad textured', lambda: quadt(0)))
    t.append(('Polygon quad textured (semi)', lambda: quadt(1)))
    t.append(('Polygon quad (1/4 off screen)', lambda: quad(0, -W // 4)))
    t.append(('Polygon quad (1/2 off screen)', lambda: quad(0, -W // 2)))
    return t


def stream(out, n):
    with open(out, 'w') as f:
        def put(kind, fr, words):
            for w in words:
                f.write('%02x %08x %08x\n' % (kind, fr, w & 0xffffffff))
        # initVideo(320, 240): ResetGraph(0), PutDispEnv, PutDrawEnv, SetDispMask(1)
        put(1, 0, [0x00000000, 0x01000000, 0x05000000, 0x06c60260, 0x07040010, 0x08000001])
        put(0, 0, [0xe100020a, 0xe3000000, 0xe4000000 | (511 << 10) | 1023, 0xe5000000, 0xe6000000])
        put(1, 0, [0x03000000, 0x04000002])            # display on, DMA direction CPU to GPU
        for k, (nm, fn) in enumerate(tests()):
            put(0, 4 * k + 2, fill(0, 0, 512, 256) + fill(512, 0, 512, 256) + fill(0, 256, 512, 256)
                + fill(512, 256, 0x3f1, 256))
            kind = 2 if nm == 'cpuToVram' else 0
            for _ in range(n):
                if kind == 2:
                    w = fn()
                    put(0, 4 * k + 3, w[:3])          # header by CPU, pixel data by DMA
                    put(2, 4 * k + 3, w[3:])
                else:
                    put(2, 4 * k + 3, fn())
    print(f'{out}: {len(tests())} tests, {n} primitives each, MAXFRAME {4 * len(tests()) + 4}')


def compare(path, n):
    hw = {}
    for ln in open(PSXLOG):
        if 'dT:' in ln:
            name = ln.split('dT:')[0].strip()
            hbl = int(ln.split('hblanks:')[1].split(')')[0])
            hw[name] = hbl / HLINE_HZ * 1e3 / 400     # the test's own dT rounds 263 x 60 Hz
    rows = {}
    for ln in open(path):
        p = list(map(int, ln.split()[:8]))
        rows[p[0]] = p
    print(f'{"test":32s} {"PS1 ms/prim":>11s} {"core ms/prim":>12s} {"PS1/core":>8s}')
    for k, (nm, _) in enumerate(tests()):
        r = rows.get(4 * k + 3)
        if not r:
            continue
        core = r[4] * T2X_NS / 1e6 / n
        h = hw.get(nm)
        print(f'{nm:32s} {h:11.4f} {core:12.4f} {h / core:8.2f}' + ('  overrun' if r[6] else ''))


if __name__ == '__main__':
    if sys.argv[1] == 'stream':
        stream(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 8)
    else:
        compare(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 8)
