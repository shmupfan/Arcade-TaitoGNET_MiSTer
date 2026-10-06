#!/bin/bash
# Two board builds against one MAME run (the stream is copied to both):
#   sim/zoomboard/run_vs_mame2.sh <set> <seconds> <nvram_src_dir> <objA> <objB>
# Output in sim/zoom/board2_<set>/ (gitignored): tbA.log, tbB.log. ZB_* and
# ZOOM_COIN_AT pass through. MAME waits for the slower testbench.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SET=$1; SECS=$2; NVSRC=$3; OA=$4; OB=$5
OUT=${OUT:-$ROOT/sim/zoom/board2_$SET}
mkdir -p "$OUT"
FIFO=$OUT/trace.fifo; FA=$OUT/a.fifo; FB=$OUT/b.fifo
rm -f "$FIFO" "$FA" "$FB"; mkfifo "$FIFO" "$FA" "$FB"
ZOOM_TRACE_OUT=$FIFO "$ROOT/tools/zoom/zoom_oracle.sh" "$SET" "$SECS" "$NVSRC" "$OUT" > "$OUT/oracle.log" 2>&1 &
ORA=$!
nice -n 15 "$ROOT/$OA/tb" "$ROOT/sim/zoom/flash_$SET" "$FA" $((1 << 62)) 10000000 > "$OUT/tbA.log" 2>&1 &
TA=$!
nice -n 15 "$ROOT/$OB/tb" "$ROOT/sim/zoom/flash_$SET" "$FB" $((1 << 62)) 10000000 > "$OUT/tbB.log" 2>&1 &
TB=$!
tee "$FA" < "$FIFO" > "$FB"
wait $TA; ra=$?
wait $TB; rb=$?
wait "$ORA" 2>/dev/null
rm -f "$FIFO" "$FA" "$FB"
echo "tbA rc $ra, tbB rc $rb"
