#!/usr/bin/env python3
"""Measure the R1 events in a MAME frame-signature run (tools/r1/r1_frames.lua):
loader screen duration (first dark frame after the sub-BIOS logo fade-out,
loader on, loader off) and the repeated-frame count in a time window.

  r1_measure.py frames.csv [--rep_t0 S --rep_t1 S]
"""
import argparse
import csv

ap = argparse.ArgumentParser()
ap.add_argument("frames")
ap.add_argument("--rep_t0", type=float, default=None)
ap.add_argument("--rep_t1", type=float, default=None)
a = ap.parse_args()
r = list(csv.DictReader(open(a.frames)))
lum = [(float(x["r"]) + float(x["g"]) + float(x["b"])) / 3 for x in r]
t = [float(x["t"]) for x in r]
# logo: first frame with lum > 100; fade-out end: next frame with lum == 0
i = next(k for k, v in enumerate(lum) if v > 100)
i = next(k for k in range(i, len(lum)) if lum[k] == 0)
on = next(k for k in range(i, len(lum)) if lum[k] > 3)
off = next(k for k in range(on, len(lum)) if all(lum[j] == 0 for j in range(k, min(k + 10, len(lum)))))
print(f"loader_on frame {r[on]['frame']} t {t[on]:.4f}")
print(f"loader_off frame {r[off]['frame']} t {t[off]:.4f}")
print(f"loader_frames {off - on} loader_s {t[off] - t[on]:.4f}")
if a.rep_t0 is not None:
    seg = [x for x in r if a.rep_t0 <= float(x["t"]) < a.rep_t1]
    z = sum(1 for x in seg if float(x["diff"]) == 0.0)
    print(f"repeats {z} of {len(seg)} ({100 * z / max(len(seg), 1):.2f}%) in {a.rep_t0}-{a.rep_t1}")
