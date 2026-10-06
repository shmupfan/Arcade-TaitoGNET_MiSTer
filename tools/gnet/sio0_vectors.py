#!/usr/bin/env python3
"""Vectors for the SIO0 replay testbench (sim/zn2/tb_sio0_replay.vhd) from
an M0 oracle sec.log (tools/mame/oracle.lua): every main-CPU access to SIO0
(0x1F801040-0x1F80104F) and every znsecsel write (0x1FA10300), at its
emulated time converted to 33.8688 MHz cycles.

  sio0_vectors.py <sec.log> <out.vec> [max_seconds]

Line format: "<delta> S <value hex>" for znsecsel, "<delta> R|W <offset hex>
<byte mask bin, lane 3..0> <data hex>" for SIO0, where delta is the number
of cycles since the previous event (absolute cycle counts pass 2^31 after
63 s). A gap of more than 10^8 cycles (about 3 s) without SIO0 or znsecsel
traffic is shortened to 101,000 cycles (3 ms), written as a "100000 N" line
(no access) and a delta of 1,000: every timer in the models (znmcu: 50 us)
has run out long before, so nothing in the RTL changes during the skipped
cycles and the replay of a 300 s run stays short.
A folded run of identical
reads ("xN tlast") is replayed as its first and last read; status reads have
no side effects. Output is game-derived (sim/, gitignored).
"""
import sys

F = 33868800


def main(log, out, max_s=None):
    n = 0
    prev = 0
    with open(out, "w") as f:
        for line in open(log):
            p = line.split()
            if len(p) < 6:
                continue
            t = float(p[0])
            if max_s is not None and t > max_s:
                break
            d, a, v, m = p[2], int(p[3], 16), int(p[4], 16), int(p[5], 16)
            times = [t]
            if len(p) >= 8 and p[6].startswith("x"):
                times.append(float(p[7]))
            for tt in times:
                c = round(tt * F)
                if c - prev > 100000000:
                    f.write("100000 N\n")
                    prev = c - 1000
                if a == 0x1FA10300:
                    if d == "W":
                        f.write(f"{c - prev} S {v & 0xFF:02x}\n")
                        prev = c
                        n += 1
                elif 0x1F801040 <= a <= 0x1F80104F:
                    be = "".join("1" if (m >> (8 * i)) & 0xFF else "0" for i in (3, 2, 1, 0))
                    f.write(f"{c - prev} {d} {a & 0xC:x} {be} {v:08x}\n")
                    prev = c
                    n += 1
    print(f"{n} events")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else None)
