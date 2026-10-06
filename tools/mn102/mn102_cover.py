#!/usr/bin/env python3
"""Read a MAME debugger trace of the MN10200 (lines "PPPPPP: mnemonic ...")
from a file or FIFO and write a PC execution histogram (pc count), so the
trace itself never has to be stored. Usage: mn102_cover.py TRACE OUT.json"""
import collections
import json
import sys

cnt = collections.Counter()
n = 0
with open(sys.argv[1], "r", errors="replace") as f:
    for line in f:
        c = line.find(":")
        if c == 6:
            try:
                cnt[int(line[:6], 16)] += 1
                n += 1
            except ValueError:
                pass
json.dump({"lines": n, "pcs": {f"{k:06x}": v for k, v in sorted(cnt.items())}}, open(sys.argv[2], "w"))
print("lines", n, "distinct pcs", len(cnt))
