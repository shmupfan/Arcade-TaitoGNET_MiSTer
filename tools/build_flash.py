#!/usr/bin/env python3
"""Build the five G-NET flash images from a PC card image and the BIOS zip,
without running the first-boot copy (M0 region builder, R3).

What the BIOS does on first boot, as reconstructed from MAME 0.288 NVRAM
(docs/m0_findings.md 3a):
  - SYSTEM.INF on the card (FAT16) names the files: gameprog, zoomprog, wave.
  - wave0..2  = the wave files, 16-bit byte-swapped.
  - zoomprog  = the zoomprog file (absent on cards for boards without the
                Zoom sound board: left erased); if its extension is .SDH it is decoded
                (Huffman then LZSS) first; then byte-swapped.
  - firm (U30) = flash.u30 from coh3002t.zip (sub-BIOS), byte-swapped, with
                 an install header at 0x50000, SYSTEM.TIM at 0x54000 (VRAM
                 position patched) and the gameprog file at 0x60000.
  - CompactFlash cards (kollonc, otenamhf; --cf, or cf=True): the BIOS also
    installs its v2 sub-BIOS in U30 0x00000-0x4FFFF, taken from the main BIOS
    ROM f35-01_m27c800.bin: 0x2C000-0x2EFFF at 0x00000 and 0x30000-0x5FFFF at
    0x10000, zeros elsewhere in that range (the header 0x00-0x43 is the same
    as flash.u30's); install header bytes 1Fh-20h are 01 00, not FF FF.
    Byte-equal to MAME 0.288 post-copy NVRAM for both sets. Without it the
    stock sub-BIOS stops a CF game with SYSTEM ERROR on hardware.
"Byte-swapped" means each 16-bit word is stored with its bytes exchanged
relative to the file, which is how MAME's 16-bit flash NVRAM files hold
them.

  tools/build_flash.py <card.img> <coh3002t.zip> <outdir> [--cf] [--check <nvramdir>]
"""
import os
import struct
import sys
import zipfile

SECTOR = 512


def swap16(b):
    a = bytearray(b)
    a[0::2], a[1::2] = b[1::2], b[0::2]
    return bytes(a)


