#!/bin/bash
# Run one set under the M0 oracle (tools/mame/oracle.lua), MAME 0.288.
#
#   tools/mame/oracle_run.sh <set> <seconds> <outdir> [--cold]
#
#   --cold  start from an empty NVRAM directory, so the first-boot copy of
#           the PC card into the flash chips (~133-155 emulated s) is traced.
#   default (warm): copy a saved post-copy state into the run first, from
#           $ORACLE_NVRAM_FROM (default sim/oracle/postcopy/<set>): either a
#           previous run directory (nvram/<set>/ and diff/), or a directory
#           holding the NVRAM files (firm, wave0..2, zoomprog, at28c16)
#           directly or in <set>/, with an optional diff/ beside them.
#
# The game writes sectors to the PC card (ATA WRITE SECTORS after the copy);
# MAME keeps those in the CHD diff file, so every run gets its own
# -diff_directory: empty for --cold, copied from the source for warm runs.
#
# Output (outdir is created; keep it under sim/oracle/, which is gitignored:
# NVRAM, snapshots and logs are game-derived data and must never be committed):
#   <outdir>/*.log, summary.txt   oracle logs (see the header of oracle.lua)
#   <outdir>/snap/f<frame>.png    snapshots every ORACLE_SNAP_EVERY frames
#   <outdir>/nvram/<set>/         MAME NVRAM at exit (after --cold: post-copy)
#   <outdir>/diff/<set>.dif       CHD diff: sectors the game wrote to the card
#   <outdir>/cfg/, mame.log       MAME cfg and console output
# Other environment passed through to the script: ORACLE_SNAP_EVERY,
# ORACLE_COIN_AT, ORACLE_FLASH_RAW, ORACLE_GPU_STREAM (1 = gpu_stream.bin for M1).
#
# Run at most 3 of these at once; each runs under nice -n 15.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MAME=${MAME:-mame}

if [ $# -lt 3 ]; then
  echo "usage: $0 <set> <seconds> <outdir> [--cold]" >&2
  exit 2
fi
SET=$1; SECS=$2; OUTDIR=$3; COLD=0
[ "${4:-}" = "--cold" ] && COLD=1

running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
if [ "$running" -ge 3 ]; then
  echo "oracle_run: $running MAME processes already running (limit 3)" >&2
  exit 3
fi

mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)
case "$OUTDIR" in
  "$ROOT"/sim/oracle/*) ;;
  *) echo "oracle_run: warning: $OUTDIR is outside sim/oracle/ (not gitignored)" >&2 ;;
esac
rm -rf "$OUTDIR/nvram" "$OUTDIR/cfg" "$OUTDIR/snap" "$OUTDIR/diff"
mkdir -p "$OUTDIR/nvram/$SET" "$OUTDIR/cfg" "$OUTDIR/snap" "$OUTDIR/diff"

if [ "$COLD" = 0 ]; then
  SRC=${ORACLE_NVRAM_FROM:-$ROOT/sim/oracle/postcopy/$SET}
  SRC=$(cd "$SRC" 2>/dev/null && pwd || echo "$SRC")
  if [ "$SRC" = "$OUTDIR" ]; then echo "oracle_run: source is the output dir" >&2; exit 4; fi
  NV=$SRC
  [ -d "$SRC/nvram/$SET" ] && NV="$SRC/nvram/$SET"
  [ -d "$NV/$SET" ] && NV="$NV/$SET"
  if [ ! -f "$NV/firm" ]; then
    echo "oracle_run: no post-copy NVRAM in $SRC (set ORACLE_NVRAM_FROM or run --cold)" >&2
    exit 4
  fi
  cp "$NV"/* "$OUTDIR/nvram/$SET/"
  if [ -d "$SRC/diff" ]; then
    cp -R "$SRC/diff/." "$OUTDIR/diff/"
  else
    echo "oracle_run: warning: no diff/ in $SRC, the card starts unmodified" >&2
  fi
  echo "nvram_from $NV" > "$OUTDIR/run.txt"
else
  echo "nvram_from cold" > "$OUTDIR/run.txt"
fi
echo "set $SET seconds $SECS started $(date '+%Y-%m-%d %H:%M:%S')" >> "$OUTDIR/run.txt"

export ORACLE_OUT="$OUTDIR" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
cd "$ROOT"
set +e
nice -n 15 "$MAME" "$SET" -rompath "$ROOT/roms" -video none -sound none -nothrottle \
  -skip_gameinfo -seconds_to_run "$SECS" \
  -nvram_directory "$OUTDIR/nvram" -cfg_directory "$OUTDIR/cfg" \
  -snapshot_directory "$OUTDIR/snap" -diff_directory "$OUTDIR/diff" \
  -autoboot_script "$HERE/oracle.lua" > "$OUTDIR/mame.log" 2>&1
rc=$?
set -e
echo "finished $(date '+%Y-%m-%d %H:%M:%S') rc $rc" >> "$OUTDIR/run.txt"
exit $rc
