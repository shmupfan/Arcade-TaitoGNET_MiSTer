#!/usr/bin/env python3
"""Generate a directed MN10200 test program (docs/mn10200_design.md 7.1).

The program executes every one of the 159 instruction forms (all forms the
mn102_isa.py table decodes, except undefined opcodes) many times, with
random register fields and corner-biased operands, and random PSW flags
before each test instruction. It is my own code, no game code: it can be
committed, and its output image is not game data.

It runs in MAME by replacing the zoomprog flash file of a copy of a game's
NVRAM set: the MN10200 boots it in the first run after power-on (about
200,000 instructions before the main CPU resets it). The testbench compares
the core against that MAME trace instruction by instruction.

Memory use: RAM 0x400000-0x400fff test area (filled with a pseudo-random
pattern first), stack at 0x41f000. (abs16) forms use the unmapped area
0x1000-0x7fff (reads 0 in MAME and in the testbench) and the timer base
registers 0xfe10-0xfe19 (no side effects). Interrupts stay disabled (IE is
never set); no external device is touched.

  tools/mn102/mn102_testgen.py <out_zoomprog> [steps] [seed]

The output is in the MAME NVRAM layout (16-bit words byte-swapped).
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mn102_isa  # noqa: E402

BASE = 0x080000
START = 0x080100
REG_LO, REG_HI = 0x400000, 0x401000      # test area
STACK = 0x41F000
CORNERS = [0x000000, 0x000001, 0x00007F, 0x000080, 0x0000FF, 0x007FFF, 0x008000, 0x00FFFF,
           0x010000, 0x7FFFFF, 0x800000, 0xFFFFFF, 0xFF8000, 0x00FF00, 0xFFFF00, 0x000002]


def le(v, n):
    return bytes((v >> (8 * i)) & 0xFF for i in range(n))


class Gen:
    def __init__(self, seed):
        self.r = random.Random(seed)
        self.code = bytearray()
        self.forms = {}
        self.count = {}
        self._table()

    def _table(self):
        for pfx in [None, 0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF7]:
            for b in range(256):
                if pfx is None and b in (0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF7):
                    continue
                mem = {i: 0 for i in range(8)}
                if pfx is None:
                    mem[0] = b
                else:
                    mem[0], mem[1] = pfx, b
                i = mn102_isa.decode(mem, 0)
                if i is None:
                    continue
                key = f"{i.mnem} {i.form}".strip()
                self.forms.setdefault(key, []).append((pfx, b, i))

    # ---------------------------------------------------------------- helpers
    def pc(self):
        return BASE + len(self.code)

    def emit(self, *bs):
        for b in bs:
            if isinstance(b, (bytes, bytearray)):
                self.code += b
            else:
                self.code.append(b & 0xFF)

    def val(self):
        if self.r.random() < 0.4:
            return self.r.choice(CORNERS)
        return self.r.getrandbits(24)

    def mov_d(self, n, v):
        self.emit(0xF4, 0x70 | n, le(v, 3))

    def mov_a(self, n, v):
        self.emit(0xF4, 0x74 | n, le(v, 3))

    def set_psw(self, v):
        self.mov_d(0, v & 0xF7FF)          # never IE
        self.emit(0xF3, 0xD0 | (0 << 2))   # mov d0,psw

    def target(self, w):
        return self.r.randrange(REG_LO, REG_HI - 4)

    # ---------------------------------------------------------------- program
    def fill(self):
        # a0 = REG_LO, d0 = seed, d1 = words; loop: mov d0,(a0); add 2,a0;
        # d0 = d0 * 5 + 0x3039 (16 bit); add -1,d1; bne loop
        self.mov_a(0, REG_LO)
        self.mov_d(0, 0x1234)
        self.mov_d(1, (REG_HI - REG_LO) // 2)
        loop = self.pc()
        self.emit(0x00)                    # mov d0,(a0)
        self.emit(0xD0, 0x02)              # add 2,a0
        self.emit(0x82)                    # mov d0,d2
        self.emit(0x90)                    # add d0,d0
        self.emit(0x90)                    # add d0,d0
        self.emit(0x98)                    # add d2,d0
        self.emit(0xF7, 0x18, le(0x3039, 2))  # add 0x3039,d0
        self.emit(0xD5, 0xFF)              # add -1,d1
        disp = loop - (self.pc() + 2)
        self.emit(0xE9, disp & 0xFF)       # bne loop

    def step(self, key):
        cands = self.forms[key]
        if key == "jsr (An)":
            # jsr (a3) would push its return address through the target
            cands = [c for c in cands if (c[1] >> 2) & 3 != 3]
        pfx, b, insn = self.r.choice(cands)
        self.count[key] = self.count.get(key, 0) + 1
        d_, a_, i_ = b & 3, (b >> 2) & 3, (b >> 4) & 3
        m, f, mode = insn.mnem, insn.form, insn.mode
        # PSW flags, MDR, registers
        self.set_psw(self.r.getrandbits(16))
        if m == "divu" or self.r.random() < 0.2:
            self.mov_d(1, self.val())
            self.emit(0xF3, 0xC0 | (1 << 2))   # mov d1,mdr
        for n in range(4):
            self.mov_d(n, self.val())
        for n in range(3):
            self.mov_a(n, self.val())
        self.mov_a(3, STACK)
        if m == "divu" and self.r.random() < 0.5:
            # quotient fits: MDR < divisor
            dv = self.r.randrange(1, 0x10000)
            self.mov_d(a_, dv)
            self.mov_d(1 if a_ != 1 else 2, self.r.randrange(0, dv))
            self.emit(0xF3, 0xC0 | ((1 if a_ != 1 else 2) << 2))
            self.mov_d(d_, self.val())
        ops = b""
        n_ops = insn.size - (1 if pfx is None else 2)
        pre = []      # extra setup emitted just before the test instruction
        post = b""    # bytes after it (branch targets)
        if insn.kind in ("load", "store", "rmw"):
            an = self.r.randrange(REG_LO + 0x200, REG_HI - 0x200)
            pre.append(("a", a_, an))
            t = self.target(insn.width)
            if mode == "(d8,An)":
                ops = le(self.r.randrange(-128, 128), 1)
            elif mode == "(d16,An)":
                ops = le(t - an, 2)
            elif mode == "(d24,An)":
                ops = le(t - an, 3)
            elif mode == "(Di,An)":
                if i_ == d_ and insn.kind == "store":
                    pass
                pre.append(("d", i_, (t - an) & 0xFFFFFF))
            elif mode == "(abs24)":
                ops = le(t, 3)
            elif mode == "(abs16)":
                if self.r.random() < 0.2:
                    ops = le(0xFE10 + 2 * self.r.randrange(0, 4), 2)
                else:
                    ops = le(self.r.randrange(0x1000, 0x8000), 2)
            # register fields that are both base and Di / data keep the base
            if mode == "(Di,An)" and insn.kind != "store" and False:
                pass
        elif insn.kind == "branch":
            ops = le(2, 1)
            post = bytes([0xD4, 0x01])                      # add 1,d0 (skipped when taken)
        elif insn.kind == "jmp" and f == "label16":
            ops = le(2, 2)
            post = bytes([0xD4, 0x01])
        elif insn.kind == "jmp" and f == "label24":
            ops = le(2, 3)
            post = bytes([0xD4, 0x01])
        elif insn.kind == "jsr" and f in ("label16", "label24"):
            ops = le(2, 2 if f == "label16" else 3)
            post = bytes([0xEA, 0x03, 0xD5, 0x05, 0xFE])   # bra +3; L: add 5,d1; rts
        elif insn.kind == "jmp" and f == "(An)":
            pre.append(("jmpa", a_, None))
            post = bytes([0xD4, 0x01])
        elif insn.kind == "jsr" and f == "(An)":
            pre.append(("jsra", a_, None))
            post = bytes([0xEA, 0x03, 0xD5, 0x05, 0xFE])
        elif insn.kind == "rti":
            pre.append(("rti", None, None))
        elif insn.kind == "ret":
            # jsr to a subroutine whose last instruction is the tested rts
            pass
        else:
            ops = bytes(self.r.getrandbits(8) for _ in range(n_ops))
            if f == "Dn,PSW":
                pre.append(("d", a_, self.val() & 0xF7FF))
            if f == "imm16,PSW" and m == "or":
                ops = le(self.r.getrandbits(16) & 0xF7FF, 2)
        assert len(ops) == n_ops or insn.kind in ("rti", "ret") or f == "(An)", (key, len(ops), n_ops)
        # the A3 stack must stay valid for jsr/rts/rti
        for kind, reg, v in pre:
            if kind == "a":
                self.mov_a(reg, v)
            elif kind == "d":
                self.mov_d(reg, v)
        instr = (bytes([b]) if pfx is None else bytes([pfx, b])) + ops
        if insn.kind == "ret":
            # jsr label16 +2 ; bra +1 ; rts (tested)
            self.emit(0xFD, le(2, 2), 0xEA, 0x01, 0xFE)
            return
        if insn.kind == "rti":
            psw = self.r.getrandbits(16) & 0xF7FF
            ret = self.pc() + 5 + 2 + 5 + 2 + 1
            self.mov_d(0, psw)
            self.emit(0x40 | (3 << 2) | 0, 0x00)   # mov d0,(0,a3)
            self.mov_a(0, ret)
            self.emit(0x50 | (3 << 2) | 0, 0x02)   # mov a0,(2,a3)
            assert self.pc() + 1 == ret
            self.emit(0xEB)
            return
        for kind, reg, v in pre:
            if kind in ("jmpa", "jsra"):
                tgt = self.pc() + 5 + len(instr) + 2
                self.mov_a(reg, tgt)
        here = self.pc()
        chk = mn102_isa.decode({i: x for i, x in enumerate(instr + bytes(8))}, 0)
        assert chk is not None and f"{chk.mnem} {chk.form}".strip() == key, (key, instr.hex())
        self.emit(instr, post)
        del here

    def program(self, steps):
        self.emit(0xF4, 0xE0, le(START - (BASE + 5), 3))   # jmp START
        while self.pc() < BASE + 8:
            self.emit(0xF6)
        self.emit(0xEA, 0xFE)                               # 0x080008: interrupts never expected
        while self.pc() < START:
            self.emit(0xF6)
        self.fill()
        keys = sorted(self.forms)
        for s in range(steps):
            if s % len(keys) == 0:
                self.r.shuffle(keys)
            self.step(keys[s % len(keys)])
        self.emit(0xEA, 0xFE)                               # done: bra .
        return self.code


def main():
    out = sys.argv[1]
    steps = int(sys.argv[2]) if len(sys.argv) > 2 else 6000
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    g = Gen(seed)
    code = g.program(steps)
    assert len(code) <= 0x80000, len(code)
    img = bytearray(code) + bytearray([0xFF]) * (0x80000 - len(code))
    img[0::2], img[1::2] = img[1::2], img[0::2]      # MAME NVRAM layout
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    open(out, "wb").write(img)
    print(f"{len(g.forms)} forms, {steps} steps, {len(code)} bytes, "
          f"min {min(g.count.values())} max {max(g.count.values())} per form")


if __name__ == "__main__":
    main()
