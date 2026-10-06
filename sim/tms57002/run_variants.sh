#!/bin/bash
# Replay one log through several testbench builds, two at a time, and
# print the summary line of each.
#   sim/tms57002/run_variants.sh <tms57.log> <outprefix> <name>...
# Each <name> must have been built with sim/tms57002/build.sh <name> ...;
# the full reports go to <outprefix>.<name>.txt.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
LOG=$1; OUT=$2; shift 2
run() { nice -n 15 "$ROOT/sim/zoom/obj_tms57_$1/tb" "$LOG" --quiet > "$OUT.$1.txt" 2>&1 || true; }
names=("$@")
i=0
while [ $i -lt ${#names[@]} ]; do
  run "${names[$i]}" &
  if [ $((i + 1)) -lt ${#names[@]} ]; then run "${names[$((i + 1))]}" & fi
  wait
  i=$((i + 2))
done
for n in "${names[@]}"; do
  echo "== $n"
  grep -E "first output|SO1 24-bit|compared samples|samples compared" "$OUT.$n.txt" || true
done
