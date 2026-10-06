#!/usr/bin/env python3
"""Generate the MN10200 RTL decode ROMs from the form table in mn102_isa.py.

The ISA table (manual pp.145-151 with the corrections of
docs/mn10200_design.md 1.1 and 1.2) is the single source of truth: this
script decodes every {page, key byte} with mn102_isa.decode() and maps the
resulting (mnemonic, operand form) to an RTL control word.

Outputs (rtl/zoom/, committed, derived from the manual table only):
  mn10200_form.hex  2048 x 8 bit: {page[2:0], key[7:0]} -> form id
  mn10200_ctl.hex    256 x 40 bit: form id -> control word

Page: 0 = first byte; 1..7 = second byte after F0, F1, F2, F3, F4, F5, F7.
Control word layout (must match rtl/zoom/mn10200_pkg.sv):
  [3:0]   kind   0 ALU 1 LD 2 ST 3 BSET 4 BCLR 5 MUL 6 MULU 7 DIVU 8 BCC
                 9 JMP (pc-relative) 10 JSR (pc-relative) 11 JMP (An)
                 12 JSR (An) 13 RTS 14 RTI 15 ILLEGAL
  [6:4]   ea     0 (An) 1 (d8,An) 2 (d16,An) 3 (d24,An) 4 (Di,An) 5 (abs16) 6 (abs24)
  [8:7]   mw     memory width in bytes (1, 2, 3)
  [9]     msx    load sign-extends (byte and word loads)
  [10]    dsta   destination / store-data register (field 1:0) is An
  [11]    srca   source register (field 3:2) is An
  [13:12] bsel   ALU B operand: 0 register (3:2), 1 immediate, 2 MDR, 3 PSW
  [16:14] imm    0 none 1 s8 2 z8 3 s16 4 z16 5 imm24 6 constant 0xffff
  [20:17] alu    0 ADD 1 SUB 2 ADDC 3 SUBC 4 AND 5 OR 6 XOR 7 PASSB 8 ROL
                 9 ROR 10 ASR 11 LSR 12 EXTX 13 EXTXU 14 EXTXB 15 EXTXBU
  [23:21] flg    0 none 1 arith 2 arith, ZF sticky (ADDC/SUBC) 3 logic 4 shift
  [26:24] wb     0 none 1 register (1:0) 2 MDR 3 PSW 4 MDR = sign of B
  [27]    apsw   ALU A operand is PSW (AND/OR imm16,PSW)
  [31:28] cond   0 lt 1 gt 2 ge 3 le 4 cs 5 hi 6 cc 7 ls 8 eq 9 ne 10 always
                 11 vc 12 vs 13 nc 14 ns
  [32]    condx  condition on the 24-bit flags (Bccx)
  [36:33] cyc    machine cycles (branches: not-taken count; taken adds 1)
  [39:37] len    instruction length in bytes

  tools/mn102/mn102_rom.py [outdir]   (default rtl/zoom)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mn102_isa  # noqa: E402

PAGES = [None, 0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF7]
K = dict(ALU=0, LD=1, ST=2, BSET=3, BCLR=4, MUL=5, MULU=6, DIVU=7, BCC=8, JMP=9, JSR=10,
         JMPA=11, JSRA=12, RTS=13, RTI=14, ILL=15)
EA = {"(An)": 0, "(d8,An)": 1, "(d16,An)": 2, "(d24,An)": 3, "(Di,An)": 4, "(abs16)": 5, "(abs24)": 6}
IMM = dict(none=0, s8=1, z8=2, s16=3, z16=4, i24=5, ffff=6)
ALU = dict(ADD=0, SUB=1, ADDC=2, SUBC=3, AND=4, OR=5, XOR=6, PASSB=7, ROL=8, ROR=9, ASR=10, LSR=11,
           EXTX=12, EXTXU=13, EXTXB=14, EXTXBU=15)
FLG = dict(none=0, arith=1, sticky=2, logic=3, shift=4)
WB = dict(none=0, reg=1, mdr=2, psw=3, mdrext=4)
BSEL = dict(reg=0, imm=1, mdr=2, psw=3)
CONDS = ["lt", "gt", "ge", "le", "cs", "hi", "cc", "ls", "eq", "ne"]


def word(kind, ea=0, mw=0, msx=0, dsta=0, srca=0, bsel="reg", imm="none", alu="PASSB", flg="none",
         wb="none", apsw=0, cond=0, condx=0, cyc=1, ln=1):
    v = K[kind] | ea << 4 | mw << 7 | msx << 9 | dsta << 10 | srca << 11 | BSEL[bsel] << 12
    v |= IMM[imm] << 14 | ALU[alu] << 17 | FLG[flg] << 21 | WB[wb] << 24 | apsw << 27
    v |= cond << 28 | condx << 32 | cyc << 33 | ln << 37
    assert cyc < 16 and ln < 8
    return v


def mem_form(insn):
    """load / store forms: (kind, ea, width, sign-extend, data register is An)"""
    f = insn.form
    reg_first = f.startswith(("Dm,", "Dn,", "Am,", "An,"))
    kind = "ST" if insn.kind == "store" else "LD"
    assert reg_first == (kind == "ST"), insn
    data_reg = f.split(",")[0] if kind == "ST" else f.split(",")[-1]
    dsta = 1 if data_reg[0] == "A" else 0
    mw = insn.width
    msx = 1 if (kind == "LD" and insn.mnem in ("mov", "movb") and dsta == 0 and mw in (1, 2)) else 0
    return dict(kind=kind, ea=EA[insn.mode], mw=mw, msx=msx, dsta=dsta)


def ctl_of(insn, page):
    """map a decoded instruction to (control word, description)"""
    if insn is None:
        ln = [1, 2, 2, 2, 2, 5, 3, 4][page]
        cyc = [1, 2, 2, 2, 2, 3, 2, 2][page]
        return word("ILL", cyc=cyc, ln=ln), "illegal"
    m, f, c, ln = insn.mnem, insn.form, insn.cyc, insn.size
    kw = dict(cyc=c, ln=ln)
    if insn.kind in ("load", "store"):
        return word(**mem_form(insn), **kw), f"{m} {f}"
    if insn.kind == "rmw":
        return word("BSET" if m == "bset" else "BCLR", ea=0, mw=1, **kw), f"{m} {f}"
    if insn.kind == "branch":
        imm = "s8"
        base = m[1:]
        condx = 0
        if m == "bra":
            cond = 10
        elif m in ("bvc", "bvs", "bnc", "bns", "bvcx", "bvsx", "bncx", "bnsx"):
            cond = {"vc": 11, "vs": 12, "nc": 13, "ns": 14}[m[1:3]]
            condx = 1 if m.endswith("x") else 0
        else:
            if base.endswith("x"):
                condx, base = 1, base[:-1]
            cond = CONDS.index(base)
        # the RTL adds 1 cycle when taken; BRA is always taken (MAME do_branch:
        # 1 for the opcode + 1 taken = the table's 2)
        base_cyc = insn.cyc_nt if insn.cond else insn.cyc - 1
        return word("BCC", imm=imm, cond=cond, condx=condx, cyc=base_cyc, ln=ln), f"{m}"
    if insn.kind in ("jmp", "jsr"):
        kind = "JMP" if insn.kind == "jmp" else "JSR"
        if f == "(An)":
            return word(kind + "A", **kw), f"{m} (An)"
        return word(kind, imm={"label16": "s16", "label24": "i24"}[f], **kw), f"{m} {f}"
    if insn.kind == "ret":
        return word("RTS", **kw), "rts"
    if insn.kind == "rti":
        return word("RTI", **kw), "rti"
    if insn.kind == "muldiv":
        return word({"mul": "MUL", "mulu": "MULU", "divu": "DIVU"}[m], **kw), f"{m} {f}"
    if m == "nop":
        return word("ALU", **kw), "nop"
    # register / immediate ALU forms
    a = dict(kind="ALU", **kw)
    ops = f.split(",")
    if f == "Dn" and m in ("extx", "extxu", "extxb", "extxbu"):
        a.update(alu=m.upper(), wb="reg")
    elif f == "Dn" and m in ("rol", "ror", "asr", "lsr"):
        a.update(alu=m.upper(), wb="reg", flg="shift")
    elif f == "Dn" and m == "not":
        a.update(alu="XOR", bsel="imm", imm="ffff", wb="reg", flg="logic")
    elif f == "Dn" and m == "ext":
        a.update(wb="mdrext")
    elif f == "Dn,MDR":
        a.update(wb="mdr")
    elif f == "MDR,Dn":
        a.update(bsel="mdr", wb="reg")
    elif f == "Dn,PSW":
        a.update(wb="psw")
    elif f == "PSW,Dn":
        a.update(bsel="psw", wb="reg")
    elif f == "imm16,PSW":
        a.update(apsw=1, bsel="imm", imm="z16", alu=m.upper(), wb="psw")
    else:
        src, dst = ops
        a["dsta"] = 1 if dst[0] == "A" else 0
        if src.startswith("imm"):
            a["bsel"] = "imm"
            width = src[3:]
            if width == "24":
                a["imm"] = "i24"
            elif m in ("and", "or", "xor", "btst"):
                a["imm"] = "z" + width
            elif m == "cmp" and dst == "An" and width == "16":
                a["imm"] = "z16"   # MAME: cmp imm16,An zero-extends (read_arg16)
            elif m == "mov" and dst == "An" and width == "16":
                a["imm"] = "z16"   # mov imm16,An zero-extends
            else:
                a["imm"] = "s" + width
        else:
            a["srca"] = 1 if src[0] == "A" else 0
        if m == "mov":
            a.update(alu="PASSB", wb="reg")
        elif m in ("add", "sub"):
            a.update(alu=m.upper(), wb="reg", flg="arith")
        elif m == "addnf":
            a.update(alu="ADD", wb="reg")
        elif m == "cmp":
            a.update(alu="SUB", flg="arith")
        elif m in ("addc", "subc"):
            a.update(alu=m.upper(), wb="reg", flg="sticky")
        elif m in ("and", "or", "xor"):
            a.update(alu=m.upper(), wb="reg", flg="logic")
        elif m == "btst":
            a.update(alu="AND", flg="logic")
        else:
            raise ValueError(f"unmapped {m} {f}")
    return word(**a), f"{m} {f}"


def build():
    form_rom = [0] * 2048
    ctl_ids = {}
    ctl_list = []
    names = {}
    for page, pfx in enumerate(PAGES):
        for b in range(256):
            mem = {i: 0 for i in range(8)}
            if pfx is None:
                mem[0] = b
            else:
                mem[0], mem[1] = pfx, b
            insn = mn102_isa.decode(mem, 0)
            if pfx is None and b in (0xF0, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF7):
                ln = {0xF0: 2, 0xF1: 2, 0xF2: 2, 0xF3: 2, 0xF4: 5, 0xF5: 3, 0xF7: 4}[b]
                w, name = word("ILL", ln=ln), "prefix"
            else:
                w, name = ctl_of(insn, page)
            if w not in ctl_ids:
                ctl_ids[w] = len(ctl_list)
                ctl_list.append(w)
                names[w] = name
            form_rom[page * 256 + b] = ctl_ids[w]
    assert len(ctl_list) <= 256, len(ctl_list)
    return form_rom, ctl_list, names


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "..", "rtl", "zoom")
    form_rom, ctl_list, names = build()
    with open(os.path.join(out, "mn10200_form.hex"), "w") as f:
        f.write("".join(f"{v:02x}\n" for v in form_rom))
    with open(os.path.join(out, "mn10200_ctl.hex"), "w") as f:
        f.write("".join(f"{v:010x}\n" for v in ctl_list + [word("ILL")] * (256 - len(ctl_list))))
    print(f"{len(ctl_list)} distinct control words")


if __name__ == "__main__":
    main()
