#!/usr/bin/env python3
"""Frame hashes for comparing the core's video with MAME's (frame oracle).

  tools/frame_hash.py mame <dir> [--keep-raw]       dir from tools/mame/frame_oracle.lua
  tools/frame_hash.py ppm <frames dir> <frames.tsv> [--fps 59.8173]
  tools/frame_hash.py events <frames.tsv> <out dir> [--every 30]
  tools/frame_hash.py diff <a frames.tsv> <b frames.tsv> [--ahash-max 10] [--every 30]
  tools/frame_hash.py first <core frames.tsv> <mame frames.tsv> [--ahash-max 10] [--near 0.5] [--far 10] [--tmax s]

frames.tsv, one row per video frame (format agreed with the fullsys harness,
which writes the same file for the core), tab separated, "#" header line:
  frame      1 = first frame
  t_s        emulated seconds since power-on at the frame's vblank start
             (MAME: machine time at the frame notifier)
  w, h       visible resolution
  crc555     zlib CRC32 over w555 = r5 << 10 | g5 << 5 | b5 (r5 = R8 >> 3 and
             so on), 2 bytes little-endian each, row major, full w x h
  crc555_x1  the same over w - 1 columns: MAME columns 0..w-2, core columns
             1..w-1 (the core shows VRAM from the GP1(05h) x, MAME from x + 1)
  ahash      Y = 299 r5 + 587 g5 + 114 b5 (integer); 8 x 8 cells, cell (i, j)
             covers x floor(i w / 8) to floor((i + 1) w / 8) and likewise y
             (half open); C = floor(sum Y / pixels); bit = 64 C > sum of the
             64 C; row major, first cell in bit 63; 16 hex digits
  dhash      9 x 8 cells as above; bit (j, i) = C[j][i] < C[j][i + 1] for
             i = 0..7; row major, first in bit 63
  luma       sum Y / pixels * 255 / 31000, two decimals (information only)

events writes samples.tsv (every --every-th row) and changes.tsv: a frame
is changed when the dhash Hamming distance to the previous frame is 12 or
more, or the resolution changes; consecutive changed frames form one event
(t_s, frame of the first, len, maxdist, w, h after the event).
diff pairs the samples of a with the nearest-in-time frame of b (ahash
distance, crc555_x1 equal), then the change events in order with dt.
first reports, for the core frames inside the time range MAME covers, the
first frame with no MAME frame within +-near s whose ahash is within
ahash-max bits and whose resolution matches (width equal, height within
--hdiff lines, default 8: the core shows 239 or 246 lines where MAME
shows 240), the same within +-far s (content, not only a lag), every run
of consecutive core frames unmatched within +-far s, and how many core
frames have a crc555_x1 equal to the nearest MAME frame's.
"""
import argparse
import glob
import os
import re
import zlib

import numpy as np

HDR = "#frame\tt_s\tw\th\tcrc555\tcrc555_x1\tahash\tdhash\tluma\n"
DHASH_CHANGE = 12


