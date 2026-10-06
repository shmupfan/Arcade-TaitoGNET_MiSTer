#!/usr/bin/env python3
"""Assemble the R1 system smoke program (sim/cpu50/tb_cpu50_system) into a
BIOS image: MIPS R3000 code at 0xBFC00000 that drives every crossing the
CPU uses at run time and leaves its results in RAM at 0x100 to 0x11C:

  0x100  0x11111111        start marker (RAM write through the SDRAM)
  0x104  GPUSTAT           after GP1(00) reset and four GP0 commands
  0x108  SPU 0x1DA6 read   after writing 0x1234 (TRANSFERADDR)
  0x10C  SPU 0x1DA4 read   after writing 0xBEEF (IRQ address)
  0x110  timer 2 before    root counter 2, system clock source
  0x114  timer 2 after     100-iteration loop later
  0x118  GPUREAD           two pixels of the filled rectangle (GP0 C0h)
  0x11C  0x600DF00D        done marker

    smoke_prog.py <out.bin>
"""
import struct
import sys

R = {'zero': 0, 't0': 8, 't1': 9, 't2': 10, 't3': 11, 't4': 12, 't5': 13, 's0': 16}


def i_type(op, rs, rt, imm):
    return (op << 26) | (R[rs] << 21) | (R[rt] << 16) | (imm & 0xFFFF)


def lui(rt, imm): return i_type(0x0F, 'zero', rt, imm)
def ori(rt, rs, imm): return i_type(0x0D, rs, rt, imm)
def addiu(rt, rs, imm): return i_type(0x09, rs, rt, imm)
def sw(rt, off, rs): return i_type(0x2B, rs, rt, off)
def sh(rt, off, rs): return i_type(0x29, rs, rt, off)
def lw(rt, off, rs): return i_type(0x23, rs, rt, off)
def lhu(rt, off, rs): return i_type(0x25, rs, rt, off)
NOP = 0


def li32(rt, v):
    return [lui(rt, v >> 16), ori(rt, rt, v & 0xFFFF)]


def main(out):
    p = []
    p += [lui('t0', 0x1F80), lui('s0', 0xA000)]
    p += li32('t1', 0x11111111) + [sw('t1', 0x100, 's0')]
    # bus delays as the PS1 BIOS sets them: SPU 16-bit, COM delays
    p += li32('t1', 0x200931E1) + [sw('t1', 0x1014, 't0')]
    p += li32('t1', 0x00031125) + [sw('t1', 0x1020, 't0')]
    # GPU: GP1(00) reset, draw area, offset, fill rectangle (16, 8) 32 x 4 red
    p += [sw('zero', 0x1814, 't0')]
    p += [lui('t1', 0xE300), sw('t1', 0x1810, 't0')]
    p += li32('t1', 0xE407FFFF) + [sw('t1', 0x1810, 't0')]
    p += [lui('t1', 0xE500), sw('t1', 0x1810, 't0')]
    p += li32('t1', 0x020000FF) + [sw('t1', 0x1810, 't0')]
    p += li32('t1', 0x00080010) + [sw('t1', 0x1810, 't0')]
    p += li32('t1', 0x00040020) + [sw('t1', 0x1810, 't0')]
    p += [lw('t2', 0x1814, 't0'), NOP, sw('t2', 0x104, 's0')]
    # SPU registers: write, read back
    p += [ori('t1', 'zero', 0x1234), sh('t1', 0x1DA6, 't0'), lhu('t2', 0x1DA6, 't0'), NOP, sw('t2', 0x108, 's0')]
    p += [ori('t1', 'zero', 0xBEEF), sh('t1', 0x1DA4, 't0'), lhu('t2', 0x1DA4, 't0'), NOP, sw('t2', 0x10C, 's0')]
    # timer 2 around a 100-iteration loop
    p += [lw('t3', 0x1120, 't0'), NOP, ori('t4', 'zero', 100)]
    loop = len(p)
    p += [addiu('t4', 't4', -1)]
    p += [i_type(0x05, 't4', 'zero', (loop - (len(p) + 1)) & 0xFFFF), NOP]   # bne t4, zero, loop
    p += [lw('t5', 0x1120, 't0'), NOP, sw('t3', 0x110, 's0'), sw('t5', 0x114, 's0')]
    # VRAM to CPU: GP0 C0h, 2 x 1 pixels at (16, 8), one GPUREAD
    p += [lui('t1', 0xC000), sw('t1', 0x1810, 't0')]
    p += li32('t1', 0x00080010) + [sw('t1', 0x1810, 't0')]
    p += li32('t1', 0x00010002) + [sw('t1', 0x1810, 't0')]
    p += [lw('t2', 0x1810, 't0'), NOP, sw('t2', 0x118, 's0')]
    p += li32('t1', 0x600DF00D) + [sw('t1', 0x11C, 's0')]
    end = len(p)
    p += [(0x02 << 26) | (((0xBFC00000 + 4 * end) >> 2) & 0x3FFFFFF), NOP]   # j end
    with open(out, 'wb') as f:
        for w in p:
            f.write(struct.pack('<I', w))
    print(f'{out}: {len(p)} words')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
