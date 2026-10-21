#!/bin/bash
# Super Puzzle Bobble high score evidence (docs/hiscore.md 1), MAME 0.288.
#
#   tools/mame/hiscore_run.sh <outdir> <seconds> <nvram_from> [wp]
#
# Runs spuzbobl from a saved post-copy state (<nvram_from>: a directory with
# nvram/spuzbobl/ and diff/, as an oracle_run.sh output) under
# tools/mame/hiscore_probe.lua (environment as its header), or with "wp"
# under tools/mame/hiscore_wp.lua (debugger watchpoints). Afterwards it
# compares the EEPROM file (at28c16) and the card's CHD diff with the ones
# it started from: "EEPROM unchanged" / "card unchanged" mean the run wrote
# neither. Keep <outdir> under sim/oracle/ (gitignored: game-derived data).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=$1; SECS=$2; SRC=$3; MODE=${4:-probe}
MAME=${MAME:-mame}
ROMS=${ROMS:-$ROOT/roms}
rm -rf "$OUT"; mkdir -p "$OUT/nvram/spuzbobl" "$OUT/diff" "$OUT/cfg" "$OUT/snap"
OUT=$(cd "$OUT" && pwd)
cp "$SRC"/nvram/spuzbobl/* "$OUT/nvram/spuzbobl/"
cp "$SRC"/diff/* "$OUT/diff/"
cp "$OUT/nvram/spuzbobl/at28c16" "$OUT/at28c16.before"
cp "$OUT/diff/spuzbobl.dif" "$OUT/spuzbobl.dif.before"
if [ "$MODE" = wp ]; then SCRIPT=$HERE/hiscore_wp.lua; DBG=(-debug -debugger none); else SCRIPT=$HERE/hiscore_probe.lua; DBG=(); fi
export HS_OUT="$OUT" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
nice -n 15 "$MAME" spuzbobl -rompath "$ROMS" -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run "$SECS" -nvram_directory "$OUT/nvram" -cfg_directory "$OUT/cfg" \
  -snapshot_directory "$OUT/snap" -diff_directory "$OUT/diff" ${DBG[@]+"${DBG[@]}"} \
  -autoboot_script "$SCRIPT" > "$OUT/mame.log" 2>&1
cmp -s "$OUT/at28c16.before" "$OUT/nvram/spuzbobl/at28c16" && echo "EEPROM unchanged" || echo "EEPROM changed"
cmp -s "$OUT/spuzbobl.dif.before" "$OUT/diff/spuzbobl.dif" && echo "card unchanged" || echo "card changed"
