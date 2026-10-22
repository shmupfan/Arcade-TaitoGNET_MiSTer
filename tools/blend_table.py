#!/usr/bin/env python3
"""Per-scene predicted ratios from paced sim/gpuinfl runs (docs/gpu_blend_timing.md).

  tools/blend_table.py <runs_dir> <suffix> [<suffix> ...]

For each scene below and each run suffix (run directory <prefix>_<suffix>),
prints the vblanks per MAME frame over the scene's window (tools/blend_stats.py
method) next to the board figure. Missing or unfinished runs are marked.
Windows are stream frame numbers (stream frame 0 = the seek frame).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCENES = [
    # prefix, first, last, board ratio, role, note
    ('xii', 4, 58, '2.03 to 2.07', 'fit', 'XII Stag intro white flash, MAME 23.57 to 24.49 s'),
    ('shf', 14, 118, '1.67', 'check', 'Shikigami demo 3 cyan flash, MAME 255.16 to 256.91 s'),
    ('s3l', 1, 299, 'about 1.01 (rest of demo 3)', 'check', 'Shikigami demo 3 late, MAME 272.25 to 277.25 s'),
    ('sh1', 0, 299, '1.005 (whole demo)', 'check', 'Shikigami demo 1, MAME frames 4040 to 4339'),
    ('sh2', 0, 299, '1.003 (whole demo)', 'check', 'Shikigami demo 2, MAME frames 8600 to 8899'),
    ('xiiv', 0, 176, '1.42', 'held out', 'XII Stag vortex and white burst, MAME 24.49 to 27.45 s'),
    ('psy', 0, 299, '1.001 to 1.019 (demos)', 'held out', 'Psyvariar Revision attract demo, MAME frames 9000 to 9299'),
    ('nr', 0, 299, '1.000', 'held out', 'Night Raid TUTORIAL, MAME frames 7440 to 7739'),
]


def ratio(run, a, b):
    if not os.path.exists(os.path.join(run, 'frames_brk.txt')):
        return 'no run'
    out = subprocess.run([sys.executable, os.path.join(HERE, 'blend_stats.py'), run, str(a), str(b)],
                         capture_output=True, text=True).stdout.splitlines()
    inc = [ln for ln in out if ln.startswith('incomplete')]
    main = [ln for ln in out if 'ratio' in ln]
    if not main:
        return 'error'
    r = main[0].split('ratio ')[1]
    frames = main[0].split('frames ')[1].split(' ')[0]
    return r + (f' (frames {frames} only)' if inc else '')


def main():
    runs, sufs = sys.argv[1], sys.argv[2:]
    print('| Scene | Role | Board | ' + ' | '.join(sufs) + ' |')
    print('|---|---|---|' + '---|' * len(sufs))
    for p, a, b, board, role, note in SCENES:
        cells = [ratio(os.path.join(runs, f'{p}_{s}'), a, b) for s in sufs]
        print(f'| {note} | {role} | {board} | ' + ' | '.join(cells) + ' |')


if __name__ == '__main__':
    main()
