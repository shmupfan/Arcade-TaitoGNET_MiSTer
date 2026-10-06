#!/usr/bin/env python3
"""Directed and random tests for the ZSG-2 RTL against tools/zsg2/zsg2_model.py
(MAME 61c7940 transcribed). Writes a synthetic wave set (no game data) and
an event stream for sim/zsg2/tb.cpp with the model's outputs and reads.

  zsg2_directed.py <outdir> [fuzz_samples]
  -> <outdir>/flash/wave0..2, <outdir>/directed.ev

Scenarios (docs/zsg2_rtl.md 4.5): key-on at start address 0 and other
cur_pos wrap cases, wave addresses past 6 MB (playback and readback), gain
bit 7 and bits 6:5, the 16-bit output clamp, a Zoom reset with fetches
outstanding, then a random register/key/read fuzz.
"""
import os
import random
import sys
from zsg2_model import Zsg2

NBLK = 0x180000


def load_flash(d):
    blocks = []
    for c in range(3):
        b = open(os.path.join(d, 'wave%d' % c), 'rb').read()
        for w in range(0x80000):
            i = 4 * w
            lo = b[i] << 8 | b[i + 1]
            hi = b[i + 2] << 8 | b[i + 3]
            blocks.append(lo | hi << 16)
    return blocks


def write_flash(d, blocks):
    os.makedirs(d, exist_ok=True)
    for c in range(3):
        out = bytearray()
        for blk in blocks[c * 0x80000:(c + 1) * 0x80000]:
            lo, hi = blk & 0xffff, blk >> 16
            out += bytes((lo >> 8, lo & 0xff, hi >> 8, hi & 0xff))
        open(os.path.join(d, 'wave%d' % c), 'wb').write(out)


def make_blocks(rng):
    blocks = [rng.getrandbits(32) for _ in range(NBLK)]
    # loud regions for the clamp test: page 0x10 all +max, page 0x11 all -max
    # (7-bit 0x3f / 0x40 in all four samples, shift 0)
    pos = (0x3f << 8) | (0x3f << 16) | (0x3f << 24) | 0xf | (0 << 4)
    pos &= ~((1 << 15) | (1 << 23) | (1 << 31))
    pos |= (1 << 23) | (1 << 31)          # sample 3 = 0b0111111: bits 15=0, 23=1, 31=1, low 1111
    neg = (0x40 << 8) | (0x40 << 16) | (0x40 << 24) | (1 << 15)   # sample 3 = 0b1000000
    for w in range(0x100000, 0x110000):
        blocks[w] = pos
    for w in range(0x110000, 0x120000):
        blocks[w] = neg
    blocks[0x170000] = 0                   # a zero block
    return blocks


