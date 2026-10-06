#!/usr/bin/env python3
"""CAT702 reference model and trace checker (from MAME 0.288 cat702.cpp and
psx sio.cpp bit order), for the ZN-2 layer RTL (docs/zn2_layer_design.md).

  cat702_ref.py check <sec.log> <coh3002t.zip>
      Replays every SIO0 byte the BIOS and game send to each CAT702 in an
      oracle sec.log (tools/mame/oracle.lua) through this model and compares
      the byte the SIO0 receives with the one MAME logged.
  cat702_ref.py vectors <sec.log> <coh3002t.zip> <outdir>
      Writes cat702_<n>.vec for the RTL testbench: one line per select
      session and byte, "S" for a select edge, "B <tx> <rx>" per byte, plus
      key_<n>.hex (8 bytes). The output is derived from the BIOS (game data):
      keep it under sim/ (gitignored).

Bit order per MAME (sio.cpp sio_tick, cat702.cpp write_clock): for each bit,
SCK falls (at bit 0 of a byte the state goes through the fixed initial sbox;
the output is state bit n), TXD is driven, SCK rises (if TXD is 0 the state
goes through sbox n; the bit counter advances) and the SIO samples RXD.
RXD is the AND of both CAT702 outputs and the znmcu output.
"""
import sys
import zipfile

INITIAL_SBOX = [0xFF, 0xFE, 0xFC, 0xF8, 0xF0, 0xE0, 0xC0, 0x7F]
KEYS = {0: "tt10.ic652", 1: "tt16.u17"}   # cat702_1 (ZN-2 board), cat702_2 (FC PCB)


def coef_table(key):
    """c[n][bit] for bit counter n = 0..7, built forward as the RTL does."""
    c = [list(key)]
    for n in range(1, 8):
        prev = c[-1]
        cur = [0] * 8
        for b in range(8):
            r = prev[(b - 1) & 7]
            r = ((r << 1) & 0xFF) | (((r >> 7) ^ (r >> 6)) & 1)
            cur[b] = r
        cur[7] ^= cur[0]
        c.append(cur)
    return c


def apply(state, sbox):
    r = 0
    for i in range(8):
        if (state >> i) & 1:
            r ^= sbox[i]
    return r


class Cat702:
    def __init__(self, key):
        self.coef = coef_table(key)
        self.select = 1
        self.state = 0
        self.bit = 0
        self.out = 1

    def write_select(self, s):
        if self.select != s:
            if not s:
                self.state = 0xFC
                self.bit = 0
            else:
                self.out = 1
            self.select = s

    def byte(self, tx):
        """One SIO0 byte while selected; returns the 8 output bits as a byte."""
        rx = 0
        for i in range(8):
            if self.bit == 0:
                self.state = apply(self.state, INITIAL_SBOX)
            self.out = (self.state >> self.bit) & 1
            if not ((tx >> i) & 1):
                self.state = apply(self.state, self.coef[self.bit])
            self.bit = (self.bit + 1) & 7
            rx |= self.out << i
        return rx


def parse(seclog):
    """Yield ('sel', value) and ('xfer', tx, rx) in log order."""
    sel = None
    pending = None
    for line in open(seclog):
        p = line.split()
        if len(p) < 6:
            continue
        rw, a, v, m = p[2], int(p[3], 16), int(p[4], 16), int(p[5], 16)
        if a == 0x1FA10300 and rw == "W":
            sel = v & 0xFF
            yield ("sel", sel)
        elif a == 0x1F801040 and m == 0xFF:
            if rw == "W":
                pending = v & 0xFF
            elif pending is not None:
                yield ("xfer", pending, v & 0xFF)
                pending = None


def keys_from_zip(path):
    z = zipfile.ZipFile(path)
    return {n: z.read(name) for n, name in KEYS.items()}


def run(seclog, zpath, vec_dir=None):
    keys = keys_from_zip(zpath)
    chips = [Cat702(keys[0]), Cat702(keys[1])]
    sel = 0x0C
    n_ok = [0, 0]
    n_bad = [0, 0]
    vec = None
    if vec_dir:
        vec = [open(f"{vec_dir}/cat702_{n}.vec", "w") for n in range(2)]
        for n in range(2):
            with open(f"{vec_dir}/key_{n}.hex", "w") as f:
                f.write("\n".join(f"{b:02x}" for b in keys[n]) + "\n")
    for ev in parse(seclog):
        if ev[0] == "sel":
            sel = ev[1]
            for n in range(2):
                s = (sel >> (2 + n)) & 1
                if vec and s != chips[n].select:
                    vec[n].write(f"S {s}\n")
                chips[n].write_select(s)
            continue
        tx, rx = ev[1], ev[2]
        sel_n = [n for n in range(2) if not chips[n].select]
        mcu = (sel & 0x8C) == 0x8C
        if mcu or len(sel_n) != 1:
            # znmcu traffic or no single CAT702 selected: still clock the
            # selected chips so their state follows MAME
            for n in sel_n:
                chips[n].byte(tx)
            continue
        n = sel_n[0]
        got = chips[n].byte(tx)
        if vec:
            vec[n].write(f"B {tx:02x} {rx:02x}\n")
        if got == rx:
            n_ok[n] += 1
        else:
            n_bad[n] += 1
            if n_bad[n] <= 5:
                print(f"cat702_{n}: tx {tx:02x} MAME rx {rx:02x} model {got:02x}")
    for n in range(2):
        print(f"cat702_{n} ({KEYS[n]}): bytes {n_ok[n] + n_bad[n]}, match {n_ok[n]}, mismatch {n_bad[n]}")
    if vec:
        for f in vec:
            f.close()
    return sum(n_bad) == 0


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "check":
        sys.exit(0 if run(sys.argv[2], sys.argv[3]) else 1)
    if len(sys.argv) >= 5 and sys.argv[1] == "vectors":
        sys.exit(0 if run(sys.argv[2], sys.argv[3], sys.argv[4]) else 1)
    print(__doc__)
    sys.exit(2)
