#!/bin/bash
# Run one G-NET set in MAME 0.288 with tools/r1/r1_frames.lua (per-frame
# screen signature). Warm boot from a post-copy NVRAM directory.
#   tools/r1/r1_run.sh <set> <seconds> <nvram_src> <outdir> [extra mame args]
# nvram_src: a directory holding nvram/<set>/ (and diff/) as written by
# tools/mame/oracle_run.sh, e.g. sim/oracle/postcopy/<set> of the main checkout.
# outdir must be gitignored (sim/r1/): game-derived data.
# Env: MAME (binary, default mame; the patched build is "gnet" and reads
# ZN2_CPU_HZ), ROMS, R1_COIN_AT, R1_SNAP_EVERY,
# R1_JP1=1 (boot the MB2011 MOD BIOS).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; SRC=$3; OUT=$4; shift 4
MAME=${MAME:-mame}
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
running=$(( $( (pgrep -x mame || true) | wc -l) + $( (pgrep -x gnet || true) | wc -l) ))
[ "$running" -ge 3 ] && { echo "r1_run: $running MAME processes running (limit 3)" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
NV="$SRC"; [ -d "$SRC/nvram/$SET" ] && NV="$SRC/nvram/$SET"; [ -d "$NV/$SET" ] && NV="$NV/$SET"
cp "$NV"/* "$OUT/nvram/$SET/"
[ -d "$SRC/diff" ] && cp -R "$SRC/diff/." "$OUT/diff/"
if [ "${R1_JP1:-0}" = 1 ]; then
  # JP1 closed: boot the MB2011 MOD BIOS EPROM (flash bank 2), as the
  # westtrade PCB does (its logo reads "TAITO CORPORATION MB-2011")
  cat > "$OUT/cfg/$SET.cfg" <<CFG
<?xml version="1.0"?>
<mameconfig version="10">
  <system name="$SET">
    <input>
      <port tag=":JP1" type="DIPSWITCH" mask="1" defvalue="0" value="1" />
    </input>
  </system>
</mameconfig>
CFG
fi
export R1_OUT="$OUT/frames.csv" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
nice -n 15 "$MAME" "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" \
  -autoboot_script "$HERE/r1_frames.lua" "$@" > "$OUT/mame.log" 2>&1
echo "rc $? frames $(($(wc -l < "$OUT/frames.csv") - 1))"
