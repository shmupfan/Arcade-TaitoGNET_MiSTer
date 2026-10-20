#!/bin/bash
# R23: GPU drawing time replay (docs/gpu_draw_time.md). Runs
# sim/m1/tb_gpu_replay.vhd with GTIME=true in its own directory
# sim/m1/gtime/<name>/ (own work library, GPU libraries from sim/m1/gtime,
# built by M1_BUILD=gtime sim/m1/build.sh), under nice -n 15.
#   tools/gpu_time_run.sh <name> <stream.txt> <init.bin> <maxframe> [-gX=Y ...]
# GTIME_TB overrides the testbench source (e.g. a frozen copy).
# Writes frames_time.txt, vblank_busy.txt, frames.txt, run.log there.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NAME=$1; STREAM=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
INIT=$(cd "$(dirname "$3")" && pwd)/$(basename "$3"); MAXF=$4; shift 4
D=$ROOT/sim/m1/gtime/$NAME
mkdir -p "$D" && cd "$D"
rm -rf work
TB=${GTIME_TB:-$ROOT/sim/m1/tb_gpu_replay.vhd}
nice -n 15 nvc --std=2008 -H 256m -L .. --work=work -a --relaxed "$TB" \
  -e tb_gpu_replay -gSTREAM="$STREAM" -gVRAM_INIT="$INIT" -gVRAM_Y_BITS=10 -gDUMPS=0 \
  -gMAXFRAME="$MAXF" -gGTIME=true -gVIDCAP=false -gGPUREAD_DRAIN=true "$@" \
  -r --exit-severity=failure --ieee-warnings=off 2>&1 | grep -E '^\*\* (Note|Error|Fatal|Failure)' > run.log || true
date '+finished %Y-%m-%d %H:%M:%S' >> run.log
