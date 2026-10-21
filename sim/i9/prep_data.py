#!/usr/bin/env python3
"""Inputs for the issue #9 bench (sim/i9/tb_cj.sv), into sim/i9/work/
(gitignored: game-derived data, never commit).

  card_orig.bin   Psyvariar (psyvaria) card image as in the zip: chdman
                  extractraw of roms/psyvaria/psyvaria.chd
  card_gc2.bin    the same card after MAME's psyvaria_cold300 run (a credit
                  played, records written) and the INVERT ON settings save
                  (sim/oracle/i9_psyvaria_gc2, its diff CHD on the parent)
  writes1.bin     the ATA WRITE SECTORS MAME logged for that session, in
                  order (cold300 at 287 s, then the save at 21.8 s), each
                  record LBA (4 bytes LE) + 512 bytes; the data is the
                  sector's final content in card_gc2.bin, so writing them
                  all over card_orig.bin gives card_gc2.bin
  writes_off.bin  the INVERT OFF save: the same three sectors, sector 48629
                  byte 48 = 00h
  ee_gobyrc.bin   Go By RC EEPROM after calibration in MAME
                  (sim/oracle/i4_rc1, at28c16 bytes 0-2047)

  sim/i9/prep_data.py [checkout with roms/ and sim/oracle/]
  (default: the checkout this script is in)
"""
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAIN = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE.parents[1]
W = HERE / 'work'
W.mkdir(exist_ok=True)
CHD = MAIN / 'roms/psyvaria/psyvaria.chd'
ORACLE = MAIN / 'sim/oracle'


def ata_writes(log):
    regs, out = {}, []
    for line in open(log, errors='replace'):
        p = line.split()
        if len(p) < 8 or p[2] != 'W':
            continue
        name = p[-1]
        if name not in ('seccnt', 'secnum', 'cyllo', 'cylhi', 'drvhd', 'cmd'):
            continue
        data, mask = int(p[4], 16), int(p[5], 16)
        sh = (mask & -mask).bit_length() - 1
        v = (data >> sh) & 0xff
        if name != 'cmd':
            regs[name] = v
            continue
        if v in (0x30, 0x31):
            lba = regs.get('secnum', 0) | regs.get('cyllo', 0) << 8 | regs.get('cylhi', 0) << 16 | (regs.get('drvhd', 0) & 15) << 24
            n = regs.get('seccnt', 1) or 256
            out += list(range(lba, lba + n))
    return out


def extract(dst, args):
    if not dst.exists():
        subprocess.run(['chdman', 'extractraw', *args, '-o', str(dst), '-f'], check=True,
                       stdout=subprocess.DEVNULL)


extract(W / 'card_orig.bin', ['-i', str(CHD)])
extract(W / 'card_gc2.bin', ['-i', str(ORACLE / 'i9_psyvaria_gc2/diff/psyvaria.dif'), '-ip', str(CHD)])
orig = (W / 'card_orig.bin').read_bytes()
gc2 = (W / 'card_gc2.bin').read_bytes()
assert len(orig) == len(gc2) == 40960000

seq = ata_writes(ORACLE / 'psyvaria_cold300/ata.log') + ata_writes(ORACLE / 'i9_psyvaria_gc2/ata.log')
# every sector that differs must be in the write list
diff = [i // 512 for i in range(0, len(orig), 512) if orig[i:i + 512] != gc2[i:i + 512]]
assert set(diff) <= set(seq), (diff, seq)
with open(W / 'writes1.bin', 'wb') as f:
    for lba in seq:
        f.write(struct.pack('<I', lba) + gc2[lba * 512:lba * 512 + 512])
off = bytearray(gc2)
off[48629 * 512 + 48] = 0
assert gc2[48629 * 512 + 48] == 1
with open(W / 'writes_off.bin', 'wb') as f:
    for lba in (48553, 64, 48553, 48629, 64, 48553):
        f.write(struct.pack('<I', lba) + bytes(off[lba * 512:lba * 512 + 512]))
(W / 'card_off.bin').write_bytes(bytes(off))
ee = (ORACLE / 'i4_rc1/nvram/gobyrc/at28c16').read_bytes()[:2048]
(W / 'ee_gobyrc.bin').write_bytes(ee)
print('prep_data: %d writes (%d distinct sectors, %d hunks), %d sectors differ, gobyrc EEPROM %d non-FF bytes'
      % (len(seq), len(set(seq)), len({s // 8 for s in seq}), len(diff), sum(b != 0xff for b in ee)))
