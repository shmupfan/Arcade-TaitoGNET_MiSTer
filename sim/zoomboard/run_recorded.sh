#!/bin/bash
# Run a lockstep testbench build on a recorded oracle stream
# (sim/zoomboard/record_oracle.sh):
#   sim/zoomboard/run_recorded.sh <obj dir> <set> <trace.gz> <log> [max_insns]
# ZB_* variables pass through to the testbench. Runs under nice -n 15 from
# the checkout root (the MN10200 decode tables are read from rtl/zoom/).
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OBJ=$1; SET=$2; TR=$3; LOG=$4; MAX=${5:-0}
[ "$MAX" = 0 ] && MAX=$((1 << 62))
cd "$ROOT"
nice -n 15 "$OBJ/tb" "$ROOT/sim/zoom/flash_$SET" <(gzip -dc "$TR") "$MAX" 10000000 > "$LOG" 2>&1
echo "tb rc $?"
tail -40 "$LOG"
