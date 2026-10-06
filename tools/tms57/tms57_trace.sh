#!/bin/bash
# Trace the Taito Zoom TMS57002 under MAME 0.288 with tms57_trace.lua:
# host port bytes with the DSP PC / sample, per-sample serial in/out and
# state snapshots (see the header of tms57_trace.lua).
#
#   tools/tms57/tms57_trace.sh <set> <seconds> <nvram_src_dir> <outdir>
#
# nvram_src_dir holds a post-copy NVRAM set (firm, wave0..2, zoomprog,
# at28c16); a diff/ directory beside it (<nvram_src_dir>/../../diff) is
# copied when present. outdir must be gitignored (sim/zoom/): everything in
# it is game-derived. Runs under nice -n 15 and refuses to start when 3 MAME
# processes run. Env: TMS57_SNAP_EVERY, TMS57_COIN_AT, ROMS, MAME.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
MAME=${MAME:-/opt/homebrew/bin/mame}
running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "tms57_trace: $running MAME processes running (limit 3)" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
cp "$NVSRC"/* "$OUT/nvram/$SET/"
DIFF="$NVSRC/../../diff"
[ -d "$DIFF" ] && cp "$DIFF"/* "$OUT/diff/" 2>/dev/null || true
export TMS57_OUT="$OUT/tms57.log" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
set +e
nice -n 15 "$MAME" "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" \
  -autoboot_script "$HERE/tms57_trace.lua" > "$OUT/mame.log" 2>&1
rc=$?
set -e
echo "mame rc $rc"
tail -3 "$OUT/mame.log"
