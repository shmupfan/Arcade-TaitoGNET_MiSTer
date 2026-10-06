#!/usr/bin/env python3
"""Inputs for the full-system simulation (game-derived: they stay under
sim/fullsys/work/, which is gitignored). Same layout as the zn2-layer
system bench (sim/zn2/system/prep.py).

  prep.py <coh3002t.zip> <outdir> [<card dir> <set>]

outdir/bios.bin   m534002c-60.ic353 (512 KB)
outdir/u30.bin    flash.u30 (2 MB)
outdir/keys.hex   tt10.ic652 then tt16.u17, one hex byte per line
outdir/<set>_meta.hex  with a card (tools/extract_card.sh output): 1024
                  bytes, IDNT at 000h, CIS at 200h, KEY at 300h
"""
import os, sys, zipfile


def main(zpath, out, carddir=None, setname=None):
    os.makedirs(out, exist_ok=True)
    z = zipfile.ZipFile(zpath)
    open(f'{out}/bios.bin', 'wb').write(z.read('m534002c-60.ic353'))
    open(f'{out}/u30.bin', 'wb').write(z.read('flash.u30'))
    keys = z.read('tt10.ic652') + z.read('tt16.u17')
    open(f'{out}/keys.hex', 'w').write(''.join(f'{b:02x}\n' for b in keys))
    if carddir:
        meta = bytearray(1024)
        idnt = open(f'{carddir}/{setname}.idnt', 'rb').read()
        cis = open(f'{carddir}/{setname}.cis', 'rb').read()
        key = open(f'{carddir}/{setname}.key', 'rb').read()
        assert len(idnt) == 512 and len(cis) <= 256 and len(key) == 5, (len(idnt), len(cis), len(key))
        meta[0:512] = idnt
        meta[0x200:0x200 + len(cis)] = cis
        meta[0x300:0x305] = key
        open(f'{out}/{setname}_meta.hex', 'w').write(''.join(f'{b:02x}\n' for b in meta))


if __name__ == '__main__':
    if len(sys.argv) not in (3, 5):
        sys.exit(__doc__)
    main(*sys.argv[1:])
