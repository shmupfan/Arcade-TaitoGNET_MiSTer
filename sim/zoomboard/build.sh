#!/bin/bash
# Build the Zoom board Verilator testbench into sim/zoom/obj_board (gitignored).
#   sim/zoomboard/build.sh        (OBJ=<dir>, VFLAGS=<extra -G parameters>, CLKH, CAP, TMSMAME)
# Verification parameters: MAME timer phase, the debug cycle counter, and
# MAME's 32,552 Hz sample period (192 + 16/32552 cycles, zoom_tbase.sv)
# with the output stage read at the same 32,552 Hz.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
# CLKH (2: one clock, 4: MN10200 side on clk_2x, default 4), CAP (pacer
# cap, default 1024) and TMSMAME (TMS57002 MAME parameter set, default 1 for
# oracle runs) set the build.
CLKH=${CLKH:-4}; CAP=${CAP:-1024}; TMSMAME=${TMSMAME:-1}
OBJ=${OBJ:-sim/zoom/obj_board_h${CLKH}_c${CAP}_t${TMSMAME}}
mkdir -p "$OBJ"
nice -n 15 verilator --cc --exe --build -j 4 -O2 --top-module zoom_board \
  -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM -Wno-MULTIDRIVEN \
  --x-assign 0 --x-initial 0 --public-flat-rw --Mdir "$OBJ" -o tb \
  -GTIMER_EXACT=1 -GDEBUG=1 -GTB_REM_ADD=16 -GTB_REM_MOD=32552 -GOUT_ADD=4069 -GOUT_MOD=4233600 \
  -GCLK_H=$CLKH -GPACE_CAP=$CAP -GTMS_MAME=$TMSMAME -CFLAGS "-DZB_CLK_H=$CLKH -DZB_CAP_DEFAULT=$CAP" ${VFLAGS:-} \
  -f sim/zoomboard/files.lst sim/zoomboard/tb.cpp
echo "built $OBJ/tb"
