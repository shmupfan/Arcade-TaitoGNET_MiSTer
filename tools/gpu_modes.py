#!/usr/bin/env python3
"""Draw modes of the GP0 primitives in chosen frames of a gpu_stream.bin
(tools/mame/oracle.lua ORACLE_GPU_STREAM or tools/mame/psy_play.lua
PLAY_WINDOWS).

  tools/gpu_modes.py <gpu_stream.bin> <frame> [<frame> ...] [--ref <frame>] [--list]

For each frame, every polygon, rectangle and line is classified by:
  kind      poly3/poly4/rect(size)/line, flat or gouraud
  tex       untextured, or textured with depth 4/8/15 bit and raw (no
            colour modulation) or modulated
  semi      opaque, or semi-transparent with the mode in force (0 B/2+F/2,
            1 B+F, 2 B-F, 3 B+F/4): textured polygons take it from their
            texpage word, everything else from the draw mode in force
  texpage   (x, y) page base, CLUT (x, y) for 4 and 8 bit (CLUT Y 10 bits, MAME)
The draw mode in force is the last GP0(E1) or the texpage word of the last
textured polygon, whichever came later: as in MAME 0.288 psxgpu.cpp
decode_tpage (type 2 GPU, ZN-2), a textured polygon sets the texture page,
depth and semi mode that later rectangles and untextured primitives use.
Texture page Y is bit 4 (256) plus bit 11 (512, 2 MB VRAM).
  twin      the texture window (GP0(E2)) in force, if not zero
  mask      GP0(E6) set/check bits, if not zero
  dither    GP0(E1) bit 9
and counted with the bounding box of its vertices after the drawing offset
(GP0(E5)), relative to the drawing area's top left (GP0(E3)), so in
screen pixels before MAME's ROT270 rotation (x 0 to 319, y 0 to 239). With --ref, only signatures new in each frame against the
reference frame are shown (the banner, text and such that appear). --list
prints every primitive instead of the summary.
"""
import collections
import struct
import sys

sys.path.insert(0, __import__("os").path.dirname(__import__("os").path.abspath(__file__)))
from gpu_stream import records, gp0_len  # noqa: E402

SEMI = {0: "B/2+F/2", 1: "B+F", 2: "B-F", 3: "B+F/4"}
DEPTH = {0: "4bpp", 1: "8bpp", 2: "15bpp", 3: "15bpp"}


def s11(v):
    v &= 0x7ff
    return v - 0x800 if v & 0x400 else v


def xy(w, off):
    return s11(w) + off[0], s11(w >> 16) + off[1]


def page(tp):
    """texture page base from a texpage word or GP0(E1), MAME decode_tpage type 2"""
    return ((tp & 15) * 64, ((tp >> 4) & 1) * 256 + ((tp >> 11) & 1) * 512)


def frames_words(path, wanted):
    """GP0 words per wanted frame, in order (kinds 0, 2, 3)"""
    out = collections.defaultdict(list)
    for fr, kind, words in records(path):
        if kind in (0, 2, 3):
            out[fr] += words
    return out


