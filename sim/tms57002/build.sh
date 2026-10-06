#!/bin/bash
# Build the TMS57002 Verilator replay testbench into sim/zoom/obj_tms57_<name>
# (gitignored).
#   sim/tms57002/build.sh <name> [-G<param>=<value> ...]
# Presets:
#   guide  the RTL defaults (TMS57002 User's Guide behaviour)
#   mame   the parameters that reproduce MAME 0.288 where it differs from the
#          guide: XM_CYCLES=2 XM_COUNT_IDLE=0 UPD_AFTER_CLOAD=0 MPY_A32=1
#          SI_RAW=1 (the bit-exact replay)
# Any other name starts from the mame preset and applies the -G overrides,
# e.g. "sim/tms57002/build.sh mame_mpy24 -GMPY_A32=0" isolates one guide
# difference.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
NAME=${1:-guide}
shift || true
MAMEG=(-GXM_CYCLES=2 -GXM_COUNT_IDLE=0 -GUPD_AFTER_CLOAD=0 -GMPY_A32=1 -GSI_RAW=1)
case "$NAME" in
  guide) G=(-GSI_RAW=0 "$@") ;;
  *)     G=("${MAMEG[@]}" "$@") ;;
esac
OBJ=sim/zoom/obj_tms57_$NAME
mkdir -p "$OBJ"
nice -n 15 verilator --cc --exe --build -j 4 -O2 --top-module tms57002 "${G[@]}" \
  -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
  --public-flat-rw --Mdir "$OBJ" -o tb \
  rtl/zoom/tms57002.sv sim/tms57002/tb.cpp
echo "built $OBJ/tb"
