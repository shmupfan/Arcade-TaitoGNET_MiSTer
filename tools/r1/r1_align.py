#!/usr/bin/env python3
"""Align a PCB footage luminance trace with a MAME frame-signature trace.

For each window of the footage (default 4 s, step 1 s) find the MAME time
offset that maximises the correlation of the z-scored mean-luminance
signals (both resampled to 120 Hz), within a search range. A drifting
offset inside one attract segment means the two ran the same content at
different speeds (slowdown). Prints t_pcb, best offset, correlation, and
the second-best peak's correlation as a confidence check.

  r1_align.py pcb_lum.csv mame_frames.csv --t0 80 --t1 295 --lo 50 --hi 75
pcb csv: frame,t,lum,... (sim/r1/lum.py); mame csv: tools/r1/r1_frames.lua.
"""
import argparse
import csv
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("pcb"); ap.add_argument("mame")
ap.add_argument("--t0", type=float, default=80); ap.add_argument("--t1", type=float, default=295)
ap.add_argument("--lo", type=float, default=50); ap.add_argument("--hi", type=float, default=75)
ap.add_argument("--win", type=float, default=4.0); ap.add_argument("--step", type=float, default=1.0)
ap.add_argument("--sig", default="lum", choices=["lum", "diff"])
a = ap.parse_args()

def load(path, kind):
    t, v = [], []
    for r in csv.DictReader(open(path)):
        t.append(float(r["t"]))
        if a.sig == "diff":
            v.append(float(r["diff"]))
        elif kind == "pcb":
            v.append(float(r["lum"]))
        else:
            v.append((float(r["r"]) + float(r["g"]) + float(r["b"])) / 3)
    return np.array(t), np.array(v)

FS = 120.0
tp, vp = load(a.pcb, "pcb")
tm, vm = load(a.mame, "mame")
grid_m = np.arange(tm[0], tm[-1], 1 / FS)
sm = np.interp(grid_m, tm, vm)

def z(x):
    s = x.std()
    return (x - x.mean()) / s if s > 1e-6 else None

t = a.t0
while t + a.win <= a.t1:
    g = np.arange(t, t + a.win, 1 / FS)
    wp = z(np.interp(g, tp, vp))
    if wp is None:
        print(f"{t:8.2f}  flat"); t += a.step; continue
    best = []
    n = len(g)
    i0 = int((t + a.lo - grid_m[0]) * FS); i1 = int((t + a.hi - grid_m[0]) * FS)
    i0 = max(i0, 0); i1 = min(i1, len(sm) - n)
    cs = np.full(max(i1 - i0, 0), -2.0)
    for k, i in enumerate(range(i0, i1)):
        wm = z(sm[i:i + n])
        if wm is not None:
            cs[k] = float(np.dot(wp, wm) / n)
    if len(cs) == 0:
        break
    k = int(np.argmax(cs))
    off = grid_m[i0 + k] - t
    mask = np.abs(np.arange(len(cs)) - k) > int(0.5 * FS)
    second = float(cs[mask].max()) if mask.any() else float("nan")
    print(f"{t:8.2f} {off:9.4f} {cs[k]:6.3f} {second:6.3f}")
    t += a.step
