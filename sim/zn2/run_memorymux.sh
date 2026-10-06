#!/bin/bash
# memorymux ZN2_MAP tests with NVC (docs/zn2_layer_design.md 16).
#   sim/zn2/run_memorymux.sh eq [N] [SEED] [BVAR]  ZN2_MAP = 0 against upstream (main);
#                                            BVAR=2 compares ZN2_MAP = 1 instead (must fail)
#   sim/zn2/run_memorymux.sh zn [SEED] [OVERLAP]  ZN2_MAP = 1 directed bus tests
#                                            (OVERLAP: ZN2_READ_OVERLAP, default 0)
#   sim/zn2/run_memorymux.sh prev [N] [SEED] [OVERLAP] [ALLOW_WADDR]  the
#                                            previous ZN-2 memorymux (PREV_REF)
#                                            against this one, both ZN2_MAP = 1,
#                                            every output and the zn_* port each
#                                            clock. ALLOW_WADDR 1 (default): only the
#                                            posted-write address fix may differ
#                                            (counted); OVERLAP 1 must fail
#   sim/zn2/run_memorymux.sh ovl [N] [SEED] [OVERLAP]  transaction check, the
#                                            previous memorymux against this one with
#                                            ZN2_READ_OVERLAP (default 1): read data
#                                            and device request sequence
#   sim/zn2/run_memorymux.sh lat [LATS] [OVERLAPS]  read latency rows per fixed
#                                            device latency (default "2 4 6 8 10 12
#                                            14 16 18 20 22") and overlap ("0 1"),
#                                            into work/memorymux/lat_all.txt
# PREV_REF (default 3a3fefa, the last change to rtl/memorymux.vhd before
# ZN2_READ_OVERLAP) gives memorymux_prev.
# The upstream memorymux is taken from branch main (equal to upstream/main),
# renamed memorymux_up, into sim/zn2/work/ (gitignored).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W=$HERE/work/memorymux
mkdir -p "$W"
cd "$W"
git -C "$ROOT" show main:rtl/memorymux.vhd \
  | sed -e 's/^entity memorymux is/entity memorymux_up is/' -e 's/^architecture arch of memorymux is/architecture arch of memorymux_up is/' \
  > memorymux_up.vhd
git -C "$ROOT" show "${PREV_REF:-3a3fefa}":rtl/memorymux.vhd \
  | sed -e 's/^entity memorymux is/entity memorymux_prev is/' -e 's/^architecture arch of memorymux is/architecture arch of memorymux_prev is/' \
  > memorymux_prev.vhd
NV="nvc --std=2008"
$NV --work=mem -a --relaxed "$ROOT/rtl/SyncFifoFallThroughMLAB.vhd" "$ROOT/sim/system/src/mem/RamMLAB.vhd" 2>/dev/null || \
  $NV --work=mem -a --relaxed "$ROOT/sim/system/src/mem/RamMLAB.vhd" "$ROOT/rtl/SyncFifoFallThroughMLAB.vhd"
$NV --work=work -L . -a --relaxed memorymux_up.vhd memorymux_prev.vhd "$ROOT/rtl/memorymux.vhd" "$HERE/mm_harness.vhd" \
  "$HERE/tb_memorymux_eq.vhd" "$HERE/tb_memorymux_zn.vhd" "$HERE/tb_memorymux_ovl.vhd" "$HERE/tb_memorymux_lat.vhd"
case "${1:-eq}" in
  eq) $NV -L . -e tb_memorymux_eq -gN="${2:-20000}" -gSEED="${3:-1}" -gBVAR="${4:-1}"
      nice -n 15 $NV -L . -r tb_memorymux_eq --ieee-warnings=off ;;
  zn) $NV -L . -e tb_memorymux_zn -gSEED="${2:-1}" -gOVERLAP="${3:-0}"
      nice -n 15 $NV -L . -r tb_memorymux_zn --ieee-warnings=off ;;
  prev) $NV -L . -e tb_memorymux_eq -gN="${2:-20000}" -gSEED="${3:-1}" -gAVAR=3 -gBVAR=2 -gOVERLAP="${4:-0}" -gALLOW_WADDR="${5:-1}"
      nice -n 15 $NV -L . -r tb_memorymux_eq --ieee-warnings=off ;;
  ovl) $NV -L . -e tb_memorymux_ovl -gN="${2:-20000}" -gSEED="${3:-1}" -gOVERLAP="${4:-1}"
      nice -n 15 $NV -L . -r tb_memorymux_ovl --ieee-warnings=off ;;
  lat) : > lat_all.txt
      for o in ${3:-0 1}; do
        for l in ${2:-2 4 6 8 10 12 14 16 18 20 22}; do
          $NV -L . -e tb_memorymux_lat -gOVERLAP=$o -gLAT=$l -gOUTFILE="$W/lat_o${o}_l${l}.txt"
          nice -n 15 $NV -L . -r tb_memorymux_lat --ieee-warnings=off > /dev/null
          cat "$W/lat_o${o}_l${l}.txt" >> lat_all.txt
        done
      done
      cat lat_all.txt ;;
esac
