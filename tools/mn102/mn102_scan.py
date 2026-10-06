#!/usr/bin/env python3
"""Static scan of a Taito Zoom MN10200 program image (flash U27 / zoomprog).

Recursive-descent disassembly from the reset vector (0x080000) and the
interrupt vector (0x080008), plus code pointers found as MOV imm24,An / Dn
operands inside the program window. Reports instruction-form usage,
addressing modes, internal I/O register accesses (0xFC00-0xFFFF) with the
values written where a simple in-block constant tracker can see them, and
external bus targets. Prints statistics only: it never writes the image or a
listing of it (the program is copyrighted); use --listing DIR to write a
private listing outside the repository.

Usage: mn102_scan.py zoomprog [zoomprog ...] [--listing DIR] [--json OUT]
The MAME NVRAM file stores the 16-bit flash with each word byte-swapped;
the scanner detects that from the reset vector (F4 E0 = jmp label24).
"""
import argparse
import collections
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mn102_isa import decode  # noqa: E402

BASE = 0x080000


class Mem:
    def __init__(self, data):
        self.d = data

    def __getitem__(self, a):
        o = a - BASE
        if 0 <= o < len(self.d):
            return self.d[o]
        raise IndexError(a)


def load(path):
    d = bytearray(open(path, "rb").read())
    if d[0] == 0xE0 and d[1] == 0xF4:
        d[0::2], d[1::2] = d[1::2], d[0::2]
    assert d[0] == 0xF4 and d[1] == 0xE0, "reset vector is not jmp label24"
    return bytes(d)


def region(a):
    if 0xFC00 <= a <= 0xFFFF:
        return "io"
    if a < 0x10000:
        return "low64k"
    if 0x080000 <= a <= 0x0FFFFF:
        return "prog"
    if 0x400000 <= a <= 0x41FFFF:
        return "ram"
    if 0x800000 <= a <= 0x8007FF:
        return "zsg2"
    if a == 0xC00000:
        return "tms57002"
    if 0xE00000 <= a <= 0xE000FF:
        return "mailbox"
    return "other"


def scan(path, listing_dir=None):
    data = load(path)
    mem = Mem(data)
    end = BASE + len(data.rstrip(b"\xff"))
    seen = {}
    work = [(BASE, "reset"), (BASE + 8, "irq")]
    entry_kind = {}
    ptr_seeds = set()
    indirect = []
    bad = []
    while work:
        pc, why = work.pop()
        if pc in seen or not (BASE <= pc < end):
            continue
        entry_kind.setdefault(pc, why)
        while BASE <= pc < end and pc not in seen:
            ins = decode(mem, pc)
            if ins is None:
                bad.append((pc, why))
                break
            seen[pc] = ins
            if ins.mnem == "mov" and ins.form in ("imm24,An", "imm24,Dn") and BASE <= ins.imm < end:
                ptr_seeds.add(ins.imm)  # reported only (data pointers mostly)
            if ins.target is not None:
                work.append((ins.target, "call" if ins.kind == "jsr" else "branch"))
            if ins.kind in ("jmp", "jsr") and ins.mode == "(An)":
                indirect.append(pc)
            if ins.kind in ("ret", "rti") or (ins.kind in ("jmp",) ) or (ins.kind == "branch" and not ins.cond):
                break
            pc += ins.size
    n_direct = len(seen)
    # second pass: jump tables behind indirect jumps / calls. For each
    # indirect site take the program-window constants loaded in the 32
    # instructions before it and probe them as tables of 24-bit code
    # pointers (stride 4 or 6, pointer at offset 0 or 2); keep the longest
    # run of entries that land in decodable code.
    tables = {}
    done_sites = set()
    while True:
        new_sites = [p for p in indirect if p not in done_sites]
        if not new_sites:
            break
        for site in new_sites:
            done_sites.add(site)
            back = [q for q in sorted(seen) if site - 96 <= q < site][-32:]
            cands = set()
            for q in back:
                i = seen[q]
                for v in (i.imm, i.abs_addr):
                    if v is not None and BASE <= v < end:
                        cands.add(v)
            best = None
            for c in sorted(cands):
                for stride in (4, 6):
                    for off in (0, 2):
                        ents = []
                        k = 0
                        while k < 64:
                            ea = c + k * stride + off
                            if ea + 3 > end:
                                break
                            t = data[ea - BASE] | data[ea - BASE + 1] << 8 | data[ea - BASE + 2] << 16
                            if not (BASE <= t < end) or decode(mem, t) is None:
                                break
                            ents.append(t)
                            k += 1
                        if len(ents) >= 4 and (best is None or len(ents) > len(best[3])):
                            best = (c, stride, off, ents)
                if best:
                    tables[(site, c)] = best
                    for t in best[3]:
                        work.append((t, "table"))
                best = None
        while work:
            pc, why = work.pop()
            if pc in seen or not (BASE <= pc < end):
                continue
            entry_kind.setdefault(pc, why)
            while BASE <= pc < end and pc not in seen:
                ins = decode(mem, pc)
                if ins is None:
                    bad.append((pc, why))
                    break
                seen[pc] = ins
                if ins.target is not None:
                    work.append((ins.target, "call" if ins.kind == "jsr" else "branch"))
                if ins.kind in ("jmp", "jsr") and ins.mode == "(An)":
                    indirect.append(pc)
                if ins.kind in ("ret", "rti", "jmp") or (ins.kind == "branch" and not ins.cond):
                    break
                pc += ins.size
    ptr_seeds = {p for p in ptr_seeds if p not in seen}
    return data, end, seen, n_direct, entry_kind, indirect, bad, ptr_seeds, tables


