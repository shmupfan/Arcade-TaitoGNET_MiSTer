#!/usr/bin/env python3
"""Check every CAT702 byte of a system simulation against the reference
model (tools/gnet/cat702_ref.py, MAME 0.288 algorithm): the selects come
from znsecsel writes in zn.log, the bytes from sio.log, merged in time.
This checks the integrated path (memorymux, zn2_board, zn_sio0, CAT702)
also after the BIOS's challenge stops matching MAME's bytes (its later
challenges differ from MAME's, see compare_sio.py).

    check_cat702.py <run dir> <coh3002t.zip>
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "tools", "gnet"))
import cat702_ref  # noqa: E402


def events(run):
    ev = []
    for line in open(os.path.join(run, "zn.log")):
        p = line.split()
        if len(p) >= 5 and p[1] == "'1'" and p[2] == "1FA10300":
            ev.append((int(p[0]), 0, "S", int(p[4], 16) & 0xFF))
    for n, line in enumerate(open(os.path.join(run, "sio.log"))):
        p = line.split()
        if len(p) >= 3:
            if p[1] == "W" and p[2] == "0":
                ev.append((int(p[0]), 1 + n, "T", int(p[3], 16) & 0xFF))
            elif p[1] == "R":
                ev.append((int(p[0]), 1 + n, "R", int(p[2], 16)))
    ev.sort()
    return ev


def main(run, zpath):
    keys = cat702_ref.keys_from_zip(zpath)
    chips = [cat702_ref.Cat702(keys[0]), cat702_ref.Cat702(keys[1])]
    sel, pend, rx_ready = 0x0C, None, False
    ok = bad = other = 0
    for t, _, kind, v in events(run):
        if kind == "S":
            sel = v
            for n in range(2):
                chips[n].write_select((sel >> (2 + n)) & 1)
        elif kind == "T":
            pend, rx_ready = v, False
            sel_n = [n for n in range(2) if not chips[n].select]
            mcu = (sel & 0x8C) == 0x8C
            exp = None
            outs = [chips[n].byte(v) for n in sel_n]
            if not mcu and len(sel_n) == 1:
                exp = outs[0]
            pend = (v, exp)
        elif kind == "R" and pend is not None:
            if rx_ready:
                tx, exp = pend
                if exp is None:
                    other += 1
                elif (v & 0xFF) == exp:
                    ok += 1
                else:
                    bad += 1
                    if bad <= 5:
                        print(f"{t} us tx {tx:02x} core rx {v & 0xFF:02x} model {exp:02x}")
                pend, rx_ready = None, False
            elif v & 0x2:
                rx_ready = True
    print(f"CAT702 bytes checked {ok + bad}: match {ok}, mismatch {bad}; other bytes (znmcu) {other}")
    return bad == 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(0 if main(*sys.argv[1:]) else 1)
