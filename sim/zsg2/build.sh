#!/bin/bash
# Build the ZSG-2 Verilator testbench into sim/zsg2/work/obj (gitignored).
#   sim/zsg2/build.sh            (READB_SHIFT 3, the core's default)
#   SHIFT=0 sim/zsg2/build.sh    (MAME 0.288 register 0xB rule)
#   COVER=1 sim/zsg2/build.sh    (also count datapath cases, sim/zsg2/tb.cpp)
#   INFL=8 sim/zsg2/build.sh     (memory requests outstanding, default 4)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
SHIFT=${SHIFT:-3}
INFL=${INFL:-4}
COVER=${COVER:-0}
if [ "$COVER" = 1 ]; then
  OBJ=${OBJ:-sim/zsg2/work/obj_cov_s$SHIFT}; EXTRA=(--public-flat-rw -CFLAGS -DZSG2_COVER)
else
  OBJ=${OBJ:-sim/zsg2/work/obj_s$SHIFT}; EXTRA=()
  if [ "$INFL" != 4 ]; then OBJ=sim/zsg2/work/obj_s${SHIFT}_i$INFL; fi
fi
mkdir -p "$OBJ"
nice -n 15 verilator --cc --exe --build -j 4 -O2 --top-module zsg2 \
  -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --x-assign 0 --x-initial 0 -GREADB_SHIFT=$SHIFT -GINFL=$INFL ${EXTRA[@]+"${EXTRA[@]}"} --Mdir "$OBJ" -o tb \
  rtl/zoom/zsg2_ram.sv rtl/zoom/zsg2_fetch.sv rtl/zoom/zsg2.sv sim/zsg2/tb.cpp
echo "built $OBJ/tb"
