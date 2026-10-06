#!/bin/bash
# Trace the Taito Zoom ZSG-2 under MAME 0.288 with tools/zsg2/zsg2_trace.lua:
# every MN10200 access to the ZSG-2 (time, data, MN10200 PC, sample count)
# and the four ZSG-2 output words of every sample (from the TMS57002 serial
# inputs), for the chip-level replay in sim/zsg2.
#
#   tools/zsg2/zsg2_trace.sh <set> <seconds> <nvram_src_dir> <outdir>
#
# nvram_src_dir holds a post-copy NVRAM set (firm, wave0..2, zoomprog,
# at28c16), e.g. sim/r18/nv_<set>/<set> in the main checkout. outdir must be
# gitignored (sim/zsg2/work/): everything in it is game-derived.
# Env: ZSG2_LUA (script, default zsg2_trace.lua), ZSG2_COIN_AT (s, default 40).
# Runs under nice -n 15 and refuses to start when 3 MAME processes run.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
MAME=${MAME:-/opt/homebrew/bin/mame}
running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "zsg2_trace: $running MAME processes running (limit 3)" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
cp "$NVSRC"/* "$OUT/nvram/$SET/"
export ZOUT="$OUT/zsg2.log" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
set +e
nice -n 15 "$MAME" "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" \
  -autoboot_script "${ZSG2_LUA:-$HERE/zsg2_trace.lua}" > "$OUT/mame.log" 2>&1
rc=$?
set -e
echo "mame rc $rc"; tail -3 "$OUT/mame.log"