def cells(y, nx, ny):
    h, w = y.shape
    c = np.empty((ny, nx), dtype=np.int64)
    for j in range(ny):
        for i in range(nx):
            blk = y[j * h // ny:(j + 1) * h // ny, i * w // nx:(i + 1) * w // nx]
            c[j, i] = int(blk.sum()) // blk.size
    return c


def bits(a):
    v = 0
    for b in a.reshape(-1):
        v = (v << 1) | int(bool(b))
    return v


def row(frame, t, rgb8, x1_from):
    """rgb8: h x w x 3 uint8; x1_from: 0 for MAME (cols 0..w-2), 1 for the core"""
    h, w = rgb8.shape[:2]
    q = (rgb8 >> 3).astype(np.int64)
    w555 = ((q[..., 0] << 10) | (q[..., 1] << 5) | q[..., 2]).astype("<u2")
    crc = zlib.crc32(w555.tobytes())
    crc1 = zlib.crc32(np.ascontiguousarray(w555[:, x1_from:x1_from + w - 1]).tobytes())
    y = 299 * q[..., 0] + 587 * q[..., 1] + 114 * q[..., 2]
    a = cells(y, 8, 8)
    d = cells(y, 9, 8)
    luma = int(y.sum()) / (w * h) * 255 / 31000
    return (f"{frame}\t{t:.6f}\t{w}\t{h}\t{crc:08x}\t{crc1:08x}\t{bits(64 * a > a.sum()):016x}\t"
            f"{bits(d[:, :-1] < d[:, 1:]):016x}\t{luma:.2f}\n")


def from_mame(d, keep):
    times = {}
    for l in open(os.path.join(d, "times.tsv")):
        if not l.startswith("#"):
            f = l.split("\t")
            times[int(f[0])] = float(f[1])
    out = [HDR]
    for p in sorted(glob.glob(os.path.join(d, "raw", "f*_*x*.argb"))):
        fr, w, h = map(int, re.search(r"f(\d+)_(\d+)x(\d+)\.argb$", p).groups())
        a = np.frombuffer(open(p, "rb").read(), dtype="<u4").reshape(h, w)
        rgb = np.stack([(a >> 16) & 0xff, (a >> 8) & 0xff, a & 0xff], axis=-1).astype(np.uint8)
        out.append(row(fr, times[fr], rgb, 0))
        if not keep:
            os.remove(p)
    open(os.path.join(d, "frames.tsv"), "w").write("".join(out))


def read_ppm(p):
    data = open(p, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    w, h, mx = map(int, m.groups())
    assert mx == 255, p
    return np.frombuffer(data[m.end():m.end() + w * h * 3], dtype=np.uint8).reshape(h, w, 3)


def from_ppm(src, dst, fps):
    out = [HDR]
    for p in sorted(glob.glob(os.path.join(src, "f*.ppm"))):
        fr = int(re.search(r"f(\d+)\.ppm$", p).group(1))
        out.append(row(fr, (fr - 1) / fps, read_ppm(p), 1))
    open(dst, "w").write("".join(out))


def load(path):
    rows = []
    for l in open(path):
        if l.startswith("#") or not l.strip():
            continue
        f = l.rstrip("\n").split("\t")
        rows.append({"frame": int(f[0]), "t": float(f[1]), "w": int(f[2]), "h": int(f[3]), "crc": f[4],
                     "crc1": f[5], "ahash": int(f[6], 16), "dhash": int(f[7], 16), "luma": f[8], "line": l})
    return rows


def hd(a, b):
    return bin(a ^ b).count("1")


def change_events(rows):
    ev, cur = [], None
    for p, r in zip(rows, rows[1:]):
        d = hd(p["dhash"], r["dhash"])
        if d >= DHASH_CHANGE or (p["w"], p["h"]) != (r["w"], r["h"]):
            if cur and cur["frame"] + cur["len"] == r["frame"]:
                cur["len"] += 1; cur["dist"] = max(cur["dist"], d); cur["w"], cur["h"] = r["w"], r["h"]
            else:
                cur = {"t": r["t"], "frame": r["frame"], "len": 1, "dist": d, "w": r["w"], "h": r["h"]}
                ev.append(cur)
    return ev


def events(src, d, every):
    os.makedirs(d, exist_ok=True)
    rows = load(src)
    open(os.path.join(d, "samples.tsv"), "w").write(HDR + "".join(r["line"] for r in rows if r["frame"] % every == 0))
    open(os.path.join(d, "changes.tsv"), "w").write(
        "#t_s\tframe\tlen\tmaxdist\tw\th\n" +
        "".join(f"{e['t']:.6f}\t{e['frame']}\t{e['len']}\t{e['dist']}\t{e['w']}\t{e['h']}\n" for e in change_events(rows)))


def diff(a, b, amax, every):
    ra, rb = load(a), load(b)
    tb = np.array([r["t"] for r in rb])
    print("#t_a\tt_b\tres_a\tres_b\tcrc1_eq\tahash_dist\tmatch")
    for r in ra:
        if r["frame"] % every:
            continue
        s = rb[int(np.abs(tb - r["t"]).argmin())]
        dist = hd(r["ahash"], s["ahash"])
        print(f"{r['t']:.3f}\t{s['t']:.3f}\t{r['w']}x{r['h']}\t{s['w']}x{s['h']}\t{int(r['crc1'] == s['crc1'])}\t"
              f"{dist}\t{int(dist <= amax)}")
    ea, eb = change_events(ra), change_events(rb)
    print("#change\tt_a\tt_b\tdt\tres_a\tres_b")
    for i in range(max(len(ea), len(eb))):
        x = ea[i] if i < len(ea) else None
        y = eb[i] if i < len(eb) else None
        dt = f"{y['t'] - x['t']:+.3f}" if x and y else "-"
        print(f"{i}\t{x['t'] if x else '-'}\t{y['t'] if y else '-'}\t{dt}\t"
              f"{str(x['w']) + 'x' + str(x['h']) if x else '-'}\t{str(y['w']) + 'x' + str(y['h']) if y else '-'}")


def first(core, mame, amax, near, far, tmax_limit=None, hdiff=8):
    rc, rm = load(core), load(mame)
    tm = np.array([r["t"] for r in rm])
    tmax = tm.max() if tmax_limit is None else min(tm.max(), tmax_limit)

    def match(r, win):
        lo, hi = np.searchsorted(tm, r["t"] - win), np.searchsorted(tm, r["t"] + win, side="right")
        best = None
        for s in rm[lo:hi]:
            d = hd(r["ahash"], s["ahash"])
            if s["w"] == r["w"] and abs(s["h"] - r["h"]) <= hdiff and d <= amax:
                return s, d
            if best is None or d < best[1]:
                best = (s, d)
        return None, best

    found = {"near": None, "far": None}
    crc_eq = 0
    for r in rc:
        if r["t"] > tmax:
            break
        s = rm[int(np.abs(tm - r["t"]).argmin())]
        crc_eq += r["crc1"] == s["crc1"]
        for key, win in (("near", near), ("far", far)):
            if found[key] is None:
                m, best = match(r, win)
                if m is None:
                    found[key] = (r, s, best)
    for key, win in (("near", near), ("far", far)):
        f = found[key]
        if f is None:
            print(f"{key} (+-{win} s): every core frame up to {tmax:.3f} s has a match")
            continue
        r, s, best = f
        bd = f"{best[1]} bits at t {best[0]['t']:.3f} ({best[0]['w']}x{best[0]['h']})" if best else "no MAME frame in the window"
        print(f"{key} (+-{win} s): first unmatched core frame {r['frame']} t {r['t']:.3f} {r['w']}x{r['h']} "
              f"luma {r['luma']}; nearest MAME frame {s['frame']} t {s['t']:.3f} {s['w']}x{s['h']} luma {s['luma']}; "
              f"closest ahash in window {bd}")
    print(f"crc555_x1 equal to the nearest MAME frame: {crc_eq} core frames")
    seg = None
    print("unmatched runs (+-far):")
    for r in rc:
        if r["t"] > tmax:
            break
        m, best = match(r, far)
        if m is None:
            if seg and seg["last"]["frame"] + 1 == r["frame"]:
                seg["last"] = r; seg["n"] += 1
            else:
                if seg:
                    _seg_print(seg)
                seg = {"first": r, "last": r, "n": 1, "best": best}
    if seg:
        _seg_print(seg)


def _seg_print(seg):
    f, l, b = seg["first"], seg["last"], seg["best"]
    bd = f"closest {b[1]} bits at {b[0]['t']:.3f} {b[0]['w']}x{b[0]['h']}" if b else "no MAME frame"
    print(f"  frames {f['frame']}-{l['frame']} t {f['t']:.3f}-{l['t']:.3f} ({seg['n']} frames) "
          f"{f['w']}x{f['h']} luma {f['luma']}; first frame {bd}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    m = sub.add_parser("mame"); m.add_argument("dir"); m.add_argument("--keep-raw", action="store_true")
    p = sub.add_parser("ppm"); p.add_argument("src"); p.add_argument("dst"); p.add_argument("--fps", type=float, default=59.8173)
    e = sub.add_parser("events"); e.add_argument("src"); e.add_argument("out"); e.add_argument("--every", type=int, default=30)
    d = sub.add_parser("diff"); d.add_argument("a"); d.add_argument("b")
    d.add_argument("--ahash-max", type=int, default=10); d.add_argument("--every", type=int, default=30)
    f = sub.add_parser("first"); f.add_argument("core"); f.add_argument("mame")
    f.add_argument("--ahash-max", type=int, default=10); f.add_argument("--near", type=float, default=0.5)
    f.add_argument("--far", type=float, default=10.0)
    f.add_argument("--hdiff", type=int, default=8)
    f.add_argument("--tmax", type=float, default=None, help="compare core frames up to this time only (e.g. 40, before MAME's coin)")
    a = ap.parse_args()
    if a.cmd == "first":
        first(a.core, a.mame, a.ahash_max, a.near, a.far, a.tmax, a.hdiff)
        return
    if a.cmd == "mame":
        from_mame(a.dir, a.keep_raw)
    elif a.cmd == "ppm":
        from_ppm(a.src, a.dst, a.fps)
    elif a.cmd == "events":
        events(a.src, a.out, a.every)
    else:
        diff(a.a, a.b, a.ahash_max, a.every)


if __name__ == "__main__":
    main()