class Fat16:
    def __init__(self, img):
        self.img = img
        plba = struct.unpack('<I', img[0x1be + 8:0x1be + 12])[0]
        bs = plba * SECTOR
        bps, spc, rsv, nfats, nroot, _, _, spf = struct.unpack('<HBHBHHBH', img[bs + 11:bs + 24])
        self.fat = img[bs + rsv * bps:bs + rsv * bps + spf * bps]
        self.root = bs + (rsv + nfats * spf) * bps
        self.nroot = nroot
        self.data = self.root + nroot * 32
        self.clus = spc * bps

    def _chain(self, c):
        while 2 <= c < 0xfff8:
            yield c
            c = struct.unpack('<H', self.fat[c * 2:c * 2 + 2])[0]

    def read(self, name):
        """read a file from the root directory (case-insensitive 8.3 name)"""
        want = name.upper()
        raw = self.img[self.root:self.root + self.nroot * 32]
        for i in range(0, len(raw), 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xe5 or e[11] & 0x18:
                continue
            n = e[0:8].decode('latin-1').rstrip()
            x = e[8:11].decode('latin-1').rstrip()
            if (n + ('.' + x if x else '')).upper() == want:
                start, size = struct.unpack('<H', e[26:28])[0], struct.unpack('<I', e[28:32])[0]
                b = b''.join(self.img[self.data + (c - 2) * self.clus:self.data + (c - 1) * self.clus]
                             for c in self._chain(start))
                return b[:size]
        raise FileNotFoundError(name)


def sdh_decode(sdh):
    """SDH = 255-node Huffman tree (16-bit LE pairs, nodes 0x100..0x1fe, root
    0x100, values < 0x100 are bytes), 0xffffffff, u32 decoded length, MSB-first
    bit stream. The decoded stream is u32 output length then LZSS (flag bits
    LSB first, 1 = literal; reference = 12-bit ring offset low byte plus high
    nibble, 4-bit length + 3; 4096-byte ring starting at 4078, zero-filled)."""
    nodes = [struct.unpack('<HH', sdh[k:k + 4]) for k in range(0, 1020, 4)]
    assert sdh[1020:1024] == b'\xff' * 4, 'SDH marker'
    hlen = struct.unpack('<I', sdh[1024:1028])[0]
    out = bytearray()
    n = 0x100
    for byte in sdh[1028:]:
        for b in range(7, -1, -1):
            n = nodes[n - 0x100][(byte >> b) & 1]
            if n < 0x100:
                out.append(n)
                n = 0x100
                if len(out) == hlen:
                    break
        if len(out) == hlen:
            break
    olen = struct.unpack('<I', out[0:4])[0]
    src = out[4:]
    N, F = 4096, 18
    ring = bytearray(N)
    r = N - F
    res = bytearray()
    i = 0
    while len(res) < olen:
        flags = src[i]
        i += 1
        for b in range(8):
            if len(res) >= olen:
                break
            if (flags >> b) & 1:
                c = src[i]
                i += 1
                res.append(c)
                ring[r] = c
                r = (r + 1) % N
            else:
                b1, b2 = src[i], src[i + 1]
                i += 2
                off = b1 | ((b2 & 0xf0) << 4)
                for k in range((b2 & 0x0f) + 3):
                    c = ring[(off + k) % N]
                    res.append(c)
                    ring[r] = c
                    r = (r + 1) % N
    return bytes(res)


def parse_inf(text):
    """SYSTEM.INF: one key per line, fields separated by tabs or spaces. The
    title is the rest of the line in double quotes; psyvarrv's title has no
    closing quote, so quotes are stripped leniently."""
    inf = {'wave': []}
    for line in text.replace('\x1a', '').splitlines():
        parts = line.strip().split(None, 1)
        if not parts:
            continue
        k, rest = parts[0], (parts[1] if len(parts) > 1 else '')
        if k == 'title':
            inf[k] = [rest.strip().strip('"')]
        elif k == 'wave':
            inf['wave'].append(rest.split())
        else:
            inf[k] = rest.split()
    return inf


def build(card_path, zip_path, cf=False):
    fs = Fat16(open(card_path, 'rb').read())
    inf = parse_inf(fs.read('SYSTEM.INF').decode('latin-1'))
    out = {}
    for n, w in enumerate(inf['wave']):
        data = fs.read(w[0])
        out['wave%d' % n] = swap16(data.ljust(0x200000, b'\xff'))
    # games without the Zoom board (MAME init_nozoom: otenamih, zooo and the
    # rest) have no zoomprog line; U27 then stays erased (all FFh), so no
    # 'zoomprog' image is returned and callers leave the area at FFh
    if 'zoomprog' in inf:
        zname = inf['zoomprog'][0]
        z = fs.read(zname)
        if zname.upper().endswith('.SDH'):
            z = sdh_decode(z)
        out['zoomprog'] = swap16(z.ljust(0x80000, b'\xff'))

    firm = bytearray(swap16(zipfile.ZipFile(zip_path).read('flash.u30')))
    gname, gver = inf['gameprog'][0], inf['gameprog'][1]
    game = fs.read(gname)
    major, minor = (int(x) for x in gver.split('.'))
    title = inf['title'][0].upper().encode('latin-1')[:16].ljust(16, b'\x00')
    ext = gname.upper().split('.')[1].encode('latin-1')[:3]
    area = inf['area'][0].encode('latin-1')[:1]
    header = (struct.pack('<II', int(inf['lotno'][0], 10), len(game)) + title + ext + area +
              bytes([major, minor, (1 << len(inf['wave'])) - 1]))   # mask of installed wave flashes
    # file view (unswapped) of the firm chip, patched, then swapped back
    fv = bytearray(swap16(bytes(firm)))
    fv[0x50000:0x50000 + len(header)] = header
    fv[0x50000 + len(header):0x50000 + len(header) + 5] = b'\xff\xff\x00\x00\x00'
    tim = bytearray(fs.read('SYSTEM.TIM'))
    tim[12:16] = b'\x00\x03\xfe\x00'                # VRAM position fields the BIOS writes
    tim[56:60] = b'\x00\x03\x00\x00'                # (whole fields: otenamih and zooo differ otherwise)
    tim += bytes(-len(tim) % 0x100)                 # zero pad to a 256-byte page
    fv[0x54000:0x54000 + len(tim)] = tim
    game_padded = game + bytes(-len(game) % 0x10000)  # zero pad to the 64 KB erase block
    fv[0x60000:0x60000 + len(game_padded)] = game_padded
    if cf:
        bios = zipfile.ZipFile(zip_path).read('f35-01_m27c800.bin')
        fv[0x00000:0x50000] = bytes(0x50000)
        fv[0x00000:0x03000] = bios[0x2c000:0x2f000]
        fv[0x10000:0x40000] = bios[0x30000:0x60000]
        fv[0x50000 + len(header):0x50000 + len(header) + 2] = b'\x01\x00'
    out['firm'] = swap16(bytes(fv))
    return out, inf


def main():
    card, zp, outdir = sys.argv[1:4]
    rest = sys.argv[4:]
    cf = '--cf' in rest
    check = rest[rest.index('--check') + 1] if '--check' in rest else None
    imgs, inf = build(card, zp, cf)
    os.makedirs(outdir, exist_ok=True)
    bad = 0
    for name, data in imgs.items():
        open(os.path.join(outdir, name), 'wb').write(data)
        if check:
            ref = open(os.path.join(check, name), 'rb').read()
            diff = [i for i in range(0, len(ref), SECTOR) if data[i:i + SECTOR] != ref[i:i + SECTOR]]
            print(f'{name:9s} {len(data):8d} bytes  {"IDENTICAL" if not diff and len(data) == len(ref) else "DIFF sectors %d first %s" % (len(diff), [hex(d) for d in diff[:4]])}')
            bad += bool(diff) or len(data) != len(ref)
        else:
            print(f'{name:9s} {len(data):8d} bytes')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
