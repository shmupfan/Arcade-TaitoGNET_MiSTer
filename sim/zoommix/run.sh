#!/bin/bash
# zoom_mix bench (SFX level, saturation), Verilator, nice -n 15.
set -euo pipefail
cd "$(dirname "$0")"
nice -n 15 verilator --cc --exe --build -O2 -Wall -Wno-fatal -j 2 --top-module zoom_mix -Mdir obj_dir \
  ../../rtl/zoom/zoom_mix.sv tb.cpp -o tb > obj_dir.log 2>&1 || { tail -30 obj_dir.log; exit 1; }
grep -c '%Warning' obj_dir.log | sed 's/^/verilator -Wall warnings: /'
nice -n 15 ./obj_dir/tb
