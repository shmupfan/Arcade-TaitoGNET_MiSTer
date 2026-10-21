#!/usr/bin/env python3
"""GPU stream for the reqVRAMwrap check (docs/area_timing.md 9).

Writes a tb_gpu_infl stream (one GP0/GP1 word per line, "KK FFFFFFFF WWWWWWWW")
that fills and uploads source data on both sides of the VRAM x = 1023 / 0
seam, then runs VRAM-to-VRAM copies whose source rows wrap past x = 1024
(short, unaligned, a 100-wide one, a 600-wide one that also needs
reqVRAMnext, one whose destination wraps too) and two that end exactly at
x = 1024. Compare vram_3.bin and ddr3_frames.txt of two GPU builds:

  sim/gpuinfl/wrap_stream.py > s.txt; python3 -c "open('z.bin','wb').write(bytes(2<<20))"
  sim/gpuinfl/run.sh <name> $PWD/s.txt $PWD/z.bin 3 -gDUMPS=3 [-gARB=true]
"""
L = []


def gp0(w):
    L.append("00 %08X %08X" % (1, w))


def gp1(w):
    L.append("01 %08X %08X" % (1, w))


def upload(x, y, w, h, seed):
    gp0(0xA0000000); gp0((y << 16) | x); gp0((h << 16) | w)
    px = [((seed * 131 + i * 7 + 1) & 0x7FFF) for i in range(w * h)]
    if len(px) % 2:
        px.append(0)
    for i in range(0, len(px), 2):
        gp0(px[i] | (px[i + 1] << 16))


def copy(sx, sy, dx, dy, w, h):
    gp0(0x80000000); gp0((sy << 16) | sx); gp0((dy << 16) | dx); gp0((h << 16) | w)


gp1(0x00000000)
gp0(0x02123456); gp0((0 << 16) | 512); gp0((16 << 16) | 512)
upload(960, 0, 64, 16, 1)
upload(0, 0, 64, 16, 2)
upload(600, 0, 40, 16, 3)
for bx in range(0, 192, 16):          # distinct fill colour per 16 x 4 block at x 0..191
    for by in range(0, 16, 4):
        col = ((bx * 3 + by * 29 + 17) & 0xFF) | (((bx + by * 7) & 0xFF) << 8) | (((bx * 5 + by) & 0xFF) << 16)
        gp0(0x02000000 | col); gp0((by << 16) | bx); gp0((4 << 16) | 16)
copy(1000, 0, 100, 100, 50, 8)
copy(1021, 2, 300, 120, 7, 4)
copy(1017, 0, 400, 140, 100, 8)
copy(600, 0, 0, 300, 600, 4)
copy(1022, 5, 1010, 200, 30, 3)
copy(1023, 1, 500, 220, 1, 4)
copy(1019, 3, 520, 230, 5, 5)
print("\n".join(L))
