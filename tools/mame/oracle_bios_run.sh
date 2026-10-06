#!/bin/bash
# Run one set under the M0 oracle (tools/mame/oracle.lua, MAME 0.288) with a
# chosen BIOS EPROM and the JP1 jumper set, for the BIOS flasher checks in
# docs/gnet_set_survey.md (oracle_run.sh always runs the default BIOS with
# JP1 at the set's default).
#
#   tools/mame/oracle_bios_run.sh <set> <bios> <jp1 0|1> <seconds> <outdir> [<nvram src dir>]
#
#   <bios>  a ROM_SYSTEM_BIOS name of COH3002T_BIOS: v1, v2, mb2009, mb2011
#   <nvram src dir>  optional: files copied into the run's NVRAM directory
#           first (warm run); without it the run is cold.
# MAME keeps NVRAM for a non-default BIOS in nvram/<set>_<bios index>/
# (for example coh3002t_1 for v2); the source files are copied there.
#
# Output goes under sim/oracle/ (gitignored: game-derived data). Refuses to
# run when 3 or more MAME processes are running; runs under nice -n 15.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
MAME=${MAME:-mame}
if [ $# -lt 5 ]; then
  echo "usage: $0 <set> <bios> <jp1> <seconds> <outdir> [<nvram src dir>]" >&2
  exit 2
fi
SET=$1; BIOS=$2; JP1=$3; SECS=$4; OUTDIR=$5; NVSRC=${6:-}
case "$BIOS" in v1) IDX=0;; v2) IDX=1;; mb2009) IDX=2;; mb2011) IDX=3;;
  *) echo "unknown bios $BIOS" >&2; exit 2;; esac
running=$( (pgrep -x mame || true) | wc -l | tr -d ' ')
if [ "$running" -ge 3 ]; then
  echo "oracle_bios_run: $running MAME processes already running (limit 3)" >&2
  exit 3
fi
if [ -e "$OUTDIR" ]; then echo "oracle_bios_run: $OUTDIR exists, use a new directory" >&2; exit 4; fi
mkdir -p "$OUTDIR"
OUTDIR=$(cd "$OUTDIR" && pwd)
NVD="$OUTDIR/nvram/${SET}_$IDX"
[ "$IDX" = 0 ] && NVD="$OUTDIR/nvram/$SET"
mkdir -p "$NVD" "$OUTDIR/cfg" "$OUTDIR/snap" "$OUTDIR/diff"
[ -n "$NVSRC" ] && cp "$NVSRC"/* "$NVD/"
cat > "$OUTDIR/cfg/$SET.cfg" <<CFG
<?xml version="1.0"?>
<mameconfig version="10">
  <system name="$SET">
    <input>
      <port tag=":JP1" type="DIPSWITCH" mask="1" defvalue="0" value="$JP1" />
    </input>
  </system>
</mameconfig>
CFG
echo "set $SET bios $BIOS jp1 $JP1 seconds $SECS nvram_from ${NVSRC:-cold} started $(date '+%Y-%m-%d %H:%M:%S')" > "$OUTDIR/run.txt"
export ORACLE_OUT="$OUTDIR" SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
cd "$ROOT"
set +e
nice -n 15 "$MAME" "$SET" -bios "$BIOS" -rompath "$ROOT/roms" -video none -sound none -nothrottle \
  -skip_gameinfo -seconds_to_run "$SECS" \
  -nvram_directory "$OUTDIR/nvram" -cfg_directory "$OUTDIR/cfg" \
  -snapshot_directory "$OUTDIR/snap" -diff_directory "$OUTDIR/diff" \
  -autoboot_script "$HERE/oracle.lua" > "$OUTDIR/mame.log" 2>&1
rc=$?
set -e
echo "finished $(date '+%Y-%m-%d %H:%M:%S') rc $rc" >> "$OUTDIR/run.txt"
exit $rc
