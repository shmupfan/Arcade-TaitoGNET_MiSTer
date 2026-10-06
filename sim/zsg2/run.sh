#!/bin/bash
# One ZSG-2 replay under nice: sim/zsg2/run.sh <shift> <events> <flashdir> <log> [tb options]
# (build first with SHIFT=<shift> sim/zsg2/build.sh; <shift> = cov3 runs the
# COVER=1 build of READB_SHIFT 3, i<N> the INFL=<N> build)
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
S=$1; EV=$2; FL=$3; LOG=$4; shift 4
case "$S" in i*) BIN="$ROOT/sim/zsg2/work/obj_s3_$S/tb" ;; cov*) BIN="$ROOT/sim/zsg2/work/obj_cov_s${S#cov}/tb" ;; *) BIN="$ROOT/sim/zsg2/work/obj_s$S/tb" ;; esac
nice -n 15 "$BIN" "$EV" "$FL" "$@" > "$LOG" 2>&1
echo "rc $?" >> "$LOG"
tail -6 "$LOG"
