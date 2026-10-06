#!/bin/bash
# Trace the Taito Zoom MN10200 under MAME 0.288: PC histogram (debugger
# trace streamed through a FIFO into mn102_cover.py, never stored) plus the
# I/O log from mn102_trace.lua. MAME must be 0.288 on PATH.
#
#   tools/mn102/mn102_trace.sh <set> <seconds> <nvram_src_dir> <outdir>
#
# nvram_src_dir holds a post-copy NVRAM set (firm, wave0..2, zoomprog,
# at28c16), e.g. ../gnet-mister/sim/r18/nv_<set>/<set>. outdir must be
# outside the repository or gitignored: everything in it is game-derived.
# Runs under nice -n 15 and refuses to start when 3 MAME processes run.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "mn102_trace: $running MAME processes running (limit 3)" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"; mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
cp "$NVSRC"/* "$OUT/nvram/$SET/"
FIFO="$OUT/trace.fifo"; rm -f "$FIFO"
if [ -z "${MN102_TRACE_FILE:-}" ]; then
  # stream the trace through a FIFO; after MAME exits the reader is unblocked below
  mkfifo "$FIFO"
  python3 "$HERE/mn102_cover.py" "$FIFO" "$OUT/pcs.json" > "$OUT/cover.txt" &
  COV=$!
fi
export MN102_OUT="$OUT/io.log" MN102_TRACE="${MN102_TRACE_FILE:-$FIFO}" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
set +e
nice -n 15 mame "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" -debug -debugger none \
  -autoboot_script "$HERE/mn102_trace.lua" > "$OUT/mame.log" 2>&1
rc=$?
set -e
if [ -z "${MN102_TRACE_FILE:-}" ]; then
  [ -p "$FIFO" ] && { exec 3<>"$FIFO"; exec 3>&-; } # unblock the reader if MAME never opened it
  wait $COV
  rm -f "$FIFO"
else
  python3 "$HERE/mn102_cover.py" "$MN102_TRACE_FILE" "$OUT/pcs.json" > "$OUT/cover.txt"
fi
echo "mame rc $rc"; cat "$OUT/cover.txt"
