#!/usr/bin/env python3
"""Paced GPU replay statistics (docs/gpu_blend_timing.md).

Reads frames_brk.txt of a sim/gpuinfl run made with -gPACED=true (one line
per stream frame: frame rel_vblank cycles busy tex clut dst wfifo other
misses dst_reads dst_beats tex_reads tex_beats wr_beats walk drawn, then 10
pixel classes and, from the gpu-blend bench on, spx_cycles spx_waits).

  tools/blend_stats.py <run_dir> <first_frame> <last_frame>
      vblanks used by stream frames first..last (release of last + 1 minus
      release of first) over the number of frames: the predicted board/MAME
      style ratio of the window under the DrawSync, VSync loop; plus the busy
      breakdown summed over the window, in clk2x and as shares.
  tools/blend_stats.py <run_dir> <first> <last> --frames
      the same, plus one line per frame (vblanks, busy, classes).
"""
import sys

COLS = ['frame', 'rel_vb', 'cycles', 'busy', 'tex', 'clut', 'dst', 'wfifo', 'other', 'misses',
        'dst_reads', 'dst_beats', 'tex_reads', 'tex_beats', 'wr_beats', 'walk', 'drawn',
        'p_flat', 'p_flat_s', 'p_gour', 'p_gour_s', 'p_tex', 'p_tex_s', 'r', 'r_s', 'r_tex', 'r_tex_s',
        'spx_cyc', 'spx_waits']


def load(run):
    rows = {}
    for ln in open(run.rstrip('/') + '/frames_brk.txt'):
        p = list(map(int, ln.split()))
        rows[p[0]] = dict(zip(COLS, p))
    return rows


def main():
    run, a, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    rows = load(run)
    # MAME frames without GPU words have no line; a frame is complete when a
    # later frame has been released
    nxt = lambda f: min((k for k in rows if k > f), default=None)
    if nxt(b) is None:
        done = [k for k in rows if nxt(k) is not None]
        print(f'incomplete: frames after {b} not released yet (last complete frame {max(done)})')
        b = max(done)
    n = b - a + 1
    vb = rows[nxt(b)]['rel_vb'] - rows[a]['rel_vb'] - (nxt(b) - b - 1)
    print(f'{run}: frames {a}..{b} ({n}), vblanks {vb}, ratio {vb / n:.3f}')
    keys = ['busy', 'tex', 'spx_cyc', 'clut', 'dst', 'wfifo', 'other', 'misses', 'spx_waits', 'tex_reads',
            'dst_reads', 'walk', 'drawn']
    fr = [f for f in range(a, b + 1) if f in rows]
    tot = {k: sum(rows[f].get(k, 0) for f in fr) for k in keys}
    busy = tot['busy'] or 1
    print('per frame mean: ' + ', '.join(f'{k} {tot[k] / n:.0f}' for k in keys))
    print('shares of busy: ' + ', '.join(f'{k} {100 * tot[k] / busy:.1f}%' for k in
                                         ('tex', 'spx_cyc', 'clut', 'dst', 'wfifo', 'other')))
    if '--frames' in sys.argv:
        for f in fr:
            r = rows[f]
            v = rows[nxt(f)]['rel_vb'] - r['rel_vb']
            print(f"{f} vb {v} busy {r['busy']} tex {r['tex']} spx {r.get('spx_cyc', 0)} dst {r['dst']} "
                  f"other {r['other']} misses {r['misses']} drawn {r['drawn']}")


if __name__ == '__main__':
    main()
