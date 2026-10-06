#!/usr/bin/env python3
"""Per-frame signature of a video region (R1 speed study): mean luminance,
mean R/G/B and mean absolute difference to the previous frame over a 64 x 48
downscale of the crop. Times assume the stream's constant frame rate
(optional 6th argument, default 19001/317 = 59.94 for the westtrade capture;
60 for 60/1 streams).

  r1_lum.py video start_s dur_s crop(w:h:x:y) out.csv [fps]
Output is game-derived: keep it under gitignored sim/r1/.
"""
import sys, subprocess, numpy as np
v, ss, du, crop, out = sys.argv[1:6]
fps = eval(sys.argv[6]) if len(sys.argv) > 6 else 19001 / 317
W, H = 64, 48
cmd = ["ffmpeg", "-v", "error", "-ss", ss, "-i", v, "-t", du, "-vf", f"crop={crop},scale={W}:{H}", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
p = subprocess.Popen(cmd, stdout=subprocess.PIPE)
n = 0; prev = None
with open(out, "w") as f:
    f.write("frame,t,lum,r,g,b,diff\n")
    while True:
        b = p.stdout.read(W * H * 3)
        if len(b) < W * H * 3: break
        a = np.frombuffer(b, np.uint8).reshape(H, W, 3).astype(np.float32)
        d = 0.0 if prev is None else float(np.abs(a - prev).mean())
        prev = a
        m = a.mean(axis=(0, 1))
        f.write(f"{n},{float(ss)+n/fps:.4f},{m.mean():.2f},{m[0]:.1f},{m[1]:.1f},{m[2]:.1f},{d:.2f}\n")
        n += 1
print(n)
