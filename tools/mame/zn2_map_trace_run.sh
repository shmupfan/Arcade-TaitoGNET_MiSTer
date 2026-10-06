#!/bin/bash
# Run one set under tools/mame/zn2_map_trace.lua (MAME 0.288).
#
#   tools/mame/zn2_map_trace_run.sh <set> <seconds> <outdir> [--cold]
#
# Warm by default: copies the post-copy NVRAM and card diff from
# $ORACLE_NVRAM_FROM (default sim/oracle/postcopy/<set>), as oracle_run.sh.
# outdir must be under sim/ (gitignored): the logs are game-derived.
# Runs under nice -n 15 and refuses to start with 2 or more MAME processes.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${GNET_ROOT:-$(cd "$HERE/../.." && pwd)}
MAME=${MAME:-mame}
[ $# -lt 3 ] && { echo "usage: $0 <set> <seconds> <outdir> [--cold]" >&2; exit 2; }
SET=$1; SECS=$2; OUTDIR=$3; COLD=0
[ "${4:-}" = "--cold" ] && COLD=1

running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -ge 2 ] && { echo "zn2_map_trace_run: $running MAME processes running" >&2; exit 3; }

mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)
rm -rf "$OUTDIR/nvram" "$OUTDIR/cfg" "$OUTDIR/diff"
mkdir -p "$OUTDIR/nvram/$SET" "$OUTDIR/cfg" "$OUTDIR/diff"
if [ "$COLD" = 0 ]; then
  SRC=${ORACLE_NVRAM_FROM:-$ROOT/sim/oracle/postcopy/$SET}
  NV=$SRC
  [ -d "$SRC/nvram/$SET" ] && NV="$SRC/nvram/$SET"
  [ -d "$NV/$SET" ] && NV="$NV/$SET"
  [ -f "$NV/firm" ] || { echo "no post-copy NVRAM in $SRC" >&2; exit 4; }
  cp "$NV"/* "$OUTDIR/nvram/$SET/"
  [ -d "$SRC/diff" ] && cp -R "$SRC/diff/." "$OUTDIR/diff/"
fi

export ZN2MAP_OUT="$OUTDIR" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
cd "$ROOT"
nice -n 15 "$MAME" "$SET" -rompath "$ROOT/roms" -video none -sound none -nothrottle \
  -skip_gameinfo -seconds_to_run "$SECS" \
  -nvram_directory "$OUTDIR/nvram" -cfg_directory "$OUTDIR/cfg" \
  -diff_directory "$OUTDIR/diff" \
  -autoboot_script "$HERE/zn2_map_trace.lua" > "$OUTDIR/mame.log" 2>&1
