#!/usr/bin/env python3
"""Memory latency the ZSG-2 engine tolerates per outstanding-request limit
(INFL), at the worst-case load of tools/zsg2/zsg2_stress.py. Runs the
INFL builds of sim/zsg2 (INFL=<n> sim/zsg2/build.sh) one at a time under
nice, fixed latency, always-ready memory.

  zsg2_latency_sweep.py <burst.ev> <stagger.ev> <flashdir>
"""
import re
import subprocess
import sys
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
LATS = [8, 16, 24, 32, 40, 48, 64, 80, 96, 128, 160, 192, 256, 384, 512]


def tb(infl):
    sub = 'obj_s3' if infl == 4 else 'obj_s3_i%d' % infl
    return os.path.join(ROOT, 'sim', 'zsg2', 'work', sub, 'tb')


def run(infl, ev, fl, lat):
    out = subprocess.run(['nice', '-n', '15', tb(infl), ev, fl, '--lat', str(lat)],
                         capture_output=True, text=True).stdout
    bad = int(re.search(r'mismatching (\d+)', out).group(1))
    m = re.search(r'longest pass (\d+) clocks, late (\d), overrun (\d)', out)
    return bad, int(m.group(1)), int(m.group(2)), int(m.group(3))


def main():
    burst, stag, fl = sys.argv[1:4]
    print('case infl lat mismatching longest_pass late overrun')
    for name, ev in (('stagger', stag), ('burst', burst)):
        for infl in (1, 2, 4, 8):
            for lat in LATS:
                r = run(infl, ev, fl, lat)
                print(name, infl, lat, *r, flush=True)
                if r[1] > 2 * 1040:
                    break


if __name__ == '__main__':
    main()