class Gen:
    def __init__(self, path, blocks):
        self.f = open(path, 'w')
        self.m = Zsg2(blocks, 3)
        self.k = 0
        self.n = {'W': 0, 'R': 0, 'T': 0, 'X': 0, 'nz': 0, 'clip': 0}
        self.reset()

    def reset(self):
        self.m.reset()
        self.f.write('X\n'); self.n['X'] += 1

    def w(self, a, d):
        self.m.write(a, d & 0xffff)
        self.f.write('W %03x %04x\n' % (a, d & 0xffff)); self.n['W'] += 1

    def r(self, a):
        self.f.write('R %03x %04x\n' % (a, self.m.read(a))); self.n['R'] += 1

    def t(self, n=1):
        for _ in range(n):
            self.k += 1
            o = self.m.render()
            if any(o): self.n['nz'] += 1
            if any(x in (32767, -32768) for x in o): self.n['clip'] += 1
            self.f.write('T %d\nO %d %d %d %d %d\n' % (self.k, self.k, o[0], o[1], o[2], o[3])); self.n['T'] += 1

    def voice(self, ch, start, end, loop, page, step=0x7fff, gains=(0x1f, 0x1f, 0x1f, 0x1f),
              cut_i=0x8000, cut_t=0x9000, cramp=0x17, vt=0xc000, vramp=0x17):
        b = ch * 16
        self.w(b + 0, (start & 0xff) << 8)
        self.w(b + 1, page << 8 | start >> 8)
        self.w(b + 2, 0)
        self.w(b + 3, 0x0400)
        self.w(b + 4, step)
        self.w(b + 5, gains[3] << 8 | (loop & 0xff))
        self.w(b + 6, end)
        self.w(b + 7, gains[2] << 8 | loop >> 8)
        self.w(b + 8, cut_i)
        self.w(b + 9, 0)
        self.w(b + 0xa, 0)
        self.w(b + 0xb, 0)
        self.w(b + 0xc, cut_t)
        self.w(b + 0xd, gains[1] << 8 | cramp)
        self.w(b + 0xe, vt)
        self.w(b + 0xf, gains[0] << 8 | vramp)

    def keyon(self, chs):
        for g in range(3):
            m = sum(1 << (c - 16 * g) for c in chs if 16 * g <= c < 16 * g + 16)
            if m: self.w(0x300 + g, m)

    def keyoff(self, chs):
        for g in range(3):
            m = sum(1 << (c - 16 * g) for c in chs if 16 * g <= c < 16 * g + 16)
            if m: self.w(0x304 + g, m)

    def poll(self, chs):
        for c in chs:
            self.r(c * 16 + 3); self.r(c * 16 + 9); self.r(c * 16 + 0xb)


