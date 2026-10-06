#!/usr/bin/env python3
"""Reference for frames.tsv rows (tb_fullsys.cpp, format agreed with
gnet-games tools/frame_hash.py): prints frame t_s(blank) w h crc555
crc555_x1 ahash dhash luma for given PPM files, to check the harness."""
import sys, zlib, struct
def ppm(fn):
    d = open(fn, 'rb').read(); parts = d.split(b'\n', 3)
    w, h = map(int, parts[1].split()); return w, h, parts[3]
def cells(Y, w, h, nx, ny):
    C = []
    for j in range(ny):
        for i in range(nx):
            x0, x1, y0, y1 = i*w//nx, (i+1)*w//nx, j*h//ny, (j+1)*h//ny
            s = sum(Y[y*w + x] for y in range(y0, y1) for x in range(x0, x1))
            n = (x1-x0)*(y1-y0); C.append(s//n if n else 0)
    return C
for fn in sys.argv[1:]:
    w, h, px = ppm(fn)
    words = []; Y = []
    for k in range(w*h):
        r5, g5, b5 = px[3*k] >> 3, px[3*k+1] >> 3, px[3*k+2] >> 3
        words.append(r5 << 10 | g5 << 5 | b5); Y.append(299*r5 + 587*g5 + 114*b5)
    full = b''.join(struct.pack('<H', v) for v in words)
    x1 = b''.join(struct.pack('<H', words[y*w + x]) for y in range(h) for x in range(1, w))
    C = cells(Y, w, h, 8, 8); S = sum(C); a = 0
    for c in C: a = (a << 1) | (64*c > S)
    D = cells(Y, w, h, 9, 8); d = 0
    for j in range(8):
        for i in range(8): d = (d << 1) | (D[j*9+i] < D[j*9+i+1])
    fr = int(fn.rsplit('f', 1)[1].split('.')[0])
    print(f"{fr}\t-\t{w}\t{h}\t{zlib.crc32(full):08x}\t{zlib.crc32(x1):08x}\t{a:016x}\t{d:016x}\t{sum(Y)/(w*h)*255/31000:.2f}")
