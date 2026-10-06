#!/usr/bin/env python3
"""Compare a bench SO1 stream (aud.bin, int16 L/R per output FIFO push) with
MAME's Zoom output before the SPU mix (tools/zoom/zoom_hostlog_aud.lua:
TMS57002 so[2]/so[3] >> 8 per sample). Aligns by the first non-zero sample,
then refines the offset (+-300 samples) for the most exact matches over the
first 4,000 samples after the onset; reports exact matches, max abs error,
where the first difference is and the RMS of both.

  cmp_mame_audio.py <mame aud.bin> <bench aud.bin>
"""
import array, math, sys
def load(p):
    a = array.array('h'); a.frombytes(open(p, 'rb').read()); return a
M, B = load(sys.argv[1]), load(sys.argv[2])
nm, nb = len(M) // 2, len(B) // 2
fm = next(i for i in range(nm) if M[2 * i] or M[2 * i + 1])
fb = next(i for i in range(nb) if B[2 * i] or B[2 * i + 1])
base = fb - fm
def matches(off, a, n):
    c = 0
    for i in range(a, a + n):
        j = i + off
        if 0 <= j < nb and M[2 * i] == B[2 * j] and M[2 * i + 1] == B[2 * j + 1]: c += 1
    return c
best = max(range(base - 300, base + 301), key=lambda o: matches(o, fm, 4000))
n = min(nm, nb - best) - fm
eq = 0; mx = 0; first = None; err2 = 0; sm = 0; sb = 0
for i in range(fm, fm + n):
    j = i + best
    dl, dr = M[2 * i] - B[2 * j], M[2 * i + 1] - B[2 * j + 1]
    if dl == 0 and dr == 0: eq += 1
    elif first is None: first = i
    mx = max(mx, abs(dl), abs(dr)); err2 += dl * dl + dr * dr
    sm += M[2 * i] ** 2 + M[2 * i + 1] ** 2; sb += B[2 * j] ** 2 + B[2 * j + 1] ** 2
R = 32552.083
print(f'MAME first non-zero sample {fm} ({fm / R:.4f} s after t0), bench {fb} ({fb / R:.4f} s); offset bench - MAME {best} samples (first-non-zero offset {base})')
print(f'compared {n} samples from the onset: exact {eq} ({100 * eq / max(1, n):.2f}%), max abs error {mx}, '
      f'RMS MAME {math.sqrt(sm / max(1, 2 * n)):.1f}, bench {math.sqrt(sb / max(1, 2 * n)):.1f}, error {math.sqrt(err2 / max(1, 2 * n)):.1f}')
if first is not None:
    j = first + best
    print(f'first difference at MAME sample {first} ({first / R:.4f} s, {first - fm} after the onset): MAME {M[2 * first]} {M[2 * first + 1]}, bench {B[2 * j]} {B[2 * j + 1]}')
