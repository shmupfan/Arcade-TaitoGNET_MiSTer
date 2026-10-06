#!/usr/bin/env python3
"""Summarise sim/cdc/work/results.txt (RESULT lines of sim/cdc/run.sh all).

Prints, per block and clock pair (source -> destination), the number of
runs, transfers, errors, and the latency range over all seeds, separately
for the plain model (meta 0) and the late-resolving synchroniser model
(meta 1).
"""
import re
import sys
from collections import defaultdict

MHZ = {20000000: "50", 10000000: "100", 29525699: "33.8688",
       14762850: "67.7376", 18624341: "53.693175"}

path = sys.argv[1] if len(sys.argv) > 1 else "sim/cdc/work/results.txt"
rows = defaultdict(lambda: {"runs": 0, "n": 0, "err": 0, "lat": {}})
total = defaultdict(int)
for line in open(path):
    if not line.startswith("RESULT"):
        continue
    kv = dict(re.findall(r"(\w+)=(\S+)", line))
    block = line.split()[1]
    if block == "pulse":
        block += "_w%s_m%s" % (kv["cnt_w"], kv["mode"])
    if block == "fifo":
        block += "_fwft%s_d%s" % (kv["fwft"], kv["depth"])
    if kv.get("stages", "2") != "2":
        block += "_s%s" % kv["stages"]
    if block == "tick_accum":
        print(line.strip())
        continue
    pair = "%s->%s" % (MHZ[int(kv["PA"])], MHZ[int(kv["PB"])])
    key = (block, pair, kv["meta"])
    r = rows[key]
    r["runs"] += 1
    n = int(kv.get("updates", kv.get("n", 0)))
    r["n"] += n
    total[block] += n
    r["err"] += int(kv["errors"])
    for f, v in kv.items():
        if f.startswith(("lat", "req_lat", "ack_lat", "roundtrip")) and ".." in v:
            lo, hi = (float(x) for x in v.split(".."))
            a, b = r["lat"].get(f, (lo, hi))
            r["lat"][f] = (min(a, lo), max(b, hi))

for key in sorted(rows):
    r = rows[key]
    lat = " ".join("%s=%g..%g" % (f, a, b) for f, (a, b) in sorted(r["lat"].items()))
    print("%-16s %-20s meta=%s runs=%d n=%d errors=%d %s" % (key + (r["runs"], r["n"], r["err"], lat)))
print()
for b, n in sorted(total.items()):
    print("total transfers %-16s %d" % (b, n))
