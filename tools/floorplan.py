#!/usr/bin/env python3
"""Floor plan of a fitted build: which block of the core sits where on the chip.

Copyright (C) 2026 Lee Foot
SPDX-License-Identifier: GPL-2.0-or-later

Inputs, both from one build folder (tools/pc_build.sh fetch):
  placement.tsv         tools/sta/placement_dump.tcl on the kept database
                        (location, WYSIWYG type, cell name per line)
  GNET_Z1FULLR.fit.rpt  "Fitter Resource Utilization by Entity" for the table
Output: a PNG. Each square is one LAB, M10K or DSP site (X, Y as in the chip
planner, Y = 0 at the bottom), coloured by the group owning most of its
cells; unused sites are dark grey. The table gives per group the
combinational ALUTs, dedicated registers, M10K and DSP blocks of the fit
report (each entity's own share, summed by group).

  tools/floorplan.py <build dir> [-o out.png] [--title TEXT]
"""
import argparse
import collections
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# (label, colour); order is the legend order
GROUPS = [
    ("GPU", (220, 20, 60)),
    ("GTE", (60, 90, 200)),
    ("R3000 CPU", (60, 170, 60)),
    ("SPU", (240, 200, 20)),
    ("MDEC", (150, 60, 190)),
    ("DMA, memory mux, timers", (140, 200, 40)),
    ("ZN-2 board (FC, I/O, CAT702)", (240, 130, 40)),
    ("Zoom: MN10200", (40, 170, 170)),
    ("Zoom: TMS57002", (100, 220, 240)),
    ("Zoom: ZSG-2", (160, 100, 50)),
    ("Zoom: bus, caches, CDC", (230, 70, 200)),
    ("DDR3 + SDRAM ports", (250, 160, 170)),
    ("Core video out", (120, 120, 255)),
    ("Hiscore, card journal", (200, 160, 255)),
    ("hps_io", (40, 110, 110)),
    ("emu other", (230, 70, 70)),
    ("HDMI scaler (ascal)", (255, 255, 255)),
    ("sys (framework)", (110, 110, 115)),
]
COLOUR = dict(GROUPS)

PSX_GLUE = {"idma", "imemorymux", "imemctrl", "itimer", "iirq", "isio", "iexp2",
            "isavestates", "ipsx_top"}
DDR = {"ddr3_arb", "flcopy", "gmux", "mirror", "zport", "sdram", "ch3_arb", "ch3_cdc"}
VIDEO = {"arcade_video", "screen_rotate", "rot_gamma", "crt_pos", "video_freak",
         "pause_dim", "sd_blank", "crop224", "sync_keeper"}


def group_of(path):
    """Group for a hierarchy given as instance names (emu|psx|ipsx_top|igpu|...)."""
    t = [re.sub(r"^.*:", "", p) for p in path]  # \gzn2c:izn2_board -> izn2_board
    s = set(t)
    if not t or t[0] not in ("emu",):
        return "HDMI scaler (ascal)" if t and t[0] == "ascal" else "sys (framework)"
    if "igpu" in s:
        return "GPU"
    if "igte" in s:
        return "GTE"
    if "icpu" in s or "icpu_split" in s:
        return "R3000 CPU"
    if "ispu" in s:
        return "SPU"
    if "imdec" in s:
        return "MDEC"
    if "izoom_board" in s or "izoom_cdc" in s:
        if "u_cpu" in s:
            return "Zoom: MN10200"
        if "u_tms" in s:
            return "Zoom: TMS57002"
        if "u_zsg2" in s:
            return "Zoom: ZSG-2"
        return "Zoom: bus, caches, CDC"
    if s & {"izn2_board", "izn2_cardmem", "izn2_cdc"}:
        return "ZN-2 board (FC, I/O, CAT702)"
    if "psx" in s:
        return "DMA, memory mux, timers"
    if len(t) > 1 and t[1] in DDR:
        return "DDR3 + SDRAM ports"
    if len(t) > 1 and t[1] in VIDEO:
        return "Core video out"
    if len(t) > 1 and t[1] in ("hiscore_save", "card_journal"):
        return "Hiscore, card journal"
    if len(t) > 1 and t[1] in ("hps_io", "hps_ext"):
        return "hps_io"
    return "emu other"


LOC = re.compile(r"^([A-Z0-9]+)_X(\d+)_Y(\d+)_N\d+$")


# hard blocks worth a marker: (site kind, label)
MARKS = {"HPSINTERFACEFPGA2SDRAM": "HPS DDR3 port (f2sdram)"}


def read_placement(path):
    """{(x, y): (site kind, Counter of groups)} for LAB, MLAB, M10K and DSP sites,
    plus [(x, y, label)] for the hard blocks in MARKS."""
    sites, marks = {}, []
    for line in open(path, encoding="latin-1"):
        loc, _wys, name = line.rstrip("\n").split("\t")
        m = LOC.match(loc)
        if not m:
            continue
        kind, x, y = m.group(1), int(m.group(2)), int(m.group(3))
        if kind in MARKS:
            marks.append((x, y, MARKS[kind]))
        if kind in ("LABCELL", "FF"):
            kind = "LAB"
        elif kind == "MLABCELL":
            kind = "MLAB"
        elif kind not in ("M10K", "DSP"):
            continue
        g = group_of(name.split("|")[:-1] or [""])
        k, c = sites.setdefault((x, y), (kind, collections.Counter()))
        if kind != "LAB" and k == "LAB":  # MLAB cells in a LAB-registered site
            sites[(x, y)] = (kind, c)
        c[g] += 1
    return sites, marks


