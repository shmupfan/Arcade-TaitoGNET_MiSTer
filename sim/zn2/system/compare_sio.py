#!/usr/bin/env python3
"""Compare the SIO0 byte exchange of a system simulation (sio.log from
tb_zn2_system) with MAME 0.288's (oracle sec.log): the sequence of
(byte sent, byte received) pairs, which covers both CAT702 and the znmcu.

    compare_sio.py <sio.log> <sec.log>
"""
import sys


def mame_pairs(path):
    pairs, pend = [], None
    for line in open(path):
        p = line.split()
        if len(p) < 6:
            continue
        a, v, m = int(p[3], 16), int(p[4], 16), int(p[5], 16)
        if a == 0x1F801040 and m == 0xFF:
            if p[2] == "W":
                pend = v & 0xFF
            elif pend is not None:
                pairs.append((pend, v & 0xFF))
                pend = None
    return pairs


def core_pairs2(path):
    """Pair each TX byte with the next data-register read. The testbench log
    writes 'R <data>' without the address; a data read follows a status read
    with RX ready (bit 1) set, so the read after the first status value with
    bit 1 set is the data read."""
    pairs, pend, rx_ready = [], None, False
    for line in open(path):
        p = line.split()
        if len(p) < 3:
            continue
        if p[1] == "W":
            if p[2] == "0":
                pend = int(p[3], 16) & 0xFF
                rx_ready = False
        else:
            v = int(p[2], 16)
            if pend is None:
                continue
            if rx_ready:
                pairs.append((pend, v & 0xFF))
                pend = None
                rx_ready = False
            elif v & 0x2:
                rx_ready = True
    return pairs


def main(core, mame):
    c = core_pairs2(core)
    m = mame_pairs(mame)
    n = min(len(c), len(m))
    first_bad = next((i for i in range(n) if c[i] != m[i]), None)
    print(f"core pairs {len(c)}, MAME pairs {len(m)}, compared {n}, "
          f"first difference {'none' if first_bad is None else first_bad}")
    if first_bad is not None:
        for i in range(max(0, first_bad - 3), min(n, first_bad + 5)):
            print(i, "core %02x %02x" % c[i], "MAME %02x %02x" % m[i])
    return first_bad is None


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(0 if main(sys.argv[1], sys.argv[2]) else 1)
