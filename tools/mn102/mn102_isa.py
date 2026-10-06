"""MN10200 (MN102L/MN102H) instruction decoder for static analysis.

Encodings, sizes and minimum cycle counts from the MN102L Series Instruction
Manual 12250-030E appendix "Instruction set" (pp.145-151), with the MOVB
Dm,(An) operand order corrected (manual erratum, see MAME mn10200.cpp and
Pokechu22/ghidra-mn102-lang): the byte is 10 + An<<2 + Dm. Cross-checked
against MAME 0.288 src/devices/cpu/mn10200/mn10200.cpp. Reads no ROM data.

decode(mem, pc) returns an Insn or None (illegal / undecodable).
"""
from dataclasses import dataclass, field

CC = ["lt", "gt", "ge", "le", "cs", "hi", "cc", "ls", "eq", "ne"]


@dataclass
class Insn:
    pc: int
    size: int
    cyc: int            # minimum cycles (branch: taken count)
    cyc_nt: int         # branch not taken (same as cyc otherwise)
    mnem: str           # e.g. "mov"
    form: str           # canonical operand form, e.g. "Dm,(d8,An)"
    text: str           # rendered instruction
    kind: str = "alu"   # alu, load, store, rmw, branch, jmp, jsr, ret, rti, misc
    width: int = 0      # memory access width in bytes (load/store/rmw)
    mode: str = ""      # addressing mode of the memory operand
    abs_addr: int = None  # absolute memory address (abs16 / abs24)
    target: int = None    # branch / jump / call target
    cond: bool = False    # conditional branch
    regs: dict = field(default_factory=dict)  # field values: An, Am, Dn, Dm, Di
    imm: int = None


def s8(v):
    return v - 0x100 if v & 0x80 else v


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def rd(mem, a, n):
    v = 0
    for i in range(n):
        v |= mem[(a + i)] << (8 * i)
    return v


