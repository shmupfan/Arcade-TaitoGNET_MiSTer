#!/usr/bin/env python3
"""Disassemble a range of a PS1/ZN main RAM dump (MIPS I, little endian).

    tools/mame/r1_mips_dis.py <ram.bin> <start_va> <end_va>

<ram.bin> is the 4 MB dump that tools/mame/r1_bus.lua writes (ram_end.bin,
KSEG0 0x80000000 onwards). Addresses are virtual (0x80xxxxxx); KUSEG and
KSEG1 forms are folded. Needs the capstone Python module.
"""
import sys

import capstone


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    ram = open(sys.argv[1], "rb").read()
    start, end = (int(a, 16) & 0x1FFFFFFF for a in sys.argv[2:4])
    md = capstone.Cs(capstone.CS_ARCH_MIPS, capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
    code = ram[start:end]
    for ins in md.disasm(code, 0x80000000 + start):
        print(f"{ins.address:08x}  {ins.bytes[::-1].hex()}  {ins.mnemonic:8s} {ins.op_str}")


if __name__ == "__main__":
    main()
