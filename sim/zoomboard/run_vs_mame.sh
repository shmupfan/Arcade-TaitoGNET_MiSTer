#!/bin/bash
# Board-level check of rtl/zoom/zoom_board.sv against MAME, streamed through a
# FIFO (nothing large on disk): MAME runs <set> for <seconds> with
# tools/zoom/zoom_oracle.lua, the Verilator testbench (sim/zoomboard/tb.cpp)
# reads the stream as it is produced and stops at the first divergence;
# MAME is then stopped.
#
#   sim/zoomboard/run_vs_mame.sh <set> <seconds> <nvram_src_dir> [max_insns]
#
# Needs sim/zoom/flash_<set>/ from tools/build_flash.py and the testbench
# (sim/zoomboard/build.sh). Output in sim/zoom/board_<set>/ (gitignored).
# ZOOM_COIN_AT=<s> passes through to the oracle; MAME=<binary> overrides the
# default 61c7940 build; OBJ=<dir> selects the testbench build; OUT=<dir> the
# output directory; ZB_* variables pass through to the testbench.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SET=$1; SECS=$2; NVSRC=$3; MAX=${4:-0}
OUT=${OUT:-$ROOT/sim/zoom/board_$SET}
mkdir -p "$OUT"
FIFO=$OUT/trace.fifo
rm -f "$FIFO"; mkfifo "$FIFO"
ZOOM_TRACE_OUT=$FIFO "$ROOT/tools/zoom/zoom_oracle.sh" "$SET" "$SECS" "$NVSRC" "$OUT" > "$OUT/oracle.log" 2>&1 &
ORA=$!
if [ "$MAX" = 0 ]; then MAX=$((1 << 62)); fi
nice -n 15 "$ROOT/${OBJ:-sim/zoom/obj_board_h4_c1024_t1}/tb" "$ROOT/sim/zoom/flash_$SET" "$FIFO" "$MAX" 10000000 2>&1 | tee "$OUT/tb.log"
rc=${PIPESTATUS[0]}
# stop MAME if the testbench stopped first (it would block on the FIFO)
for p in $(pgrep -P "$ORA"); do pkill -P "$p" 2>/dev/null; done
pkill -P "$ORA" 2>/dev/null
exec 3<>"$FIFO"; exec 3>&-
wait "$ORA" 2>/dev/null
rm -f "$FIFO"
echo "tb rc $rc"
exit $rc
