#!/usr/bin/env python3
"""Static MDEC check on main-RAM dumps (tools/mame/r18_trace.lua R18_RAMDUMP).

PsyQ-style code reaches hardware through register addresses kept as 32-bit
data words (e.g. GPU_DATA = 0x1f801810), so this counts aligned words equal
to each register address in KUSEG, KSEG0 or KSEG1 form. GPU GP0/GP1 is the
positive control: every game writes the GPU, so its count must be non-zero
for a zero MDEC count to mean anything.

(An earlier version looked for `lui 0x1f80` + offset instruction pairs; the
GPU control showed zero, so that pattern is not how these games address
hardware and the method was dropped.)
"""
import struct
import sys

REGS = {
    'GPU GP0/GP1 (control)': [0x1f801810, 0x1f801814],
    'SPU base (control)': [0x1f801c00, 0x1f801d80, 0x1f801d88],
    'MDEC0/MDEC1': [0x1f801820, 0x1f801824],
    'DMA0 MADR/BCR/CHCR (MDEC in)': [0x1f801080, 0x1f801084, 0x1f801088],
    'DMA1 MADR/BCR/CHCR (MDEC out)': [0x1f801090, 0x1f801094, 0x1f801098],
}


def forms(a):
    return {a, a | 0x80000000, a | 0xa0000000}


for path in sys.argv[1:]:
    data = open(path, 'rb').read()
    words = struct.unpack('<%dI' % (len(data) // 4), data)
    count = {}
    for w in words:
        count[w] = count.get(w, 0) + 1
    print(path)
    for name, addrs in REGS.items():
        n = sum(count.get(f, 0) for a in addrs for f in forms(a))
        print(f'  {name:32s} {n:5d}')
