#!/bin/bash
# Record a lossless glue trace (tools/mame/glue_trace.lua) for one set.
#   tools/mame/glue_trace_run.sh <set> <seconds> <outdir> [--warm <nvram_src>] [coin_at]
# Cold by default (empty NVRAM: U30 from flash.u30, other flashes erased, so
# the first-boot copy is traced). Writes <outdir>/glue.zst, nvram/ (MAME's
# flash contents at exit), diff/ (card writes), mame.log. outdir must be
# gitignored (sim/gnet/work/): game-derived data.
# At most 3 MAME processes across sessions; nice -n 15.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; OUT=$3; shift 3
WARM=""; COIN=""
while [ $# -gt 0 ]; do
  case $1 in --warm) WARM=$2; shift 2 ;; *) COIN=$1; shift ;; esac
done
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "glue_trace_run: $running MAME running (limit 3)" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"; mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
if [ -n "$WARM" ]; then
  NV=$WARM; [ -d "$WARM/nvram/$SET" ] && NV=$WARM/nvram/$SET
  cp "$NV"/* "$OUT/nvram/$SET/"
  [ -d "$WARM/diff" ] && cp -R "$WARM/diff/." "$OUT/diff/"
fi
export GLUE_OUT="$OUT/glue.zst" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
[ -n "$COIN" ] && export GLUE_COIN_AT=$COIN
set +e
nice -n 15 mame "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" \
  -autoboot_script "$HERE/glue_trace.lua" > "$OUT/mame.log" 2>&1
rc=$?
set -e
echo "rc $rc $(cat "$OUT/glue.zst.txt" 2>/dev/null) $(du -h "$OUT/glue.zst" | cut -f1)"
