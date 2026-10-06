#!/bin/bash
# Build and run the zoom_host / mailbox directed test for both volume laws.
#   sim/zoomboard/build_host.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
for G in 0 1; do
  OBJ=sim/zoom/obj_host_g$G
  mkdir -p "$OBJ"
  nice -n 15 verilator --cc --exe --build -j 2 -O1 --top-module zoom_host_tb \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-MULTIDRIVEN \
    --x-assign 0 --x-initial 0 -GMAME_GAIN=$G --Mdir "$OBJ" -o tb \
    rtl/zoom/zoom_host.sv rtl/zoom/zoom_mbox.sv sim/zoomboard/zoom_host_tb.sv sim/zoomboard/tb_host.cpp > "$OBJ/build.log" 2>&1
  "$OBJ/tb" $G
done
