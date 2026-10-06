#!/usr/bin/env python3
"""Compare the TMS57002 SO1 streams (aud.bin: int16 L, R per output FIFO
push, in the board's virtual time) of two Zoom bench runs.

  cmp_audio.py <run A dir> <run B dir>
"""
import array, sys

def load(d):
    a = array.array('h'); a.frombytes(open(d + '/aud.bin', 'rb').read()); return a

A, B = load(sys.argv[1]), load(sys.argv[2])
na, nb = len(A) // 2, len(B) // 2
n = min(na, nb)
diff = [i for i in range(n) if A[2 * i] != B[2 * i] or A[2 * i + 1] != B[2 * i + 1]]
nz = sum(1 for i in range(n) if A[2 * i] or A[2 * i + 1])
print(f'samples: A {na}, B {nb} ({na / 32552.083:.3f} s and {nb / 32552.083:.3f} s); non-zero in A {nz}')
if not diff:
    print(f'SO1 streams: identical over {n} samples')
else:
    i = diff[0]
    err = sum((A[2 * k] - B[2 * k]) ** 2 + (A[2 * k + 1] - B[2 * k + 1]) ** 2 for k in diff)
    sig = sum(A[2 * k] ** 2 + A[2 * k + 1] ** 2 for k in range(n)) or 1
    print(f'SO1 streams: {len(diff)} of {n} samples differ, first at {i} ({i / 32552.083:.4f} s), last at {diff[-1]}; '
          f'error energy / signal energy {err / sig:.3e}')
