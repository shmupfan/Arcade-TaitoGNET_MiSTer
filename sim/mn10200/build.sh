#!/bin/bash
# Build the MN10200 Verilator testbench into sim/zoom/obj (gitignored).
#   sim/mn10200/build.sh   (OBJ=<dir> build directory, VFLAGS=-GTIMER_EXACT=0 etc.)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OBJ=${OBJ:-sim/zoom/obj}
mkdir -p "$OBJ"
nice -n 15 verilator --cc --exe --build -j 4 -O2 --top-module mn10200 \
  -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --public-flat-rw --Mdir "$OBJ" -o tb ${VFLAGS:--GTIMER_EXACT=1} \
  rtl/zoom/mn10200_decode.sv rtl/zoom/mn10200_rf.sv rtl/zoom/mn10200_core.sv rtl/zoom/mn10200_periph.sv rtl/zoom/mn10200.sv \
  sim/mn10200/tb.cpp
echo "built $OBJ/tb"
