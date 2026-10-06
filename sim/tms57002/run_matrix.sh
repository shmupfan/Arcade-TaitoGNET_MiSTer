#!/bin/bash
# Build every testbench variant and replay each given log through all of
# them (stepped), plus the mame build with --freerun. Two simulations at a
# time, nice -n 15. Reports: <log dir>/../<set>.<variant>.txt
#   sim/tms57002/run_matrix.sh <tms57.log>...
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
B=$ROOT/sim/tms57002/build.sh
"$B" mame > /dev/null
"$B" guide > /dev/null
"$B" m_mpy24 -GMPY_A32=0 > /dev/null
"$B" m_upd -GUPD_AFTER_CLOAD=1 > /dev/null
"$B" m_xm6 -GXM_CYCLES=6 -GXM_COUNT_IDLE=1 > /dev/null
"$B" m_si16 -GSI_RAW=0 > /dev/null
jobs=()
for log in "$@"; do
  set_dir=$(cd "$(dirname "$log")" && pwd)
  pre="$(dirname "$set_dir")/$(basename "$set_dir")"
  for v in mame guide m_mpy24 m_upd m_xm6 m_si16; do jobs+=("$v|$log|$pre.$v.txt|"); done
  jobs+=("mame|$log|$pre.mame_free.txt|--freerun")
done
run() {
  IFS='|' read -r v log out opt <<< "$1"
  nice -n 15 "$ROOT/sim/zoom/obj_tms57_$v/tb" "$log" --quiet $opt > "$out" 2>&1 || true
}
i=0
while [ $i -lt ${#jobs[@]} ]; do
  run "${jobs[$i]}" &
  if [ $((i + 1)) -lt ${#jobs[@]} ]; then run "${jobs[$((i + 1))]}" & fi
  wait
  i=$((i + 2))
done
for j in "${jobs[@]}"; do
  IFS='|' read -r v log out opt <<< "$j"
  echo "== $(basename "$out")"
  grep -E "first output|SO1 24-bit|compared samples|samples compared|free-running|periodic|resync" "$out" || true
done
