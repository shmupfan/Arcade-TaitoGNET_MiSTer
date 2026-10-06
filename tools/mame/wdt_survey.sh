#!/bin/bash
# MB3773 kick survey over the target sets, warm and cold, one MAME at a time.
#   tools/mame/wdt_survey.sh <outdir under sim/oracle/> [set ...]
# Warm: the five post-copy flash images from sim/oracle/<set>_cold300 (or
# raycris_cold200), no EEPROM file, unmodified card (what a warm-boot MRA
# gives the core); 120 s, coin at 40 s. Cold: empty NVRAM; 300 s, coin at
# 180 s. Writes <outdir>/<set>_<warm|cold>/kicks.log (tools/mame/wdt_survey.lua).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
GNET=${GNET_ROOT:-$ROOT}
MAME=${MAME:-mame}
OUT=$1; shift
SETS=${*:-raycris psyvaria psyvarrv xiistag shikigam nightrai}
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
for s in $SETS; do
  for mode in warm cold; do
    while pgrep -x mame > /dev/null; do sleep 5; done
    d="$OUT/${s}_$mode"; rm -rf "$d"; mkdir -p "$d/nvram/$s" "$d/cfg" "$d/diff"
    if [ $mode = warm ]; then
      src="$GNET/sim/oracle/${s}_cold300/nvram/$s"; [ -d "$src" ] || src="$GNET/sim/oracle/${s}_cold200/nvram/$s"
      for f in firm zoomprog wave0 wave1 wave2; do cp "$src/$f" "$d/nvram/$s/"; done
      stop=120; coin=40
    else
      stop=300; coin=180
    fi
    (cd "$d" && WDT_OUT="$d" WDT_STOP=$stop WDT_COIN_AT=$coin SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
      nice -n 15 "$MAME" "$s" -rompath "$GNET/roms" -video none -sound none -nothrottle -skip_gameinfo \
      -nvram_directory nvram -cfg_directory cfg -diff_directory diff \
      -autoboot_script "$HERE/wdt_survey.lua" > mame.log 2>&1) || echo "$s $mode rc $?"
    echo "$s $mode done $(date +%T) $(wc -l < "$d/kicks.log") lines"
  done
done
