#!/bin/bash
# R1 clock sweep: run the patched MAME (env ZN2_CPU_HZ, docs/r1_speed_study.md
# section 6.1) at several CXD8661R input clocks from the same post-copy
# MB2011 NVRAM. At most 3 MAME processes at once (stock "mame" plus patched
# "gnet", across all sessions); each run under nice -n 15 via r1_run.sh.
#   MAME=/path/to/gnet tools/r1/r1_sweep.sh <seconds> <nvram_src> <outroot> <hz> [hz ...]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SECS=$1; SRC=$2; ROOT=$3; shift 3
: "${MAME:?set MAME to the patched binary}"
mkdir -p "$ROOT"
count() { echo $(( $( (pgrep -x mame || true) | wc -l) + $( (pgrep -x gnet || true) | wc -l) )); }
for hz in "$@"; do
  while [ "$(count)" -ge 3 ]; do sleep 5; done
  ZN2_CPU_HZ=$hz "$HERE/r1_run.sh" raycris "$SECS" "$SRC" "$ROOT/hz_$hz" > "$ROOT/hz_$hz.out" 2>&1 &
  sleep 5
done
wait
for hz in "$@"; do echo "$hz $(cat "$ROOT/hz_$hz.out")"; done
