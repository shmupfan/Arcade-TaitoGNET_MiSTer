#!/bin/bash
# Build and run the zoom_line32 test with read-DQM masking (tb_line32.cpp):
# the normal run must pass, the self-test (partial read mask forced in the
# model) must fail, which shows the model catches the case.
#   sim/zoomboard/build_line32.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OBJ=sim/zoom/obj_line32
mkdir -p "$OBJ"
nice -n 15 verilator --cc --exe --build -j 2 -O1 --top-module zoom_line32 \
  -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --x-assign 0 --x-initial 0 \
  --Mdir "$OBJ" -o tb rtl/zoom/zoom_line32.sv sim/zoomboard/tb_line32.cpp > "$OBJ/build.log" 2>&1
"$OBJ/tb"
"$OBJ/tb" --selftest