def read_entity_table(path):
    """Per group: ALUTs, registers, M10K, DSP (each entity's own share)."""
    lines = open(path, encoding="latin-1").read().split("\n")
    i = next(k for k, ln in enumerate(lines) if ln.startswith("; Fitter Resource Utilization by Entity"))
    hdr = [c.strip() for c in lines[i + 2].split(";")]
    col = {h: k for k, h in enumerate(hdr)}
    rows = []
    for ln in lines[i + 4:]:
        if not ln.startswith(";"):
            break
        c = ln.split(";")
        full = c[col["Full Hierarchy Name"]].strip()
        inst = [p.split(":")[-1] for p in full.strip("|").split("|")[1:]]  # drop sys_top

        def own(h, c=c):
            v = c[col[h]].strip()
            m = re.match(r"([\d.]+)\s*\(([\d.]+)\)", v)
            return float(m.group(2)) if m else float(v or 0)

        def tot(h, c=c):
            return float(c[col[h]].strip().split(" ")[0] or 0)

        rows.append((full, inst, own("Combinational ALUTs"), own("Dedicated Logic Registers"),
                     tot("M10Ks"), tot("DSP Blocks")))
    # M10K and DSP have no own column: own = total minus direct children
    by_full = {r[0]: r for r in rows}
    child_sum = collections.defaultdict(lambda: [0.0, 0.0])
    for full, *_rest in rows:
        parent = full.rsplit("|", 1)[0]
        if parent in by_full:
            child_sum[parent][0] += by_full[full][4]
            child_sum[parent][1] += by_full[full][5]
    out = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0.0])
    for full, inst, alut, reg, m10k, dsp in rows:
        g = group_of(inst or [""])
        o = out[g]
        o[0] += alut
        o[1] += reg
        o[2] += m10k - child_sum[full][0]
        o[3] += dsp - child_sum[full][1]
    return out


def font(size):
    for f in ("/System/Library/Fonts/Menlo.ttc", "/System/Library/Fonts/SFNSMono.ttf"):
        try:
            return ImageFont.truetype(f, size)
        except OSError:
            pass
    return ImageFont.load_default()


def draw(sites, marks, table, title, out, cell=8):
    xs = [x for x, _ in sites]
    ys = [y for _, y in sites]
    x0, x1, y0, y1 = 0, max(xs), 0, max(ys)
    w_map = (x1 - x0 + 1) * cell
    h_map = (y1 - y0 + 1) * cell
    f, fb = font(13), font(15)
    table_w = 470
    img = Image.new("RGB", (w_map + table_w + 40, h_map + 50), (18, 18, 22))
    d = ImageDraw.Draw(img)
    d.text((10, 8), title, fill=(230, 230, 230), font=fb)
    oy = 34
    # site columns that never hold LABs (M10K, DSP) get a tinted empty colour
    col_kind = {}
    for (x, _y), (k, _c) in sites.items():
        if k in ("M10K", "DSP"):
            col_kind[x] = k
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            px, py = 10 + (x - x0) * cell, oy + (y1 - y) * cell
            s = sites.get((x, y))
            if s and sum(s[1].values()):
                c = COLOUR[s[1].most_common(1)[0][0]]
            elif col_kind.get(x) == "M10K":
                c = (55, 38, 30)
            elif col_kind.get(x) == "DSP":
                c = (30, 38, 60)
            else:
                c = (38, 38, 44)
            d.rectangle([px, py, px + cell - 2, py + cell - 2], fill=c)
    for x, y, label in marks:
        px, py = 10 + (x - x0) * cell + cell // 2, oy + (y1 - y) * cell + cell // 2
        d.ellipse([px - 6, py - 6, px + 6, py + 6], outline=(255, 255, 255), width=2)
        d.text((px + 10, py - 8), label, fill=(255, 255, 255), font=f)
    # table
    tx = w_map + 30
    d.text((tx, oy), f"{'group':<29}{'ALUT':>7}{'FF':>7}{'M10K':>6}{'DSP':>5}", fill=(200, 200, 200), font=f)
    ty = oy + 20
    tot = [0, 0, 0, 0]
    for g, c in GROUPS:
        v = table.get(g, [0, 0, 0, 0])
        tot = [a + b for a, b in zip(tot, v)]
        d.rectangle([tx, ty + 3, tx + 10, ty + 13], fill=c)
        d.text((tx + 16, ty), f"{g:<27}{v[0]:>7.0f}{v[1]:>7.0f}{v[2]:>6.0f}{v[3]:>5.0f}",
               fill=(220, 220, 220), font=f)
        ty += 19
    d.text((tx + 16, ty + 4), f"{'total':<27}{tot[0]:>7.0f}{tot[1]:>7.0f}{tot[2]:>6.0f}{tot[3]:>5.0f}",
           fill=(255, 255, 255), font=f)
    ty += 34
    for c, t in (((38, 38, 44), "unused LAB site"), ((55, 38, 30), "unused M10K site"),
                 ((30, 38, 60), "unused DSP site")):
        d.rectangle([tx, ty + 3, tx + 10, ty + 13], fill=c)
        d.text((tx + 16, ty), t, fill=(180, 180, 180), font=f)
        ty += 19
    d.text((tx, ty + 8), "one square = one site (X, Y), Y = 0 at the bottom;\n"
           "colour = group with most cells in the site", fill=(150, 150, 150), font=f)
    img.save(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("build")
    ap.add_argument("-o", "--out")
    ap.add_argument("--title", default="")
    a = ap.parse_args()
    b = Path(a.build)
    sites, marks = read_placement(b / "placement.tsv")
    table = read_entity_table(b / "GNET_Z1FULLR.fit.rpt")
    out = a.out or str(b / "floorplan.png")
    draw(sites, marks, table, a.title or b.name, out)
    used = sum(1 for k, c in sites.values() if sum(c.values()))
    print(f"{out}: {used} sites used")


if __name__ == "__main__":
    main()
