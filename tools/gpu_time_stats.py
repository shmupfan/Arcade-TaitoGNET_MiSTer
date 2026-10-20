#!/usr/bin/env python3
"""R23: GPU drawing time statistics from tb_gpu_replay GTIME runs
(frames_time.txt, docs/gpu_draw_time.md).

  tools/gpu_time_stats.py seek <label> <run_dir> [<run_dir> ...]
      per-run and pooled distribution of span (first word to GPU idle) and
      busy (non-idle clk2x cycles) per stream frame, in ms, frames over the
      frame period. The last frame of a run is dropped when the run ended
      before it was drawn (overrun flag at MAXFRAME).
  tools/gpu_time_stats.py demo <first> <last> <gpu.log> <run_dir_S> [...]
      demo segment from chunked seek runs: run_dir_S replays MAME frames
      S.. (directory name ends in _S); frames first..last (MAME numbering)
      are taken, each from the chunk that starts at or before it, latest
      start first. gpu.log (oracle) gives the DMA2 kick time of every frame;
      a frame whose kick offset + span exceeds the frame period would miss
      the next flip, and costs ceil((offset + span) / period) - 1 frames.
"""
import math
import os
import sys

T2X_NS = 14.762            # clk2x 67.7376 MHz period, as in the testbench
PERIOD_MS = 16.715         # 59.826 Hz
P_S = 0.01671511           # MAME frame period (oracle VRAM dump times)
# PCB (westtrade) extra frames over MAME, cumulative from MAME frame 3788,
# read from the R1 alignment (gnet-mister-r1 sim/r1/align_demo1.txt, points
# with correlation >= 0.97 at PCB 130.0, 135.0, 143.0, 154.5 s, and the
# 177.0 s end point of docs/r1_speed_study.md, 3.734 s): offset change / 16.715 ms
PCB = [(4040, 16.5), (4323, 32.9), (4759, 75.3), (5401, 121.7), (6646, 223.4)]


def load(d):
    rows = []
    for ln in open(os.path.join(d, 'frames_time.txt')):
        p = ln.split()
        if len(p) < 8:
            continue
        fr, words, t0, t1, span, busy, ov, vb = map(int, p[:8])
        rows.append(dict(frame=fr, words=words, span=span * T2X_NS / 1e6,
                         busy=busy * T2X_NS / 1e6, overrun=ov, vblank=vb))
    if rows and rows[-1]['overrun']:
        rows.pop()                     # cut off by MAXFRAME
    return rows


def pct(v, q):
    s = sorted(v)
    return s[min(len(s) - 1, int(math.ceil(q * len(s))) - 1)]


def summary(name, rows):
    sp = [r['span'] for r in rows]
    bu = [r['busy'] for r in rows]
    ov = sum(r['overrun'] for r in rows)
    over = sum(1 for x in sp if x > PERIOD_MS)
    print(f'{name:22s} n={len(rows):4d}  span ms min {min(sp):6.2f} med {pct(sp, .5):6.2f} '
          f'p95 {pct(sp, .95):6.2f} max {max(sp):6.2f}  busy med {pct(bu, .5):6.2f} max {max(bu):6.2f}  '
          f'>{PERIOD_MS} {over}  overrun {ov}  words/frame med {pct([r["words"] for r in rows], .5)}')


def kicks(path, first, last):
    k = {}
    for ln in open(path):
        p = ln.split()
        if len(p) < 6 or p[2] != 'W' or p[3] != '1f8010a8':
            continue
        fr = int(p[1])
        if first <= fr <= last and int(p[4], 16) & 0x01000000 and fr not in k:
            k[fr] = (float(p[0]) - fr * P_S) * 1e3
    return k


def main():
    mode = sys.argv[1]
    if mode == 'seek':
        label, dirs = sys.argv[2], sys.argv[3:]
        allr = []
        for d in dirs:
            r = load(d)
            summary(os.path.basename(d.rstrip('/')), r)
            allr += r
        if len(dirs) > 1:
            summary(label + ' pooled', allr)
        return
    first, last, glog, dirs = int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5:]
    starts = sorted(((int(d.rstrip('/').rsplit('_', 1)[1]), d) for d in dirs), reverse=True)
    data = {s: {r['frame']: r for r in load(d)} for s, d in starts}
    rows = []
    for f in range(first, last + 1):
        for s, d in starts:
            if s <= f and (f - s) in data[s]:
                r = dict(data[s][f - s]); r['mame'] = f
                rows.append(r)
                break
    k = kicks(glog, first, last)
    missing = (last - first + 1) - len(rows)
    summary(f'demo {first}-{last}', rows)
    if missing:
        print(f'  frames not covered: {missing}')
    off = [k[r['mame']] for r in rows if r['mame'] in k]
    print(f'  kick offset ms: min {min(off):.3f} med {pct(off, .5):.3f} max {max(off):.3f} ({len(off)} frames)')
    # GPU work per frame: span of a frame that ended before the next one
    # started; inside a run of overrun frames (backlog) the run's busy time
    # is shared evenly between its frames, the frame that ends it included
    work = {}
    for s, d in starts:
        fr = sorted(data[s])
        i = 0
        while i < len(fr):
            if not data[s][fr[i]]['overrun']:
                work[s + fr[i]] = work.get(s + fr[i]) or data[s][fr[i]]['busy']
                i += 1
                continue
            j = i
            while j < len(fr) - 1 and data[s][fr[j]]['overrun']:
                j += 1
            tot = sum(data[s][fr[x]]['busy'] for x in range(i, j + 1))
            for x in range(i, j + 1):
                work.setdefault(s + fr[x], tot / (j - i + 1))
            i = j + 1
    w = {r['mame']: work[r['mame']] for r in rows}
    wl = list(w.values())
    print(f'  work per frame ms: med {pct(wl, .5):.2f} p95 {pct(wl, .95):.2f} max {max(wl):.2f}; '
          f'frames over {PERIOD_MS} ms minus kick offset: '
          f'{sum(1 for f in w if k.get(f, 0) + w[f] > PERIOD_MS)}')
    # game loop DrawSync then VSync then kick (gpu.log): a frame whose kick
    # offset + k x work passes the next vblank costs ceil(.. / period) - 1
    print('  predicted extra frames, cumulative at the PCB check points, GPU time scaled by k:')
    print('    PCB      ' + '  '.join(f'{f}:{v:6.1f}' for f, v in PCB))
    for kf in (1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.4, 1.6):
        cum, at = 0, {}
        for f in sorted(w):
            cum += max(0, math.ceil((k.get(f, 0.0) + kf * w[f]) / PERIOD_MS) - 1)
            at[f] = cum
        print(f'    k={kf:4.2f}   ' + '  '.join(f'{f}:{at.get(f, 0):6d}' for f, _ in PCB))
    # per 480-frame block (drift profile)
    for s in range(first, last + 1, 240):
        b = [r for r in rows if s <= r['mame'] < s + 240]
        if b:
            sp = [r['span'] for r in b]
            print(f'  MAME frames {s}-{s + len(b) - 1}: span med {pct(sp, .5):6.2f} p95 {pct(sp, .95):6.2f} max {max(sp):6.2f}')


if __name__ == '__main__':
    main()
