#!/usr/bin/env python3
"""Check PSX.sv's named port connections to VHDL entities against their port
lists (Verilator cannot read VHDL, so its lint of PSX.sv stops at them).

    check_ports.py <define> ...      e.g. GNET_ZN2 GNET_CPU50 GNET_ZOOM GNET_ZOOM_SDRAM

Preprocesses PSX.sv for the given macros (ifdef, ifndef, elsif, else, endif
and define only), then for every instance of psx_mister, zn2_ch3_arb, zoom_sdram_link
and cdc_handshake compares the .name( connections with the entity's ports:
unknown names are errors, and so are entity inputs without a default that
are left unconnected.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ENT = {"psx_mister": "rtl/psx_mister.vhd", "zn2_ch3_arb": "rtl/gnet/zn2_ch3_arb.vhd",
       "zoom_sdram_link": "rtl/gnet/zoom_sdram_link.vhd", "cdc_handshake": "rtl/gnet/cdc/cdc_handshake.vhd"}


def pre(text, defs):
    out = []
    stack = []          # per level: [taking this branch, some branch taken]
    for ln in text.split("\n"):
        m = re.match(r"\s*`(ifdef|ifndef|elsif|else|endif)\b\s*(\w*)", ln)
        if m:
            k, n = m.groups()
            if k in ("ifdef", "ifndef"):
                c = (n in defs) == (k == "ifdef")
                stack.append([c, c])
            elif k == "elsif":
                c = (not stack[-1][1]) and (n in defs)
                stack[-1] = [c, stack[-1][1] or c]
            elif k == "else":
                stack[-1] = [not stack[-1][1], True]
            else:
                stack.pop()
            out.append("")
            continue
        act = all(s[0] for s in stack)
        md = re.match(r"\s*`define\s+(\w+)", ln)
        if act and md:
            defs.add(md.group(1))
        out.append(ln if act else "")
    return "\n".join(out)


def ports(path):
    t = open(os.path.join(ROOT, path)).read()
    t = re.sub(r"--[^\n]*", "", t)
    m = re.search(r"\bport\s*\((.*?)\);\s*end\s+entity", t, re.S | re.I)
    res = {}
    for decl in m.group(1).split(";"):
        mm = re.match(r"\s*([\w\s,]+?)\s*:\s*(in|out|inout|buffer)\b(.*)", decl, re.S | re.I)
        if not mm:
            continue
        for n in mm.group(1).split(","):
            res[n.strip().lower()] = (mm.group(2).lower(), ":=" in mm.group(3))
    return res


def main():
    defs = set(sys.argv[1:])
    src = pre(open(os.path.join(ROOT, "PSX.sv")).read(), defs)
    src = re.sub(r"//[^\n]*", "", src)
    errs = 0
    for mod, path in ENT.items():
        p = ports(path)
        for m in re.finditer(r"\b%s\b\s*(#\s*\(.*?\)\s*)?\w+\s*\((.*?)\);" % mod, src, re.S):
            conn = set(c.lower() for c in re.findall(r"\.(\w+)\s*\(", m.group(2)))
            for b in sorted(conn - set(p)):
                print(f"{mod}: PSX.sv connects unknown port {b}")
                errs += 1
            for b in sorted(n for n, (d, dflt) in p.items() if d == "in" and not dflt and n not in conn):
                print(f"{mod}: input {b} without a default left open")
                errs += 1
            print(f"{mod}: {len(conn)} connections checked")
    print(f"macros {' '.join(sorted(defs))}: errors {errs}")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
