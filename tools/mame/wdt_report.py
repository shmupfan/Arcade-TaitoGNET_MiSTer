#!/usr/bin/env python3
"""Summarise tools/mame/wdt_survey.sh output: per run the longest intervals
without a watchdog kick (MB3773 ck falling edge), with the PC of the kick
that opened the interval and of the kick that closed it.

  tools/mame/wdt_report.py <survey dir> [--top 3]

Cycles: MAME's ZN-2 CPU (CXD8661R, 100 MHz device clock) executes one
instruction per 4 clocks (psx.h execute_clocks_to_cycles), 25,000,000 per
emulated second with no wait states; "clk33" and "clk50" are the same
interval in clocks of a 33.8688 MHz and a 50 MHz CPU.
"""
import argparse
import glob
import os


def runs(d):
    for p in sorted(glob.glob(os.path.join(d, "*", "kicks.log"))):
        name = os.path.basename(os.path.dirname(p))
        kicks, end, resets = [], None, []
        for l in open(p):
            f = l.split()
            if f[0] == "END":
                end = (float(f[1]), float(f[2]))
            elif f[0] == "RESET":
                resets.append(float(f[1]))
            else:
                kicks.append((float(f[0]), f[1], float(f[2])))
        yield name, kicks, end, resets


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--top", type=int, default=3)
    a = ap.parse_args()
    print("run\tkicks\tresets\trank\tgap_s\tfrom_t\tfrom_pc\tto_t\tto_pc\tmame_cycles\tclk33\tclk50")
    for name, kicks, end, resets in runs(a.dir):
        gaps = []
        prev_t, prev_pc = 0.0, "reset"
        for t, pc, g in kicks:
            gaps.append((g, t - g, prev_pc, t, pc))
            prev_t, prev_pc = t, pc
        if end:
            gaps.append((end[1], end[0] - end[1], prev_pc, end[0], "END(open)"))
        gaps.sort(reverse=True)
        for i, (g, t0, pc0, t1, pc1) in enumerate(gaps[:a.top]):
            print(f"{name}\t{len(kicks)}\t{len(resets)}\t{i + 1}\t{g:.4f}\t{t0:.4f}\t{pc0}\t{t1:.4f}\t{pc1}\t"
                  f"{g * 25e6:.0f}\t{g * 33.8688e6:.0f}\t{g * 50e6:.0f}")


if __name__ == "__main__":
    main()
