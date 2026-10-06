#!/bin/bash
# Run several lockstep testbench builds one after another on one recorded
# stream (sim/zoomboard/record_oracle.sh) and print their summary lines:
#   sim/zoomboard/run_builds.sh <set> <dir with trace.gz> <obj dir> ...
# Logs: <dir>/tb_<basename of obj dir>.log. ZB_* variables pass through.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; D=$2; shift 2
for o in "$@"; do
  "$HERE/run_recorded.sh" "$o" "$SET" "$D/trace.gz" "$D/tb_$(basename "$o").log" > /dev/null
done
for o in "$@"; do
  echo "== $(basename "$o")"
  grep -E "^instructions equal|^external|^ZSG-2 output|^clocks|^TMS57002 host|^TMS57002 CMEM|^board flags|^output stage|^pacer|^virtual time|SO1 segment: [0-9]{6}" "$D/tb_$(basename "$o").log"
done