def decode(mem, pc):
    """mem: bytes-like indexed by CPU address via mem[addr] (a dict-like or
    an object with __getitem__); pc: CPU address."""
    try:
        op = mem[pc]
    except (IndexError, KeyError):
        return None
    hi, lo = op >> 4, op & 0xF
    a_ = (op >> 2) & 3   # An field (bits 3:2)
    d_ = op & 3          # Dm / Am / Dn field (bits 1:0)

    def I(size, cyc, mnem, form, text, **kw):
        cyc_nt = kw.pop("cyc_nt", cyc)
        return Insn(pc, size, cyc, cyc_nt, mnem, form, text, **kw)

    if hi == 0x0:
        return I(1, 1, "mov", "Dm,(An)", f"mov d{d_},(a{a_})", kind="store", width=2, mode="(An)")
    if hi == 0x1:
        return I(1, 1, "movb", "Dm,(An)", f"movb d{d_},(a{a_})", kind="store", width=1, mode="(An)")
    if hi == 0x2:
        return I(1, 1, "mov", "(An),Dm", f"mov (a{a_}),d{d_}", kind="load", width=2, mode="(An)")
    if hi == 0x3:
        return I(1, 1, "movbu", "(An),Dm", f"movbu (a{a_}),d{d_}", kind="load", width=1, mode="(An)")
    if hi in (0x4, 0x5, 0x6, 0x7):
        d8 = s8(mem[pc + 1])
        if hi == 0x4:
            return I(2, 1, "mov", "Dm,(d8,An)", f"mov d{d_},({d8},a{a_})", kind="store", width=2, mode="(d8,An)")
        if hi == 0x5:
            return I(2, 2, "mov", "Am,(d8,An)", f"mov a{d_},({d8},a{a_})", kind="store", width=3, mode="(d8,An)")
        if hi == 0x6:
            return I(2, 1, "mov", "(d8,An),Dm", f"mov ({d8},a{a_}),d{d_}", kind="load", width=2, mode="(d8,An)")
        return I(2, 2, "mov", "(d8,An),Am", f"mov ({d8},a{a_}),a{d_}", kind="load", width=3, mode="(d8,An)")
    if hi == 0x8:
        if a_ == d_:
            v = s8(mem[pc + 1])
            return I(2, 1, "mov", "imm8,Dn", f"mov {v},d{d_}", imm=v, regs={"Dn": d_})
        return I(1, 1, "mov", "Dn,Dm", f"mov d{a_},d{d_}")
    if hi == 0x9:
        return I(1, 1, "add", "Dn,Dm", f"add d{a_},d{d_}")
    if hi == 0xA:
        return I(1, 1, "sub", "Dn,Dm", f"sub d{a_},d{d_}")
    if hi == 0xB:
        m = ["extx", "extxu", "extxb", "extxbu"][a_]
        return I(1, 1, m, "Dn", f"{m} d{d_}")
    if hi == 0xC:
        ab = rd(mem, pc + 1, 2)
        if a_ == 0:
            return I(3, 1, "mov", "Dn,(abs16)", f"mov d{d_},(0x{ab:04x})", kind="store", width=2, mode="(abs16)", abs_addr=ab)
        if a_ == 1:
            return I(3, 1, "movb", "Dn,(abs16)", f"movb d{d_},(0x{ab:04x})", kind="store", width=1, mode="(abs16)", abs_addr=ab)
        if a_ == 2:
            return I(3, 1, "mov", "(abs16),Dn", f"mov (0x{ab:04x}),d{d_}", kind="load", width=2, mode="(abs16)", abs_addr=ab)
        return I(3, 1, "movbu", "(abs16),Dn", f"movbu (0x{ab:04x}),d{d_}", kind="load", width=1, mode="(abs16)", abs_addr=ab)
    if hi == 0xD:
        if a_ == 3:
            v = rd(mem, pc + 1, 2)
            return I(3, 1, "mov", "imm16,An", f"mov 0x{v:04x},a{d_}", imm=v)
        v = s8(mem[pc + 1])
        m = ["add", "add", "cmp"][a_]
        r = "a" if a_ == 0 else "d"
        return I(2, 1, m, f"imm8,{r.upper()}n", f"{m} {v},{r}{d_}", imm=v)
    if hi == 0xE:
        if lo <= 0x9:
            t = (pc + 2 + s8(mem[pc + 1])) & 0xFFFFFF
            return I(2, 2, "b" + CC[lo], "label8", f"b{CC[lo]} 0x{t:06x}", kind="branch", target=t, cond=True, cyc_nt=1)
        if lo == 0xA:
            t = (pc + 2 + s8(mem[pc + 1])) & 0xFFFFFF
            return I(2, 2, "bra", "label8", f"bra 0x{t:06x}", kind="branch", target=t)
        if lo == 0xB:
            return I(1, 6, "rti", "", "rti", kind="rti")
        v = rd(mem, pc + 1, 2)
        return I(3, 1, "cmp", "imm16,An", f"cmp 0x{v:04x},a{d_}", imm=v)
    # 0xF_
    if lo == 0x6:
        return I(1, 1, "nop", "", "nop", kind="misc")
    if lo in (0x8, 0x9, 0xA, 0xB):
        v = s16(rd(mem, pc + 1, 2))
        return I(3, 1, "mov", "imm16,Dn", f"mov {v},d{d_}", imm=v)
    if lo == 0xC:
        t = (pc + 3 + s16(rd(mem, pc + 1, 2))) & 0xFFFFFF
        return I(3, 2, "jmp", "label16", f"jmp 0x{t:06x}", kind="jmp", target=t)
    if lo == 0xD:
        t = (pc + 3 + s16(rd(mem, pc + 1, 2))) & 0xFFFFFF
        return I(3, 4, "jsr", "label16", f"jsr 0x{t:06x}", kind="jsr", target=t)
    if lo == 0xE:
        return I(1, 5, "rts", "", "rts", kind="ret")
    if lo == 0xF:
        return None
    op2 = mem[pc + 1]
    h2, l2 = op2 >> 4, op2 & 0xF
    i_ = (op2 >> 4) & 3
    a2 = (op2 >> 2) & 3
    d2 = op2 & 3
    if lo == 0x0:
        if op2 & 0xF3 == 0x00:
            return I(2, 3, "jmp", "(An)", f"jmp (a{a2})", kind="jmp", mode="(An)")
        if op2 & 0xF3 == 0x01:
            return I(2, 5, "jsr", "(An)", f"jsr (a{a2})", kind="jsr", mode="(An)")
        if h2 == 0x2:
            return I(2, 5, "bset", "Dm,(An)", f"bset d{d2},(a{a2})", kind="rmw", width=1, mode="(An)")
        if h2 == 0x3:
            return I(2, 5, "bclr", "Dm,(An)", f"bclr d{d2},(a{a2})", kind="rmw", width=1, mode="(An)")
        if 0x4 <= h2 <= 0x7:
            return I(2, 2, "movb", "(Di,An),Dm", f"movb (d{i_},a{a2}),d{d2}", kind="load", width=1, mode="(Di,An)")
        if 0x8 <= h2 <= 0xB:
            return I(2, 2, "movbu", "(Di,An),Dm", f"movbu (d{i_},a{a2}),d{d2}", kind="load", width=1, mode="(Di,An)")
        if h2 >= 0xC:
            return I(2, 2, "movb", "Dm,(Di,An)", f"movb d{d2},(d{i_},a{a2})", kind="store", width=1, mode="(Di,An)")
        return None
    if lo == 0x1:
        g = op2 >> 6
        # F1:00 / F1:80 (24-bit (Di,An) forms) are not in the MN102L table
        # and were deleted from the MN102H table by its errata; the Zoom IRQ
        # dispatcher uses F1:00, so the MN1020012A has it. Cycles: MAME (3).
        if g == 0:
            return I(2, 3, "mov", "(Di,An),Am", f"mov (d{i_},a{a2}),a{d2}", kind="load", width=3, mode="(Di,An)")
        if g == 1:
            return I(2, 2, "mov", "(Di,An),Dm", f"mov (d{i_},a{a2}),d{d2}", kind="load", width=2, mode="(Di,An)")
        if g == 2:
            return I(2, 3, "mov", "Am,(Di,An)", f"mov a{d2},(d{i_},a{a2})", kind="store", width=3, mode="(Di,An)")
        return I(2, 2, "mov", "Dm,(Di,An)", f"mov d{d2},(d{i_},a{a2})", kind="store", width=2, mode="(Di,An)")
    if lo == 0x2:
        tbl = {0x0: ("add", "Dm,An", "d", "a"), 0x1: ("sub", "Dm,An", "d", "a"), 0x2: ("cmp", "Dm,An", "d", "a"),
               0x3: ("mov", "Dm,An", "d", "a"), 0x4: ("add", "An,Am", "a", "a"), 0x5: ("sub", "An,Am", "a", "a"),
               0x6: ("cmp", "An,Am", "a", "a"), 0x7: ("mov", "An,Am", "a", "a"), 0x8: ("addc", "Dn,Dm", "d", "d"),
               0x9: ("subc", "Dn,Dm", "d", "d"), 0xC: ("add", "An,Dm", "a", "d"), 0xD: ("sub", "An,Dm", "a", "d"),
               0xE: ("cmp", "An,Dm", "a", "d"), 0xF: ("mov", "An,Dm", "a", "d")}
        if h2 not in tbl:
            return None
        m, f, s, t = tbl[h2]
        return I(2, 2, m, f, f"{m} {s}{a2},{t}{d2}")
    if lo == 0x3:
        if h2 in (0x0, 0x1, 0x2, 0x9):
            m = {0: "and", 1: "or", 2: "xor", 9: "cmp"}[h2]
            return I(2, 2, m, "Dn,Dm", f"{m} d{a2},d{d2}")
        if h2 == 0x3:
            m = ["rol", "ror", "asr", "lsr"][a2]
            return I(2, 2, m, "Dn", f"{m} d{d2}")
        if h2 in (0x4, 0x5):
            m = "mul" if h2 == 4 else "mulu"
            return I(2, 12, m, "Dn,Dm", f"{m} d{a2},d{d2}", kind="muldiv")
        if h2 == 0x6:
            return I(2, 13, "divu", "Dn,Dm", f"divu d{a2},d{d2}", kind="muldiv")
        if h2 == 0xC and d2 == 0:
            return I(2, 2, "mov", "Dn,MDR", f"mov d{a2},mdr")
        if h2 == 0xC and d2 == 1:
            return I(2, 3, "ext", "Dn", f"ext d{a2}")
        if h2 == 0xD and d2 == 0:
            return I(2, 3, "mov", "Dn,PSW", f"mov d{a2},psw", kind="psw")
        if h2 == 0xE and a2 == 0:
            return I(2, 2, "mov", "MDR,Dn", f"mov mdr,d{d2}")
        if h2 == 0xE and a2 == 1:
            return I(2, 2, "not", "Dn", f"not d{d2}")
        if h2 == 0xF and a2 == 0:
            return I(2, 2, "mov", "PSW,Dn", f"mov psw,d{d2}")
        return None
    if lo == 0x4:
        v = rd(mem, pc + 2, 3)
        if h2 == 0x0:
            return I(5, 3, "mov", "Dm,(d24,An)", f"mov d{d2},(0x{v:06x},a{a2})", kind="store", width=2, mode="(d24,An)", imm=v)
        if h2 == 0x1:
            return I(5, 4, "mov", "Am,(d24,An)", f"mov a{d2},(0x{v:06x},a{a2})", kind="store", width=3, mode="(d24,An)", imm=v)
        if h2 == 0x2:
            return I(5, 3, "movb", "Dm,(d24,An)", f"movb d{d2},(0x{v:06x},a{a2})", kind="store", width=1, mode="(d24,An)", imm=v)
        if h2 == 0x3:
            return I(5, 4, "movx", "Dm,(d24,An)", f"movx d{d2},(0x{v:06x},a{a2})", kind="store", width=3, mode="(d24,An)", imm=v)
        if op2 & 0xFC == 0x40:
            return I(5, 3, "mov", "Dn,(abs24)", f"mov d{d2},(0x{v:06x})", kind="store", width=2, mode="(abs24)", abs_addr=v)
        if op2 & 0xFC == 0x44:
            return I(5, 3, "movb", "Dn,(abs24)", f"movb d{d2},(0x{v:06x})", kind="store", width=1, mode="(abs24)", abs_addr=v)
        if op2 & 0xFC == 0x50:
            return I(5, 4, "mov", "An,(abs24)", f"mov a{d2},(0x{v:06x})", kind="store", width=3, mode="(abs24)", abs_addr=v)
        if h2 == 0x6 or h2 == 0x7:
            m = {0x60: "add", 0x64: "add", 0x68: "sub", 0x6C: "sub", 0x70: "mov", 0x74: "mov", 0x78: "cmp", 0x7C: "cmp"}[op2 & 0xFC]
            r = "a" if op2 & 4 else "d"
            return I(5, 3, m, f"imm24,{r.upper()}n", f"{m} 0x{v:06x},{r}{d2}", imm=v)
        if h2 == 0x8:
            return I(5, 3, "mov", "(d24,An),Dm", f"mov (0x{v:06x},a{a2}),d{d2}", kind="load", width=2, mode="(d24,An)", imm=v)
        if h2 == 0x9:
            return I(5, 3, "movbu", "(d24,An),Dm", f"movbu (0x{v:06x},a{a2}),d{d2}", kind="load", width=1, mode="(d24,An)", imm=v)
        if h2 == 0xA:
            return I(5, 3, "movb", "(d24,An),Dm", f"movb (0x{v:06x},a{a2}),d{d2}", kind="load", width=1, mode="(d24,An)", imm=v)
        if h2 == 0xB:
            return I(5, 4, "movx", "(d24,An),Dm", f"movx (0x{v:06x},a{a2}),d{d2}", kind="load", width=3, mode="(d24,An)", imm=v)
        if op2 & 0xFC == 0xC0:
            return I(5, 3, "mov", "(abs24),Dn", f"mov (0x{v:06x}),d{d2}", kind="load", width=2, mode="(abs24)", abs_addr=v)
        if op2 & 0xFC == 0xC4:
            return I(5, 3, "movb", "(abs24),Dn", f"movb (0x{v:06x}),d{d2}", kind="load", width=1, mode="(abs24)", abs_addr=v)
        if op2 & 0xFC == 0xC8:
            return I(5, 3, "movbu", "(abs24),Dn", f"movbu (0x{v:06x}),d{d2}", kind="load", width=1, mode="(abs24)", abs_addr=v)
        if op2 & 0xFC == 0xD0:
            return I(5, 4, "mov", "(abs24),An", f"mov (0x{v:06x}),a{d2}", kind="load", width=3, mode="(abs24)", abs_addr=v)
        if op2 == 0xE0:
            t = (pc + 5 + v) & 0xFFFFFF
            return I(5, 4, "jmp", "label24", f"jmp 0x{t:06x}", kind="jmp", target=t)
        if op2 == 0xE1:
            t = (pc + 5 + v) & 0xFFFFFF
            return I(5, 5, "jsr", "label24", f"jsr 0x{t:06x}", kind="jsr", target=t)
        if h2 == 0xF:
            return I(5, 4, "mov", "(d24,An),Am", f"mov (0x{v:06x},a{a2}),a{d2}", kind="load", width=3, mode="(d24,An)", imm=v)
        return None
    if lo == 0x5:
        b = mem[pc + 2]
        if op2 & 0xF0 == 0x00:
            m = ["and", "btst", "or", "addnf"][a2]
            r = "a" if a2 == 3 else "d"
            v = s8(b) if a2 == 3 else b
            return I(3, 2, m, f"imm8,{r.upper()}n", f"{m} 0x{b:02x},{r}{d2}", imm=v)
        d8 = s8(b)
        if h2 == 0x1:
            return I(3, 2, "movb", "Dm,(d8,An)", f"movb d{d2},({d8},a{a2})", kind="store", width=1, mode="(d8,An)")
        if h2 == 0x2:
            return I(3, 2, "movb", "(d8,An),Dm", f"movb ({d8},a{a2}),d{d2}", kind="load", width=1, mode="(d8,An)")
        if h2 == 0x3:
            return I(3, 2, "movbu", "(d8,An),Dm", f"movbu ({d8},a{a2}),d{d2}", kind="load", width=1, mode="(d8,An)")
        if h2 == 0x5:
            return I(3, 3, "movx", "Dm,(d8,An)", f"movx d{d2},({d8},a{a2})", kind="store", width=3, mode="(d8,An)")
        if h2 == 0x7:
            return I(3, 3, "movx", "(d8,An),Dm", f"movx ({d8},a{a2}),d{d2}", kind="load", width=3, mode="(d8,An)")
        t = (pc + 3 + d8) & 0xFFFFFF
        if 0xE0 <= op2 <= 0xE9:
            m = "b" + CC[op2 - 0xE0] + "x"
        elif op2 in (0xEC, 0xED, 0xEE, 0xEF):
            m = {0xEC: "bvcx", 0xED: "bvsx", 0xEE: "bncx", 0xEF: "bnsx"}[op2]
        elif op2 in (0xFC, 0xFD, 0xFE, 0xFF):
            m = {0xFC: "bvc", 0xFD: "bvs", 0xFE: "bnc", 0xFF: "bns"}[op2]
        else:
            return None
        return I(3, 3, m, "label8", f"{m} 0x{t:06x}", kind="branch", target=t, cond=True, cyc_nt=2)
    if lo == 0x7:
        v = rd(mem, pc + 2, 2)
        sv = s16(v)
        g = op2 & 0xFC
        simple = {0x00: ("and", "imm16,Dn", 2), 0x04: ("btst", "imm16,Dn", 2), 0x08: ("add", "imm16,An", 2),
                  0x0C: ("sub", "imm16,An", 2), 0x18: ("add", "imm16,Dn", 2), 0x1C: ("sub", "imm16,Dn", 2),
                  0x40: ("or", "imm16,Dn", 2), 0x48: ("cmp", "imm16,Dn", 2), 0x4C: ("xor", "imm16,Dn", 2)}
        if g in simple:
            m, f, c = simple[g]
            r = "a" if "An" in f else "d"
            return I(4, c, m, f, f"{m} 0x{v:04x},{r}{d2}", imm=v)
        if op2 == 0x10:
            return I(4, 3, "and", "imm16,PSW", f"and 0x{v:04x},psw", kind="psw", imm=v)
        if op2 == 0x14:
            return I(4, 3, "or", "imm16,PSW", f"or 0x{v:04x},psw", kind="psw", imm=v)
        if g == 0x20:
            return I(4, 3, "mov", "An,(abs16)", f"mov a{d2},(0x{v:04x})", kind="store", width=3, mode="(abs16)", abs_addr=v)
        if g == 0x30:
            return I(4, 3, "mov", "(abs16),An", f"mov (0x{v:04x}),a{d2}", kind="load", width=3, mode="(abs16)", abs_addr=v)
        tbl = {0x5: ("movbu", "(d16,An),Dm", 2, "load", 1, "d"), 0x6: ("movx", "Dm,(d16,An)", 3, "store", 3, "d"),
               0x7: ("movx", "(d16,An),Dm", 3, "load", 3, "d"), 0x8: ("mov", "Dm,(d16,An)", 2, "store", 2, "d"),
               0x9: ("movb", "Dm,(d16,An)", 2, "store", 1, "d"), 0xA: ("mov", "Am,(d16,An)", 3, "store", 3, "a"),
               0xB: ("mov", "(d16,An),Am", 3, "load", 3, "a"), 0xC: ("mov", "(d16,An),Dm", 2, "load", 2, "d"),
               0xD: ("movb", "(d16,An),Dm", 2, "load", 1, "d")}
        if h2 in tbl:
            m, f, c, k, w, r = tbl[h2]
            if k == "store":
                t = f"{m} {r}{d2},({sv},a{a2})"
            else:
                t = f"{m} ({sv},a{a2}),{r}{d2}"
            return I(4, c, m, f, t, kind=k, width=w, mode="(d16,An)", imm=sv)
        return None
    return None