def const_track(seen):
    """Walk each straight-line run in address order and track register
    constants (reset at every branch target and after calls). Returns I/O
    accesses as (pc, R/W, addr, width, value or None, via)."""
    targets = set(i.target for i in seen.values() if i.target is not None)
    out = []
    regs = {}
    prev_end = None
    for pc in sorted(seen):
        ins = seen[pc]
        if pc != prev_end or pc in targets:
            regs = {}
        prev_end = pc + ins.size
        t = ins.text
        # register constants
        mn, form = ins.mnem, ins.form
        ops = t.split(" ", 1)[1] if " " in t else ""
        dst = ops.split(",")[-1] if ops else ""
        if mn == "mov" and form in ("imm16,An", "imm24,An", "imm24,Dn", "imm16,Dn", "imm8,Dn"):
            v = ins.imm
            if form == "imm16,Dn" or form == "imm8,Dn":
                v &= 0xFFFFFF
            regs[dst] = v & 0xFFFFFF
        elif mn == "mov" and form in ("Dn,Dm", "An,Am", "Dm,An", "An,Dm"):
            s = ops.split(",")[0]
            if s in regs:
                regs[dst] = regs[s]
            else:
                regs.pop(dst, None)
        elif mn in ("add",) and form in ("imm8,An", "imm16,An", "imm8,Dn", "imm16,Dn", "imm24,An", "imm24,Dn") and dst in regs:
            regs[dst] = (regs[dst] + ins.imm) & 0xFFFFFF
        elif ins.kind == "load" or mn in ("add", "sub", "addc", "subc", "and", "or", "xor", "not", "rol", "ror",
                                          "asr", "lsr", "mul", "mulu", "divu", "extx", "extxu", "extxb", "extxbu",
                                          "addnf"):
            if ins.kind == "load" or form not in ("Dn,Dm",) or True:
                if dst and dst[0] in "ad":
                    regs.pop(dst, None)
        if ins.kind == "jsr":
            regs = {}
        # memory access address
        if ins.kind in ("load", "store", "rmw"):
            addr = None
            via = ins.mode
            if ins.abs_addr is not None:
                addr = ins.abs_addr
            elif ins.mode in ("(An)", "(d8,An)", "(d16,An)", "(d24,An)"):
                import re
                m = re.search(r"\(([-0-9a-fx]+,)?a(\d)\)", t)
                an = "a" + m.group(2)
                disp = 0
                if m.group(1):
                    disp = int(m.group(1)[:-1], 0)
                if an in regs:
                    addr = (regs[an] + disp) & 0xFFFFFF
            val = None
            if ins.kind == "store":
                src = ops.split(",")[0]
                val = regs.get(src)
            if addr is not None:
                out.append((pc, "W" if ins.kind == "store" else ("RMW" if ins.kind == "rmw" else "R"), addr, ins.width, val, via))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("images", nargs="+")
    ap.add_argument("--listing")
    ap.add_argument("--json")
    a = ap.parse_args()
    allres = {}
    for path in a.images:
        data, end, seen, n_direct, entry_kind, indirect, bad, ptr_seeds, tables = scan(path)
        name = os.path.basename(os.path.dirname(path)) + "/" + os.path.basename(path)
        forms = collections.Counter((i.mnem, i.form) for i in seen.values())
        modes = collections.Counter(i.mode for i in seen.values() if i.kind in ("load", "store", "rmw"))
        io = const_track(seen)
        code_bytes = sum(i.size for i in seen.values())
        res = {
            "image": path, "used_bytes": end - BASE, "insns": len(seen), "insns_direct": n_direct,
            "code_bytes": code_bytes, "indirect": len(indirect), "bad_paths": len(bad),
            "ptr_seeds": len(ptr_seeds),
            "forms": {f"{m} {f}".strip(): c for (m, f), c in sorted(forms.items())},
            "modes": dict(modes),
            "io": [(hex(pc), d, hex(ad), w, (hex(v) if v is not None else None), via) for pc, d, ad, w, v, via in io],
        }
        allres[name] = res
        if a.listing:
            os.makedirs(a.listing, exist_ok=True)
            with open(os.path.join(a.listing, name.replace("/", "_") + ".lst"), "w") as f:
                tg = set(i.target for i in seen.values() if i.target is not None)
                prev = None
                for pc in sorted(seen):
                    i = seen[pc]
                    if prev is not None and pc != prev:
                        f.write("\n")
                    lab = f"{entry_kind.get(pc, ''):6s}" if pc in entry_kind else ("L     " if pc in tg else "      ")
                    raw = " ".join(f"{data[pc - BASE + k]:02x}" for k in range(i.size))
                    f.write(f"{lab}{pc:06x}: {raw:15s} {i.text:32s} ; {i.cyc}{'/' + str(i.cyc_nt) if i.cond else ''}\n")
                    prev = pc + i.size
                f.write("\nBAD " + " ".join(f"{p:06x}({w})" for p, w in bad) + "\n")
                f.write("INDIRECT " + " ".join(f"{p:06x}" for p in indirect) + "\n")
                for (st, _), (c, stride, off, ents) in sorted(tables.items()):
                    f.write(f"TABLE site {st:06x} base {c:06x} stride {stride} off {off} n {len(ents)}: " + " ".join(f"{t:06x}" for t in ents) + "\n")
                f.write("UNUSED_PTR_CONSTS " + " ".join(f"{p:06x}" for p in sorted(ptr_seeds)) + "\n")
        print(f"{name}: used {res['used_bytes']} B, {res['insns']} insns ({n_direct} from vectors), "
              f"{code_bytes} code B, {len(indirect)} indirect jumps/calls, {len(bad)} undecodable paths, "
              f"{len(tables)} tables, {len(ptr_seeds)} unused program-window constants, {len(forms)} distinct forms")
    if a.json:
        json.dump(allres, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
