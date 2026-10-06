#!/usr/bin/env python3
"""Disassemble a range of a little-endian MIPS I RAM dump (capstone).
  tools/mame/mips_dis.py <ram.bin> <start hex> <end hex> [<base hex, default 0>]"""
import sys
import capstone
data = open(sys.argv[1], "rb").read()
start, end = int(sys.argv[2], 16), int(sys.argv[3], 16)
base = int(sys.argv[4], 16) if len(sys.argv) > 4 else 0
md = capstone.Cs(capstone.CS_ARCH_MIPS, capstone.CS_MODE_MIPS32 + capstone.CS_MODE_LITTLE_ENDIAN)
md.skipdata = True  # data words in the dump print as .byte instead of stopping
for i in md.disasm(data[start - base:end - base], start):
    print(f"{i.address:08X}: {int.from_bytes(i.bytes, 'little'):08x}  {i.mnemonic:8s}{i.op_str}")
