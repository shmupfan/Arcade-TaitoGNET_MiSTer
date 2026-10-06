#!/bin/bash
# Run one set under tools/mame/r1_bus.lua (MAME 0.288), warm from a post-copy
# NVRAM directory, or cold.
#
#   tools/mame/r1_bus_run.sh <set> <seconds> <outdir> <coin_at> [<nvram_src>|--cold]
#
# <nvram_src>: a previous oracle run (nvram/<set>/ and diff/ inside), default
# sim/oracle/postcopy/<set>. Output stays under sim/r1/ (gitignored): logs are
# game-derived and never committed. One MAME at a time from this script, under
# nice -n 15, refused when 3 MAME processes already run.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MAME=${MAME:-mame}
[ $# -ge 4 ] || { echo "usage: $0 <set> <seconds> <outdir> <coin_at> [<nvram_src>|--cold]" >&2; exit 2; }
SET=$1; SECS=$2; OUTDIR=$3; COIN=$4; SRC=${5:-$ROOT/sim/oracle/postcopy/$SET}

running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
[ "$running" -lt 3 ] || { echo "r1_bus_run: $running MAME processes already running (limit 3)" >&2; exit 3; }

mkdir -p "$OUTDIR"; OUTDIR=$(cd "$OUTDIR" && pwd)
rm -rf "$OUTDIR/nvram" "$OUTDIR/cfg" "$OUTDIR/diff" "$OUTDIR/snap"
mkdir -p "$OUTDIR/nvram/$SET" "$OUTDIR/cfg" "$OUTDIR/diff" "$OUTDIR/snap"
if [ "$SRC" != "--cold" ]; then
  NV=$SRC; [ -d "$SRC/nvram/$SET" ] && NV="$SRC/nvram/$SET"
  [ -f "$NV/firm" ] || { echo "r1_bus_run: no post-copy NVRAM in $SRC" >&2; exit 4; }
  cp "$NV"/* "$OUTDIR/nvram/$SET/"
  [ -d "$SRC/diff" ] && cp -R "$SRC/diff/." "$OUTDIR/diff/"
fi
echo "set $SET seconds $SECS coin $COIN nvram $SRC started $(date '+%F %T')" > "$OUTDIR/run.txt"
export R1B_OUT="$OUTDIR" R1B_COIN_AT="$COIN" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
cd "$ROOT"
set +e
nice -n 15 "$MAME" "$SET" -rompath "$ROOT/roms" -video none -sound none -nothrottle \
  -skip_gameinfo -seconds_to_run "$SECS" \
  -nvram_directory "$OUTDIR/nvram" -cfg_directory "$OUTDIR/cfg" \
  -snapshot_directory "$OUTDIR/snap" -diff_directory "$OUTDIR/diff" \
  -autoboot_script "$HERE/r1_bus.lua" > "$OUTDIR/mame.log" 2>&1
rc=$?
set -e
echo "finished $(date '+%F %T') rc $rc" >> "$OUTDIR/run.txt"
exit $rc
