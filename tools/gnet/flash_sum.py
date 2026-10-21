#!/usr/bin/env python3
"""Expected flash copier sum for the debug overlay's DR row in GNET_DDR3_LOAD
builds (docs/i12_ddr3_load.md 13): the 32-bit sum of the little-endian
32-bit words of the flash area as the MRA loads it (index 3), low 24 bits.

  tools/gnet/flash_sum.py gnet_raycris.zip            (the zip's <set>.flash)
  tools/gnet/flash_sum.py raycris.flash
  tools/gnet/flash_sum.py --first-boot coh3002t.zip   (flash.u30 + 8 MB of FFh)
"""
import struct
import sys
import zipfile


def data_of(arg, first_boot):
    if first_boot:
        u30 = zipfile.ZipFile(arg).read('flash.u30')
        return u30 + b'\xff' * 0x800000
    if arg.lower().endswith('.zip'):
        z = zipfile.ZipFile(arg)
        names = [n for n in z.namelist() if n.lower().endswith('.flash')]
        if len(names) != 1:
            sys.exit(f'{arg}: expected one .flash file, found {names}')
        return z.read(names[0])
    return open(arg, 'rb').read()


def main():
    first_boot = '--first-boot' in sys.argv
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if len(args) != 1:
        sys.exit(__doc__)
    d = data_of(args[0], first_boot)[:0xA00000]
    if len(d) % 4:
        d += b'\0' * (4 - len(d) % 4)   # the copier's last word holds what DDR3 had past the end
    s = sum(struct.unpack('<%dI' % (len(d) // 4), d)) & 0xFFFFFFFF
    print(f'{len(d):,} bytes, sum {s:08X}; DR row digits 3 to 8 should read {s & 0xFFFFFF:06X} '
          f'(a good load reads "DR 01{(s >> 16) & 0xFF:02X} {s & 0xFFFF:04X}": overflows 0, copier flags 1 = done, sums agree)')


if __name__ == '__main__':
    main()
