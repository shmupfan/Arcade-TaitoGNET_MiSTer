#!/bin/bash
# Run MAME with tools/zoom/zoom_hostlog.lua (main-CPU Zoom port accesses,
# control writes and MN10200 mailbox accesses, no debugger) and write
# <outdir>/hostlog.txt, for the replay in sim/zoomlink (docs/zoom_board_design.md 14).
#
#   tools/zoom/zoom_hostlog.sh <set> <seconds> <nvram_src_dir> <outdir>
#
# As tools/zoom/zoom_oracle.sh: the 61c7940 build by default, ZN2_CPU_HZ
# cleared, nvram_src_dir a post-copy NVRAM set (sim/r18/nv_<set>/<set> in the
# main checkout), outdir gitignored (game-derived). nice -n 15; refuses to
# start when 3 MAME processes run.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SET=$1; SECS=$2; NVSRC=$3; OUT=$4
ROMS=${ROMS:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/roms}
MAME=${MAME:?set MAME to a MAME 0.288 build with the 61c7940 ZSG-2 fix (docs/zsg2_rtl.md)}
running=$( (pgrep -x mame; pgrep -x gnet_61c7940; pgrep -x gnet_0288_cpuhz; true) | wc -l | tr -d ' ')
[ "$running" -ge 3 ] && { echo "zoom_hostlog: $running MAME processes running (limit 3), refusing" >&2; exit 3; }
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
rm -rf "$OUT/nvram" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
mkdir -p "$OUT/nvram/$SET" "$OUT/cfg" "$OUT/diff" "$OUT/snap"
cp "$NVSRC"/* "$OUT/nvram/$SET/"
unset ZN2_CPU_HZ
export ZOOM_HOSTLOG="$OUT/hostlog.txt" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
set +e
nice -n 15 "$MAME" "$SET" -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -diff_directory "$OUT/diff" -snapshot_directory "$OUT/snap" \
  -autoboot_script "$HERE/zoom_hostlog.lua" > "$OUT/mame.log" 2>&1
rc=$?
set -e
echo "mame rc $rc"
