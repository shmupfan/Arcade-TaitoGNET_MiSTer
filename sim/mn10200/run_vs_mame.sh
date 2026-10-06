#!/bin/bash
# Lockstep check of rtl/zoom/mn10200 against MAME 0.288, streamed through a
# FIFO (no trace on disk): MAME runs <set> for <seconds> with
# tools/mn102/mn102_oracle.lua, the Verilator testbench reads the trace as
# it is produced and stops at the first divergence; MAME is then stopped.
#
#   sim/mn10200/run_vs_mame.sh <set> <seconds> <nvram_src_dir> [max_insns]
#
# Needs sim/flash/<set>/zoomprog (tools/build_flash.py) and the testbench
# (sim/mn10200/build.sh). Output in sim/zoom/run_<set>/ (gitignored).
# MN102_COIN_AT=<s> passes through to the oracle (coin, start, fire, moves).
# ZOOMPROG=<file> overrides the program image (directed tests); OBJ=<dir>
# selects the testbench build; OUT=<dir> the output directory.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SET=$1; SECS=$2; NVSRC=$3; MAX=${4:-0}
OUT=${OUT:-$ROOT/sim/zoom/run_$SET}
mkdir -p "$OUT"
FIFO=$OUT/trace.fifo
rm -f "$FIFO"; mkfifo "$FIFO"
MN102_TRACE_OUT=$FIFO "$ROOT/tools/mn102/mn102_oracle.sh" "$SET" "$SECS" "$NVSRC" "$OUT" > "$OUT/oracle.log" 2>&1 &
ORA=$!
if [ "$MAX" = 0 ]; then MAX=$((1 << 62)); fi
nice -n 15 "$ROOT/${OBJ:-sim/zoom/obj}/tb" "${ZOOMPROG:-$ROOT/sim/flash/$SET/zoomprog}" "$FIFO" "$MAX" 10000000 2>&1 | tee "$OUT/tb.log"
rc=${PIPESTATUS[0]}
# stop MAME if the testbench stopped first (it would block on the FIFO)
pkill -P "$ORA" -x mame 2>/dev/null
for p in $(pgrep -P "$ORA"); do pkill -P "$p" -x mame 2>/dev/null; done
exec 3<>"$FIFO"; exec 3>&-
wait "$ORA" 2>/dev/null
rm -f "$FIFO"
echo "tb rc $rc"
exit $rc