def scenarios(g, rng, fuzz):
    # A. key-on at start 0 and cur_pos wrap cases
    g.voice(0, 0x0000, 0x0020, 0x0008, 0x00, step=0x5fff)      # start 0: cur_pos = 0xffffffff
    g.voice(1, 0x0000, 0x0000, 0x0000, 0x02)                    # start 0, end 0: stops at once
    g.voice(2, 0x0000, 0x0001, 0x0000, 0x03, step=0xffff)       # loop + 1 >= end: stops at first loop
    g.voice(3, 0xfff0, 0xffff, 0xfff8, 0x04, step=0xffff)       # positions near 0xffff
    g.voice(4, 0xfffe, 0xffff, 0xffff, 0x05, step=0xffff)       # loop 0xffff: stop
    g.voice(5, 0x0040, 0x0010, 0x0002, 0x06, step=0xffff)       # start past end: plays the loop
    g.voice(6, 0x0000, 0x0100, 0x0000, 0x07, step=0x0000)       # step 1/65536
    g.keyon(range(7))
    for _ in range(40):
        g.t(5); g.poll(range(7))
    g.keyoff(range(7))
    g.t(3)
    # B. wave addresses past 6 MB
    g.voice(8, 0xff00, 0xffff, 0xff80, 0x17, step=0xffff)       # last page in range
    g.voice(9, 0x0000, 0x0080, 0x0010, 0x18, step=0xffff)       # first page out of range
    g.voice(10, 0x1234, 0x2000, 0x1300, 0xff, step=0x9fff)      # page 0xff
    g.keyon([8, 9, 10])
    g.t(200)
    g.w(8 * 16 + 1, 0x18 << 8 | 0xff)                            # move channel 8 out of range while playing
    g.w(9 * 16 + 1, 0x17 << 8 | 0x00)                            # and channel 9 into range
    g.t(200)
    g.w(10 * 16 + 6, 0x1240)                                     # end moved under the playing position
    g.t(50)
    for a in (0x17ffff, 0x180000, 0x17fffe, 0x3fffffff, 0, 0x100000, 0x200000, 0x1fffff, 0x2abcd):
        g.w(0x31c, (a & 0x3fff) << 2 | rng.randrange(4))
        g.w(0x31d, a >> 14)
        g.r(0x314); g.r(0x31e); g.r(0x31f)
    g.keyoff([8, 9, 10])
    g.t(2)
    # C. gain bit 7 (inversion) and bits 6:5
    g.voice(11, 0x0100, 0x0400, 0x0200, 0x01, gains=(0x9f, 0x80 | 0x15, 0x7f, 0xe3))
    g.voice(12, 0x0100, 0x0400, 0x0200, 0x01, gains=(0x1f, 0x15, 0x9f, 0x63))
    g.keyon([11, 12])
    g.t(300)
    g.w(11 * 16 + 0xf, 0x00 << 8 | 0x17)
    g.w(12 * 16 + 5, 0x9f00 | 0x00)
    g.t(100)
    g.keyoff([11, 12])
    # D. output clamp: loud blocks, full volume, gain 31
    for i, c in enumerate(range(16, 24)):
        page = 0x10 if i < 4 else 0x11
        g.voice(c, 0x0000, 0x8000, 0x0100, page, step=0x3fff, cut_i=0xffff, cut_t=0xffff, vt=0xffff, vramp=0xb7)
    g.keyon(range(16, 24))
    for c in range(16, 24):
        g.w(c * 16 + 0xf, 0x1f00 | 0xb7)                         # leave the forced 0x400 ramp
    g.t(400)
    g.keyoff(range(16, 20))                                       # only the negative ones left
    g.t(200)
    g.keyoff(range(20, 24))
    g.t(2)
    # E. Zoom reset with fetches outstanding (run with a long latency too)
    for c in range(24, 32):
        g.voice(c, 0x2000 + 0x100 * c, 0x3000 + 0x100 * c, 0x2100 + 0x100 * c, c - 20, step=0xffff)
    g.keyon(range(24, 32))
    g.reset()                                                     # fetches for 24-31 still in flight
    for c in range(24, 32):
        g.voice(c, 0x0400 + 0x40 * c, 0x0800 + 0x40 * c, 0x0500 + 0x40 * c, 0x16 - (c - 24), step=0xbfff)
    g.keyon(range(24, 32))
    g.t(150)
    g.reset()                                                     # reset while playing
    g.t(3)
    g.voice(30, 0x0010, 0x0400, 0x0100, 0x09, step=0xffff)
    g.keyon([30])
    g.t(150); g.poll([30])
    g.reset()
    # F. random fuzz
    regs_written = 0
    while g.k < fuzz:
        op = rng.random()
        if op < 0.45:
            ch = rng.randrange(48); reg = rng.randrange(16)
            if reg in (0, 1, 5, 6, 7):
                d = rng.getrandbits(16)
                if reg == 1: d = (rng.choice([rng.randrange(0x18), 0x18, 0xff, rng.randrange(256)]) << 8) | rng.randrange(256)
            elif reg == 4:
                d = rng.choice([0xffff, 0x7fff, rng.getrandbits(16), 0])
            elif reg in (9, 0xc) and rng.random() < 0.3:
                d = 0
            else:
                d = rng.getrandbits(16)
            g.w(ch * 16 + reg, d); regs_written += 1
        elif op < 0.52:
            g.w(0x300 + rng.randrange(3), 1 << rng.randrange(16) | (rng.getrandbits(16) if rng.random() < 0.1 else 0))
        elif op < 0.57:
            g.w(0x304 + rng.randrange(3), 1 << rng.randrange(16))
        elif op < 0.62:
            g.w(0x300 + rng.randrange(0x100), rng.getrandbits(16))   # any control register
        elif op < 0.75:
            g.r(rng.randrange(0x400))
        else:
            g.t(rng.randrange(1, 40))
        if rng.random() < 0.0005:
            g.reset()


def main():
    out = sys.argv[1]
    fuzz = int(sys.argv[2]) if len(sys.argv) > 2 else 60000
    rng = random.Random(20261005)
    blocks = make_blocks(rng)
    write_flash(os.path.join(out, 'flash'), blocks)
    g = Gen(os.path.join(out, 'directed.ev'), blocks)
    scenarios(g, rng, fuzz)
    g.f.close()
    print('directed:', g.n)


if __name__ == '__main__':
    main()
