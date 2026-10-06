#!/usr/bin/env python3
"""Compare the core's GPU command stream (sim/fullsys gpu.log) with MAME's
(tools/mame/oracle.lua, ORACLE_GPU_STREAM=1, gpu_stream.bin).

Both sides become two word sequences: GP0 (CPU writes to GP0 and DMA2 words
to the GPU, in arrival order) and GP1 (CPU writes). MAME's DMA2 records are
the RAM words at the CHCR start write (linked-list headers removed), the
core's are DMA_GPU_write at each DMA_GPU_writeEna, so the GP0 sequences are
the same stream if the BIOS issues the same commands. Timing is not
compared. Commands are split with tools/gpu_stream.py's packet lengths.

    compare_gpu.py <core gpu.log> <gpu_stream.bin> [--context N]
"""
import difflib, os, struct, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tools'))
from gpu_stream import records, gp0_len  # noqa: E402


def mame(path):
    gp0, gp1, fr0 = [], [], []
    for fr, kind, words in records(path):
        if kind in (0, 2, 3):
            gp0 += words; fr0 += [fr] * len(words)
        elif kind == 1:
            gp1 += words
    return gp0, gp1, fr0


def core(path):
    gp0, gp1, t0 = [], [], []
    for line in open(path):
        p = line.split()
        if len(p) != 3:
            continue
        w = int(p[2], 16)
        if p[1] in ('GP0', 'GPD'):
            gp0.append(w); t0.append(int(p[0]))
        elif p[1] == 'GP1':
            gp1.append(w)
    return gp0, gp1, t0


def packets(seq):
    """Split a GP0 word sequence into (start index, words) commands."""
    out, i = [], 0
    while i < len(seq):
        n, kind = gp0_len(seq[i])
        if n == -1:                                         # poly-line: up to the 5xxx5xxx terminator
            j = i + 1
            while j < len(seq) and (seq[j] & 0xf000f000) != 0x50005000:
                j += 1
            n = j + 1 - i
        elif n == -2:                                       # CPU to VRAM: header, xy, wh, data
            wh = seq[i + 2] if i + 2 < len(seq) else 0
            n = 3 + (((wh & 0xffff) or 0x10000) * ((wh >> 16) or 0x10000) + 1) // 2
        out.append((i, seq[i:i + n]))
        i += n
    return out


def main():
    cpath, mpath = sys.argv[1], sys.argv[2]
    ctx = int(sys.argv[sys.argv.index('--context') + 1]) if '--context' in sys.argv else 3
    c0, c1, ct = core(cpath)
    m0, m1, mf = mame(mpath)
    print(f'core: GP0 {len(c0):,} words, GP1 {len(c1):,}; MAME: GP0 {len(m0):,} words, GP1 {len(m1):,}')
    for name, a, b in (('GP1', c1, m1), ('GP0', c0, m0)):
        n = min(len(a), len(b))
        k = next((i for i in range(n) if a[i] != b[i]), n)
        if k == n:
            print(f'{name}: first {n:,} words equal (core has {len(a):,}, MAME {len(b):,})')
        else:
            print(f'{name}: first {k:,} words equal; first difference at word {k:,}')
            for i in range(max(0, k - ctx), min(n, k + ctx + 1)):
                extra = f'  core t={ct[i]} us, MAME frame {mf[i]}' if name == 'GP0' else ''
                print(f'   {i:>8,} core {a[i]:08X} MAME {b[i]:08X}{"  <--" if i == k else ""}{extra}')
    # command-level view of GP0: how many whole commands match, and the first that differs
    pc, pm = packets(c0), packets(m0)
    n = min(len(pc), len(pm))
    k = next((i for i in range(n) if pc[i][1] != pm[i][1]), n)
    print(f'GP0 commands: core {len(pc):,}, MAME {len(pm):,}; first {k:,} equal')
    if k < n:
        print(f'   core  #{k}: ' + ' '.join(f'{w:08X}' for w in pc[k][1][:8]))
        print(f'   MAME  #{k}: ' + ' '.join(f'{w:08X}' for w in pm[k][1][:8]))
    # alignment over whole commands: the core usually runs behind MAME, so
    # MAME is cut where the last core command aligns
    a = [tuple(p[1]) for p in pc]
    b = [tuple(p[1]) for p in pm[:int(len(pc) * 1.2) + 50]]
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    ops = sm.get_opcodes()
    last = max((i2 for t, i1, i2, j1, j2 in ops if t == 'equal'), default=0)
    lastj = max((j2 for t, i1, i2, j1, j2 in ops if t == 'equal'), default=0)
    eq = sum(i2 - i1 for t, i1, i2, j1, j2 in ops if t == 'equal' and i2 <= last)
    print(f'GP0 aligned: {eq:,} of the core\'s first {last:,} commands equal MAME\'s first {lastj:,}; differences:')
    shown = 0
    for t, i1, i2, j1, j2 in ops:
        if t == 'equal' or i1 >= last:
            continue
        if shown < int(os.environ.get('SHOW', '12')):
            ca = ' | '.join(' '.join(f'{w:08X}' for w in x[:4]) for x in a[i1:min(i2, i1 + 2)])
            mb = ' | '.join(' '.join(f'{w:08X}' for w in x[:4]) for x in b[j1:min(j2, j1 + 2)])
            print(f'   {t:7} core #{i1}-{i2} (t={ct[pc[i1][0]] if i1 < len(pc) else -1} us) [{ca}]  MAME #{j1}-{j2} (frame {mf[pm[j1][0]] if j1 < len(pm) else -1}) [{mb}]')
        shown += 1
    print(f'   {shown} difference blocks')


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main()
