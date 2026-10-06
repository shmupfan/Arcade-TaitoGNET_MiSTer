#!/usr/bin/env python3
"""Check tools/zsg2/zsg2_model.py against a MAME trace (events from
zsg2_events.py): every output sample and every read.

  zsg2_model_check.py <events.ev> <flashdir> <shift_b> [max_k]
shift_b: 0 for a MAME 0.288 trace, 3 for a 61c7940 trace.
"""
import sys
from zsg2_model import Zsg2
from zsg2_directed import load_flash


def main():
    ev, fl, sb = sys.argv[1], sys.argv[2], int(sys.argv[3])
    maxk = int(sys.argv[4]) if len(sys.argv) > 4 else None
    m = Zsg2(load_flash(fl), sb)
    outs = {}
    no = nbad = nr = nrbad = 0
    first = None
    for line in open(ev):
        p = line.split()
        if p[0] == 'X':
            m.reset()
        elif p[0] == 'W':
            m.write(int(p[1], 16), int(p[2], 16))
        elif p[0] == 'R':
            nr += 1
            if m.read(int(p[1], 16)) != int(p[2], 16):
                nrbad += 1
        elif p[0] == 'T':
            k = int(p[1])
            if maxk is not None and k > maxk:
                break
            outs = {k: m.render()}
        elif p[0] == 'O':
            k = int(p[1])
            if k in outs:
                no += 1
                if outs[k] != [int(x) for x in p[2:6]]:
                    nbad += 1
                    if first is None:
                        first = (k, outs[k], p[2:6])
    print('model check: samples %d mismatching %d, reads %d mismatching %d, first %r' % (no, nbad, nr, nrbad, first))


if __name__ == '__main__':
    main()
