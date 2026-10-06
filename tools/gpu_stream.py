#!/usr/bin/env python3
"""Summarise a gpu_stream.bin from tools/mame/oracle.lua (ORACLE_GPU_STREAM=1).

Walks the records, splits GP0 words into commands using the PS1 GPU packet
lengths (polygons, lines incl. poly-lines, rectangles, VRAM transfers with
their image data), and prints counts per command class and per frame.
  tools/gpu_stream.py <gpu_stream.bin>
  tools/gpu_stream.py <gpu_stream.bin> --text <out.txt> [--maxframe N] [--from F]
      write the M1 replay input for sim/m1/tb_gpu_replay.vhd: one word per
      line, "KK FFFFFFFF WWWWWWWW" (kind 0 GP0, 1 GP1, 2/3 DMA; kind 4 is
      dropped), frames up to N
      --from F: seek. Start at MAME frame F (pair with the MAME VRAM dump of
      frame F loaded by the testbench, generic VRAM_INIT): first a preamble at
      frame 0 with the last write of every GP1 command and every GP0 E1-E6
      word seen before F, then the records from F on with frames renumbered
      from 0. Commands in flight across the frame boundary are not
      reconstructed, so pick F at a quiet point and check the first frames.
"""
import collections
import struct
import sys

KIND = {0: 'cpu_gp0', 1: 'cpu_gp1', 2: 'dma_block', 3: 'dma_list', 4: 'dma_other'}


def records(path):
    b = open(path, 'rb').read()
    i = 0
    while i + 9 <= len(b):
        fr, kind, n = struct.unpack_from('<IBI', b, i)
        i += 9
        words = struct.unpack_from('<%dI' % n, b, i)
        i += 4 * n
        yield fr, kind, words


def gp0_len(w):
    op = w >> 24
    if 0x20 <= op <= 0x3f:                       # polygon
        verts = 4 if op & 8 else 3
        per = 1 + (1 if op & 4 else 0) + (1 if op & 0x10 else 0)
        return 1 + verts * per - (1 if op & 0x10 else 0), 'polygon'
    if 0x40 <= op <= 0x5f:                       # line (poly-line ends at 0x5xxx5xxx)
        if op & 8:
            return -1, 'polyline'
        return 3 + (1 if op & 0x10 else 0), 'line'
    if 0x60 <= op <= 0x7f:                       # rectangle
        n = 2 + (1 if op & 4 else 0) + (1 if (op >> 3) & 3 == 0 else 0)
        return n, 'rect'
    if 0x80 <= op <= 0x9f:
        return 4, 'vram_copy'
    if 0xa0 <= op <= 0xbf:
        return -2, 'cpu_to_vram'
    if 0xc0 <= op <= 0xdf:
        return 3, 'vram_to_cpu'
    if op == 0x02:
        return 3, 'fill'
    if 0xe1 <= op <= 0xe6:
        return 1, 'env'
    return 1, 'misc'


def write_text(path, out, maxframe, start=0):
    n = 0
    gp1_last = {}           # GP1 command byte -> word
    env_last = {}           # GP0 E1..E6 -> word (only those sent as single words)
    pend = []               # GP0 words before start, to find E1-E6 commands
    with open(out, 'w') as f:
        started = start == 0
        for fr, kind, words in records(path):
            if maxframe is not None and fr > maxframe:
                break
            if kind > 3:
                continue
            if not started:
                if fr < start:
                    if kind == 1:
                        for w in words:
                            gp1_last[w >> 24] = w
                    else:
                        pend.extend(words)
                    continue
                # preamble: GP1 state in command order, then draw environment
                i = 0
                while i < len(pend):
                    w = pend[i]
                    n_, _cls = gp0_len(w)
                    if 0xe1 <= (w >> 24) <= 0xe6:
                        env_last[w >> 24] = w
                    if n_ == -1:
                        j = i + 1
                        while j < len(pend) and (pend[j] & 0xf000f000) != 0x50005000:
                            j += 1
                        n_ = j - i + 1
                    elif n_ == -2:
                        if i + 2 >= len(pend):
                            break
                        wh = pend[i + 2]
                        n_ = 3 + ((wh & 0xffff or 0x400) * ((wh >> 16) or 0x200) + 1) // 2
                    i += max(n_, 1)
                for c in sorted(gp1_last):
                    f.write('%02x %08x %08x\n' % (1, 0, gp1_last[c])); n += 1
                for c in sorted(env_last):
                    f.write('%02x %08x %08x\n' % (0, 0, env_last[c])); n += 1
                started = True
            for w in words:
                f.write('%02x %08x %08x\n' % (kind, fr - start, w))
                n += 1
    print(f'{n} words written to {out}' + (f' (seek from frame {start}: {len(gp1_last)} GP1 + {len(env_last)} env words)' if start else ''))


def main():
    path = sys.argv[1]
    if '--text' in sys.argv:
        mf = int(sys.argv[sys.argv.index('--maxframe') + 1]) if '--maxframe' in sys.argv else None
        st = int(sys.argv[sys.argv.index('--from') + 1]) if '--from' in sys.argv else 0
        write_text(path, sys.argv[sys.argv.index('--text') + 1], mf, st)
        return
    by_kind = collections.Counter()
    by_class = collections.Counter()
    frames = set()
    pend = []                 # GP0 word queue across records
    for fr, kind, words in records(path):
        by_kind[KIND.get(kind, kind)] += len(words)
        frames.add(fr)
        if kind in (0, 2, 3):
            pend.extend(words)
    i = 0
    while i < len(pend):
        n, cls = gp0_len(pend[i])
        if n == -1:            # poly-line: until terminator
            j = i + 1
            while j < len(pend) and (pend[j] & 0xf000f000) != 0x50005000:
                j += 1
            n = j - i + 1
        elif n == -2:          # CPU to VRAM: 3 words then w*h/2 data words
            if i + 2 >= len(pend):
                break
            wh = pend[i + 2]
            w, h = wh & 0xffff or 0x400, (wh >> 16) or 0x200
            n = 3 + (w * h + 1) // 2
        by_class[cls] += 1
        i += max(n, 1)
    print(f'records over {len(frames)} frames ({min(frames)}..{max(frames)})')
    for k, v in by_kind.items():
        print(f'  words {k:10s} {v:10,d}')
    for k, v in by_class.most_common():
        print(f'  GP0 {k:12s} {v:8,d}')


if __name__ == '__main__':
    main()
