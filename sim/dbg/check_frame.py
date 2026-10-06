#!/usr/bin/env python3
"""Decode the debug overlay text from a frame written by tb_zn_dbg_overlay
(P3 PPM) and compare it with the values the bench's stimulus produces.

Usage: check_frame.py <frame.ppm> [--dbl] [--dr] [--png out.png]

--dr: the frame has the eleventh row DR (tb_zn_dbg_overlay -gDR=1).

The text is found from the black box (its top left corner), then every 8x8
cell is matched against the font of tools/gnet/dbg_font.py. Exits non-zero
on an unknown glyph or a row that differs from the expectation.
"""
import os
import re
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools", "gnet"))
import dbg_font  # noqa: E402

LABELS = ["PC", "DA", "IO", "MS", "WD", "RS", "XP", "XD", "XI", "XM"]


def read_ppm(path):
    tok = open(path).read().split()
    assert tok[0] == "P3"
    w, h = int(tok[1]), int(tok[2])
    vals = list(map(int, tok[4:]))
    assert len(vals) == w * h * 3, (len(vals), w * h * 3)
    px = [tuple(vals[i:i + 3]) for i in range(0, len(vals), 3)]
    return w, h, px


def write_png(path, w, h, px, scale=3):
    raw = b""
    for y in range(h):
        row = b"".join(bytes(px[y * w + x]) * scale for x in range(w))
        raw += (b"\x00" + row) * scale
    W, H = w * scale, h * scale

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    open(path, "wb").write(data)


def main():
    args = sys.argv[1:]
    dbl = "--dbl" in args
    dr = "--dr" in args
    labels = LABELS + (["DR"] if dr else [])
    png = None
    if "--png" in args:
        png = args[args.index("--png") + 1]
    path = args[0]
    sc = 2 if dbl else 1
    w, h, px = read_ppm(path)
    if png:
        write_png(png, w, h, px)

    glyphs = {}
    for code, ch in enumerate(dbg_font.ORDER):
        glyphs[tuple(dbg_font.rows(ch))] = ch

    black = (0, 0, 0)
    white = (255, 255, 255)
    # box top left: first black dot in raster order (the gradient has no black)
    top = left = None
    for y in range(h):
        for x in range(w):
            if px[y * w + x] == black:
                top, left = y, x
                break
        if top is not None:
            break
    if top is None:
        print("FAIL: no overlay box")
        return 1
    ox, oy = left + 2 * sc, top + 2
    print("box top left at dot %d, line %d (text at %d, %d)" % (left, top, ox, oy))

    text = []
    bad = 0
    for r in range(len(labels)):
        line = ""
        for c in range(12):
            rows = []
            for gy in range(8):
                v = 0
                for gx in range(8):
                    p = px[(oy + r * 8 + gy) * w + ox + (c * 8 + gx) * sc]
                    if dbl:
                        p2 = px[(oy + r * 8 + gy) * w + ox + (c * 8 + gx) * sc + 1]
                        if p2 != p:
                            bad += 1
                    if p == white:
                        v |= 0x80 >> gx
                    elif p != black:
                        bad += 1
                rows.append(v)
            ch = glyphs.get(tuple(rows))
            if ch is None:
                bad += 1
                ch = "?"
            line += ch
        text.append(line)
        print("  " + line)
    if bad:
        print("FAIL: %d dots or glyphs not recognised" % bad)
        return 1

    # expectations from tb_zn_dbg_overlay's stimulus
    exact = {
        "PC": "8003 F00C",
        "DA": "8012 3456",
        "IO": "E801 1814",
        "RS": "0101 0005",
        "XP": "8001 2ABC",
        "XD": "8004 0000",
        "XI": "0003 1044",
        "XM": "0000 0003",
        "DR": "1010 01A3",
    }
    fail = 0
    vals = {}
    for line in text:
        lab, body = line[:2], line[3:]
        if lab not in labels or line[2] != " " or line[7] != " ":
            print("FAIL: layout of %r" % line)
            fail += 1
            continue
        vals[lab] = body
        if lab in exact and body != exact[lab]:
            print("FAIL: %s %s, expected %s" % (lab, body, exact[lab]))
            fail += 1
    if [l[:2] for l in text] != labels:
        print("FAIL: label order")
        fail += 1
    ms = int(vals["MS"].replace(" ", ""), 16)
    nk = int(vals["WD"][:4], 16)
    nkmax = int(vals["WD"][5:], 16)
    # the capture frame is frame 3 (about 40 to 60 ms after the reset)
    if not (30 <= ms <= 70):
        print("FAIL: MS %d ms out of range" % ms)
        fail += 1
    if abs(nk - ms) > 1 or abs(nkmax - nk) > 1:
        print("FAIL: WD %d / %d against MS %d (no kick since the reset)" % (nk, nkmax, ms))
        fail += 1
    print("MS %d ms, WD %d / %d ms" % (ms, nk, nkmax))
    if fail:
        print("FAIL: %d rows" % fail)
        return 1
    print("PASS: %d rows decoded, %d exact, MS and WD in range" % (len(labels), 9 if dr else 8))
    return 0


if __name__ == "__main__":
    sys.exit(main())
