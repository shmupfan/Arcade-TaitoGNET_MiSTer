#!/usr/bin/env python3
"""List (and optionally extract) the FAT16 files on a G-NET PC card image.

The card images (tools/extract_card.sh) carry an MBR with one FAT16
partition. Usage:
  tools/card_ls.py sim/cards/raycris.img            list root directory (recursive)
  tools/card_ls.py sim/cards/raycris.img --extract DIR   copy files out (gitignored location only)
"""
import os
import struct
import sys


def main():
    img = open(sys.argv[1], 'rb').read()
    out = sys.argv[3] if len(sys.argv) > 3 and sys.argv[2] == '--extract' else None
    ptype, plba = img[0x1be + 4], struct.unpack('<I', img[0x1be + 8:0x1be + 12])[0]
    bs = plba * 512
    bps, spc, rsv, nfats, nroot, _, _, spf = struct.unpack('<HBHBHHBH', img[bs + 11:bs + 24])
    fat0 = bs + rsv * bps
    root = fat0 + nfats * spf * bps
    data = root + nroot * 32
    clus = spc * bps
    fat = img[fat0:fat0 + spf * bps]
    print(f'partition type {ptype:#x} at LBA {plba}; {bps} B/sector, {spc} sectors/cluster, '
          f'root {nroot} entries, data area at byte {data:#x}')

    def chain(c):
        while 2 <= c < 0xfff8:
            yield c
            c = struct.unpack('<H', fat[c * 2:c * 2 + 2])[0]

    def read(c, size):
        b = b''.join(img[data + (x - 2) * clus:data + (x - 1) * clus] for x in chain(c))
        return b[:size] if size else b

    def walk(raw, path):
        for i in range(0, len(raw), 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xe5 or e[11] == 0x0f or e[11] & 0x08:
                continue
            name = e[0:8].decode('latin-1').rstrip()
            ext = e[8:11].decode('latin-1').rstrip()
            if name in ('.', '..'):
                continue
            full = path + name + ('.' + ext if ext else '')
            start, size = struct.unpack('<H', e[26:28])[0], struct.unpack('<I', e[28:32])[0]
            off = data + (start - 2) * clus if start >= 2 else 0
            contiguous = list(chain(start)) == list(range(start, start + len(list(chain(start)))))
            if e[11] & 0x10:
                print(f'{full + "/":40s} dir   cluster {start}')
                walk(read(start, 0), full + '/')
            else:
                print(f'{full:40s} {size:10,d} bytes  card offset {off:#09x}  {"contiguous" if contiguous else "fragmented"}')
                if out:
                    os.makedirs(out, exist_ok=True)
                    open(os.path.join(out, full.replace('/', '_')), 'wb').write(read(start, size))

    walk(img[root:root + nroot * 32], '')


if __name__ == '__main__':
    main()
