#!/usr/bin/env python3
"""Worst-case load for the ZSG-2 replay testbench, with expected outputs from
tools/zsg2/zsg2_model.py: all 48 channels at the maximum pitch (step
0x10000, one block per sample, so 24 line fetches per sample) with distinct
start addresses, then N samples. The testbench reports the longest pass and
whether any block arrived late (docs/zsg2_rtl.md 5).

  zsg2_stress.py <flashdir> <out.ev> [samples] [--stagger]

--stagger keys the channels on one per sample (steady state); without it
all 48 key on together (burst).
"""
import sys
from zsg2_model import Zsg2
from zsg2_directed import load_flash


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    stagger = '--stagger' in sys.argv
    fl, out = args[0], args[1]
    n = int(args[2]) if len(args) > 2 else 4000
    m = Zsg2(load_flash(fl), 3)
    m.reset()
    k = 0
    with open(out, 'w') as f:
        f.write('X\n')

        def w(a, d):
            m.write(a, d)
            f.write('W %03x %04x\n' % (a, d))

        def t():
            nonlocal k
            k += 1
            o = m.render()
            f.write('T %d\nO %d %d %d %d %d\n' % (k, k, o[0], o[1], o[2], o[3]))

        for ch in range(48):
            base = ch * 0x20 >> 1
            start = 0x0100 + ch * 0x0400
            page = ch % 24
            end, loop = start + 0x3f0, start + 0x10
            regs = [0] * 16
            regs[0] = (start & 0xff) << 8
            regs[1] = (page << 8) | (start >> 8)
            regs[3] = 0x0400
            regs[4] = 0xffff                     # step 0x10000
            regs[5] = (0x1f << 8) | (loop & 0xff)
            regs[6] = end
            regs[7] = (0x1f << 8) | (loop >> 8)
            regs[8] = 0x8000
            regs[0xc] = 0x9000
            regs[0xd] = (0x1f << 8) | 0x17
            regs[0xe] = 0x8000
            regs[0xf] = (0x1f << 8) | 0x17
            for r in range(16):
                w(base + r, regs[r])
        if stagger:
            for ch in range(48):
                w(0x300 + ch // 16, 1 << (ch % 16))
                t()
        else:
            for g in range(3):
                w(0x300 + g, 0xffff)
        while k < n:
            t()


if __name__ == '__main__':
    main()
