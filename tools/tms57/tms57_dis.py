#!/usr/bin/env python3
"""TMS57002 disassembler and program statistics for the replay logs.

    tms57_dis.py <tms57.log> [--snap N] [--list]

Takes PMEM, ST0 and ST1 from snapshot N (default: the second Z block, the
first one after a download) of a tools/tms57/tms57_trace.lua log and prints
the mnemonic counts, the operand modes in use and the spacing between each
RDE/WRE and the next external access or SRBD. --list prints the program
(game-derived: print it, never commit it).

Instruction fields follow the TMS57002 User's Guide 4.2 (pp.4-4, 4-5):
bits 23:18 primary (cat 1, 0x3F = cat 3), 17:11 secondary (cat 2) or the
cat 3 opcode, bit 10 D (memory X is CMEM when 1), bit 9 E (memory Y post
increment), bit 8 F (memory X direct), 7:0 G (direct address, or bit 7 = X
post increment). Mnemonic names come from MAME's tmsinstr.lst (reference
only, rank 5).
"""
import os
import re
import sys
from collections import Counter
from pathlib import Path

# MAME 0.288 src/devices/cpu/tms57002/tmsinstr.lst (docs/mame_sources.md),
# from a local MAME source tree: MAME_SRC=<tree> or the default below
LST = Path(os.environ.get("MAME_SRC", "mame-src-0288")) / "src/devices/cpu/tms57002/tmsinstr.lst"


def load_lst():
    tab = {}
    cur = None
    for line in LST.read_text().splitlines():
        if not line.strip():
            cur = None
            continue
        if line[0] not in " \t":
            t = line.split()
            cur = (t[1], int(t[2], 16))
            tab[cur] = [t[0], None]
        elif cur and tab[cur][1] is None:
            tab[cur][1] = line.strip()
    return tab


TAB = load_lst()


def operands(w):
    """Return (c_operand, d_operand) strings for word w (guide Fig. 4-2)."""
    x_is_c = bool(w & 0x400)
    if w & 0x100:
        x = "%s(%d)" % ("C" if x_is_c else "D", w & 0xff)
    else:
        x = ("C*" if x_is_c else "D*") + ("+" if w & 0x80 else "")
    y = ("D*" if x_is_c else "C*") + ("+" if w & 0x200 else "")
    return (x, y) if x_is_c else (y, x)


def dis(w):
    c, d = operands(w)

    def fill(t):
        return t.replace("%c", c).replace("%d", d).replace("%i", "%02x" % (w & 0xff))
    if (w & 0xfc0000) == 0xfc0000:
        k = ("3", (w >> 11) & 0x7f)
        e = TAB.get(k)
        return [fill(e[1]) if e else "?cat3 %02x" % k[1]], [k]
    out, keys = [], []
    p = w >> 18
    if p:
        e = TAB.get(("1", p))
        out.append(fill(e[1]) if e else "?cat1 %02x" % p)
        keys.append(("1", p))
    s = (w >> 11) & 0x7f
    if s:
        e = TAB.get(("2a", s)) or TAB.get(("2b", s))
        cat = "2a" if ("2a", s) in TAB else "2b"
        out.append(fill(e[1]) if e else "?cat2 %02x" % s)
        keys.append((cat, s))
    return out or ["nop"], keys


def snapshots(path):
    snaps, cur = [], None
    for line in open(path):
        if line.startswith("Z "):
            t = line.split()
            cur = {"tag": t[1], "t": float(t[2]), "xba": int(t[3], 16), "pc": int(t[4], 16), "v": {}, "a": {}}
        elif cur is not None:
            if line.startswith("ZV "):
                _, n, v = line.split()
                cur["v"][n] = int(v, 16)
            elif line.startswith("ZA "):
                t = line.split()
                cur["a"][t[1]] = [int(x, 16) for x in t[2:]]
            elif line.startswith("ZP "):
                cur["pmem"] = [int(x, 16) for x in line.split()[1:]]
            elif line.startswith("ZE"):
                snaps.append(cur)
                cur = None
    return snaps


def main():
    args = sys.argv[1:]
    path = args[0]
    n = int(args[args.index("--snap") + 1]) if "--snap" in args else 1
    snaps = list_snaps = snapshots(path)
    s = snaps[n]
    pm = s["pmem"]
    print("snapshot %d: %s t=%.6f st0=%06x st1=%06x" % (n, s["tag"], s["t"], s["v"]["st0"], s["v"]["st1"]))
    end = next(i for i, w in enumerate(pm) if (w & 0xfc0000) == 0xfc0000 and ((w >> 11) & 0x7f) == 0x08)
    print("first IDLE at %d" % end)
    cnt, modes = Counter(), Counter()
    xm = []
    for pc in range(end + 1):
        w = pm[pc]
        txt, keys = dis(w)
        for k, tx in zip(keys, txt):
            cnt["%s(%s,%02x)" % (TAB[k][0] if k in TAB else "?", k[0], k[1])] += 1
        if (w & 0xfc0000) != 0xfc0000:
            modes["X=%s %s E=%d" % ("C" if w & 0x400 else "D", "dir" if w & 0x100 else ("ind+" if w & 0x80 else "ind"), (w >> 9) & 1)] += 1
        names = [TAB[k][0] if k in TAB else "?" for k in keys]
        if "rde" in names or "wre" in names or "srbd" in names:
            xm.append((pc, "/".join(names)))
        if "--list" in args:
            print("%3d %06x  %s" % (pc, w, " ; ".join(txt)))
    print("mnemonic (category, opcode): count")
    for k, v in sorted(cnt.items()):
        print("  %-22s %d" % (k, v))
    print("operand modes:", dict(modes))
    # spacing: each rde/wre to the next rde/wre/srbd
    gaps = Counter()
    for i, (pc, nm) in enumerate(xm):
        if "rde" in nm or "wre" in nm:
            for pc2, nm2 in xm[i + 1:]:
                gaps["%s->%s" % ("rde" if "rde" in nm else "wre", nm2)] = min(gaps.get("%s->%s" % ("rde" if "rde" in nm else "wre", nm2), 999), pc2 - pc)
                break
    print("minimum distance from an external access to the next rde/wre/srbd:", dict(gaps))


if __name__ == "__main__":
    main()
