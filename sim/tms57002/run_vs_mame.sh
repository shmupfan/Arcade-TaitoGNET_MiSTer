#!/bin/bash
# Replay a tools/tms57/tms57_trace.sh log through the TMS57002 testbench.
#   sim/tms57002/run_vs_mame.sh <guide|mame> <tms57.log> [tb options]
# Builds the testbench if needed; the report goes to stdout. Runs under
# nice -n 15; keep at most 2 of these running at once.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CFG=$1; LOG=$2; shift 2
TB=$ROOT/sim/zoom/obj_tms57_$CFG/tb
[ -x "$TB" ] || "$ROOT/sim/tms57002/build.sh" "$CFG" > /dev/null
exec nice -n 15 "$TB" "$LOG" "$@"