def decode(words, st):
    """yield primitives of one frame; st is the running GP0 state"""
    i = 0
    while i < len(words):
        w = words[i]
        op = w >> 24
        n, cls = gp0_len(w)
        if n == -1:                      # poly-line: to the terminator
            j = i + 1
            while j < len(words) and (words[j] & 0xf000f000) != 0x50005000:
                j += 1
            n = j - i + 1
        elif n == -2:                    # CPU to VRAM: header + data
            if i + 2 < len(words):
                wh = words[i + 2]
                n = 3 + ((wh & 0xffff) * (wh >> 16) + 1) // 2
            else:
                n = 3
        pk = words[i:i + n]
        i += max(n, 1)
        if cls == "env":
            st[op] = w
            if op == 0xe1:
                st["tp"] = w & 0xffffff
            if op == 0xe5:
                st["off"] = (s11(w), s11(w >> 11))
            if op == 0xe3:
                st["org"] = (w & 0x3ff, (w >> 10) & 0x3ff)
            continue
        if cls not in ("polygon", "rect", "line"):
            continue
        e1 = st.get(0xe1, 0)
        tpm = st.get("tp", e1 & 0xffffff)        # draw mode in force
        d = {"op": op, "dither": (e1 >> 9) & 1, "twin": st.get(0xe2, 0) & 0xfffff,
             "mask": st.get(0xe6, 0) & 3}
        # vertex coordinates relative to the drawing area's top left (GP0(E3)),
        # so they are screen positions whichever buffer is being drawn
        o, g = st.get("off", (0, 0)), st.get("org", (0, 0))
        off = (o[0] - g[0], o[1] - g[1])
        pts = []
        if cls == "polygon":
            quad, tex, gour = bool(op & 8), bool(op & 4), bool(op & 0x10)
            d["kind"] = ("poly4" if quad else "poly3") + ("g" if gour else "f")
            k = 1
            uvs = []
            for v in range(4 if quad else 3):
                if gour and v > 0:
                    k += 1
                if k < len(pk):
                    pts.append(xy(pk[k], off))
                k += 1
                if tex:
                    if k < len(pk):
                        uvs.append(pk[k])
                    k += 1
            if tex and len(uvs) >= 2:
                tp = uvs[1] >> 16
                st["tp"] = tp                    # decode_tpage: sets the draw mode
                d["tex"] = DEPTH[(tp >> 7) & 3] + (" raw" if op & 1 else " mod")
                d["page"] = page(tp)
                d["semi_mode"] = (tp >> 5) & 3
                clut = uvs[0] >> 16
                d["clut"] = ((clut & 0x3f) * 16, (clut >> 6) & 0x3ff) if ((tp >> 7) & 3) < 2 else None
            else:
                d["tex"] = "none"
                d["semi_mode"] = (tpm >> 5) & 3
        elif cls == "rect":
            tex = bool(op & 4)
            size = (op >> 3) & 3
            p = xy(pk[1], off) if len(pk) > 1 else (0, 0)
            if size == 0:
                wh = pk[-1] if len(pk) > 2 else 0
                sw, sh = wh & 0x3ff, (wh >> 16) & 0x1ff
            else:
                sw = sh = {1: 1, 2: 8, 3: 16}[size]
            d["kind"] = f"rect{sw}x{sh}"
            pts = [p, (p[0] + sw, p[1] + sh)]
            if tex:
                d["tex"] = DEPTH[(tpm >> 7) & 3] + (" raw" if op & 1 else " mod")
                d["page"] = page(tpm)
                clut = pk[2] >> 16 if len(pk) > 2 else 0
                d["clut"] = ((clut & 0x3f) * 16, (clut >> 6) & 0x3ff) if ((tpm >> 7) & 3) < 2 else None
            else:
                d["tex"] = "none"
            d["semi_mode"] = (tpm >> 5) & 3
        else:
            d["kind"] = "line" + ("g" if op & 0x10 else "f")
            d["tex"] = "none"
            d["semi_mode"] = (tpm >> 5) & 3
            pts = [xy(pk[1], off)] if len(pk) > 1 else []
        d["semi"] = SEMI[d["semi_mode"]] if op & 2 else "opaque"
        d["pts"] = pts
        yield d


def sig(d):
    return (d["kind"] if not d["kind"].startswith("rect") or d["kind"] in ("rect1x1", "rect8x8", "rect16x16")
            else "rect(var)", d["tex"], d["semi"], d.get("page"), d.get("clut"),
            hex(d["twin"]) if d["twin"] else "-", d["mask"], d["dither"])


def summary(prims):
    agg = {}
    for d in prims:
        s = sig(d)
        a = agg.setdefault(s, [0, 9999, 9999, -9999, -9999, set()])
        a[0] += 1
        for x, y in d["pts"]:
            a[1], a[2], a[3], a[4] = min(a[1], x), min(a[2], y), max(a[3], x), max(a[4], y)
        if d["kind"].startswith("rect"):
            a[5].add(d["kind"])
    return agg


def main():
    a = sys.argv[1:]
    path = a[0]
    ref = int(a[a.index("--ref") + 1]) if "--ref" in a else None
    lst = "--list" in a
    frames = [int(x) for x in a[1:] if x.isdigit() and (ref is None or int(x) != ref or True)]
    frames = [f for f in frames if f != ref]
    allw = frames_words(path, None)
    st = {}
    keep = {}
    for fr in sorted(allw):
        prims = list(decode(allw[fr], st))
        if fr in frames or fr == ref:
            keep[fr] = prims
    refsig = set(summary(keep[ref]).keys()) if ref is not None and ref in keep else set()
    for fr in frames:
        if fr not in keep:
            print(f"frame {fr}: not in the stream")
            continue
        prims = keep[fr]
        print(f"=== frame {fr}: {len(prims)} primitives" + (f" (signatures new against frame {ref})" if ref is not None else ""))
        if lst:
            for d in prims:
                print("  ", sig(d), d["pts"])
            continue
        print("  count  kind        tex          semi      page        clut        twin     mask dith  bbox (x0,y0)-(x1,y1)  rect sizes")
        for s, v in sorted(summary(prims).items(), key=lambda kv: -kv[1][0]):
            if ref is not None and s in refsig:
                continue
            sizes = ",".join(sorted(v[5]))[:40]
            print(f"  {v[0]:5d}  {s[0]:10s}  {s[1]:11s}  {s[2]:8s}  {str(s[3]):10s}  {str(s[4]):10s}  {s[5]:7s}  {s[6]}    {s[7]}    ({v[1]},{v[2]})-({v[3]},{v[4]})  {sizes}")


if __name__ == "__main__":
    main()
