#!/bin/bash
# MN10200 instruction-trace oracle: run MAME 0.288 with mn102_oracle.lua and
# write trace.log (per-instruction state and external accesses), or stream
# it to MN102_TRACE_OUT (a FIFO, see sim/mn10200/run_vs_mame.sh).
#
#   tools/mn102/mn102_oracle.sh <set> <seconds> <nvram_src_dir> <outdir>
#
# nvram_src_dir holds an NVRAM set (firm, wave0..2, zoomprog, at28c16), for
# example sim/r18/nv_<set>/<set>. outdir must be gitignored (sim/zoom/...):
# everything in it is game-derived. Runs under nice -n 15 and refuses to
# start when 3 MAME processes run on the machine. Run one oracle at a time.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "mn102_oracle: $running MAME processes running (limit 3), refusing" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
cp "$NVSRC"/* "$OUT/nvram/$SET/"
export MN102_TRACE="${MN102_TRACE_OUT:-$OUT/trace.log}" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
set +e
nice -n 15 mame "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" -debug -debugger none \
  -autoboot_script "$HERE/mn102_oracle.lua" > "$OUT/mame.log" 2>&1
rc=$?
set -e
echo "mame rc $rc"
