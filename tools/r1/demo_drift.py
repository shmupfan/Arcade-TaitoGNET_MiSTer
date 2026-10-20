#!/usr/bin/env python3
"""Core speed against MAME over Ray Crisis attract demo 1, from MiSTer screenshots.

demo_drift.py <mame snap dir> <screenshot dir> <tag> [first last]

- MAME side: tools/mame/oracle_run.sh with ORACLE_SNAP_EVERY=1 (snap/f<frame>.png).
- Core side: MiSTer screenshots taken at a steady interval during the demo,
  <tag>_<i>.png, plus <tag>.log with one "<i> <unix time>" line per
  screenshot command (the capture script is not in this repository).
- Each screenshot is matched to the MAME frame with the smallest mean squared
  difference (both reduced to 80 x 60 grey). A match is kept when every frame
  within 5% of the best distance lies within 3 frames of it (static scenes are
  dropped as ambiguous).
- Kept matches inside MAME frames first..last (default 3788..6646, demo 1 as
  in docs/gpu_draw_time.md 4.1) give core seconds against MAME seconds
  (59.826 Hz); the Theil-Sen slope is the core / MAME time ratio. The PCB's
  ratio over the same span is 1.078 (docs/r1_speed_study.md 3.2).
"""
import os
import re
import sys

import numpy as np
from PIL import Image

MAME_HZ = 59.826
SIZE = (80, 60)


def load(path):
    im = Image.open(path).convert("L").resize(SIZE, Image.BILINEAR)
    return np.asarray(im, dtype=np.float32)


def main():
    mame_dir, shot_dir, tag = sys.argv[1:4]
    first, last = (int(sys.argv[4]), int(sys.argv[5])) if len(sys.argv) > 5 else (3788, 6646)
    lo, hi = first - 300, last + 300
    frames, imgs = [], []
    for name in sorted(os.listdir(mame_dir)):
        m = re.match(r"f(\d+)\.png$", name)
        if m and lo <= int(m.group(1)) <= hi:
            frames.append(int(m.group(1)))
            imgs.append(load(os.path.join(mame_dir, name)).ravel())
    frames = np.array(frames)
    mame = np.stack(imgs)
    times = {}
    with open(os.path.join(shot_dir, tag + ".log")) as f:
        for line in f:
            k, v = line.split()
            if k.isdigit():
                times[int(k)] = float(v)
    rows = []
    for i in sorted(times):
        p = os.path.join(shot_dir, f"{tag}_{i}.png")
        if not os.path.exists(p):
            continue
        d = ((mame - load(p).ravel()) ** 2).mean(axis=1)
        b = int(d.argmin())
        near = frames[d <= d[b] * 1.05 + 1.0]
        ok = near.max() - near.min() <= 3
        rows.append((i, times[i], int(frames[b]), float(d[b]), ok))
    for r in rows:
        print("%3d %.3f f%05d mse %8.1f %s" % (r[0], r[1], r[2], r[3], "ok" if r[4] else "ambiguous"))
    keep = [(t, f / MAME_HZ) for _, t, f, _, ok in rows if ok and first <= f <= last]
    if len(keep) < 10:
        print("too few matches in the demo span:", len(keep))
        return
    t = np.array([k[0] for k in keep])
    m = np.array([k[1] for k in keep])
    slopes = [(t[j] - t[i]) / (m[j] - m[i]) for i in range(len(t)) for j in range(i + 1, len(t)) if m[j] - m[i] > 5]
    # Theil-Sen start, drop matches more than 1 s off that line (dark or
    # transition frames matched into the span), then least squares.
    s = float(np.median(slopes))
    k = abs(t - (np.median(t - s * m) + s * m)) < 1.0
    t, m = t[k], m[k]
    s, c = np.polyfit(m, t, 1)
    resid = t - (s * m + c)
    print("matches in span: %d of %d; MAME span covered %.2f s; core/MAME ratio %.4f; "
          "residual sd %.3f s, max %.3f s; projected demo 1 length %.2f s (MAME 47.77, PCB 51.50)"
          % (len(t), len(keep), m.max() - m.min(), s, resid.std(), abs(resid).max(),
             s * (last - first + 1) / MAME_HZ))
    for a in np.arange(m.min(), m.max(), 8.0):
        k = (m >= a) & (m < a + 8.0)
        if k.sum() > 4:
            print("  MAME frames %d to %d: ratio %.3f (n %d)"
                  % (a * MAME_HZ, (a + 8.0) * MAME_HZ, np.polyfit(m[k], t[k], 1)[0], k.sum()))


if __name__ == "__main__":
    main()
