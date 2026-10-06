#!/bin/bash
# Record a MAME Zoom oracle stream (tools/zoom/zoom_oracle.sh) compressed to
# <outdir>/trace.gz, so the lockstep testbench can run afterwards instead of
# beside MAME (one simulation process at a time):
#   sim/zoomboard/record_oracle.sh <set> <seconds> <nvram_src_dir> <outdir>
#   then: <tb> <flashdir> <(gzip -dc <outdir>/trace.gz) ...
# outdir must be gitignored (sim/zoom/...): the stream is game-derived.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
FIFO=$OUT/trace.fifo
rm -f "$FIFO"; mkfifo "$FIFO"
gzip -1 < "$FIFO" > "$OUT/trace.gz" &
GZ=$!
ZOOM_TRACE_OUT=$FIFO "$ROOT/tools/zoom/zoom_oracle.sh" "$SET" "$SECS" "$NVSRC" "$OUT" > "$OUT/oracle.log" 2>&1 || true
wait "$GZ"
rm -f "$FIFO"
ls -l "$OUT/trace.gz"
tail -3 "$OUT/oracle.log"
