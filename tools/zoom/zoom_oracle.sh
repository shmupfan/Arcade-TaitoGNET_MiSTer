#!/bin/bash
# Taito Zoom board oracle: run MAME with tools/zoom/zoom_oracle.lua and write
# trace.log, or stream it to ZOOM_TRACE_OUT (a FIFO, see
# sim/zoomboard/run_vs_mame.sh).
#
#   tools/zoom/zoom_oracle.sh <set> <seconds> <nvram_src_dir> <outdir>
#
# MAME defaults to the 0.288 build with the 61c7940 ZSG-2 fix
# (docs/zoom_zsg2_tms57002_design.md, last section); ZN2_CPU_HZ is cleared so
# the main CPU runs at MAME's default rate. nvram_src_dir holds a post-copy
# NVRAM set (sim/r18/nv_<set>/<set> in the main checkout). outdir must be
# gitignored (sim/zoom/...): everything in it is game-derived. Runs under
# nice -n 15 and refuses to start when 3 MAME processes run on the machine.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
MAME=${MAME:?set MAME to a MAME 0.288 build with the 61c7940 ZSG-2 fix (docs/zsg2_rtl.md)}
running=$( (pgrep -x mame; pgrep -x gnet_61c7940; pgrep -x gnet_0288_cpuhz; true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "zoom_oracle: $running MAME processes running (limit 3), refusing" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
cp "$NVSRC"/* "$OUT/nvram/$SET/"
unset ZN2_CPU_HZ
export ZOOM_TRACE="${ZOOM_TRACE_OUT:-$OUT/trace.log}" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
set +e
nice -n 15 "$MAME" "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" -debug -debugger none \
  -autoboot_script "$HERE/zoom_oracle.lua" > "$OUT/mame.log" 2>&1
rc=$?
set -e
echo "mame rc $rc"
