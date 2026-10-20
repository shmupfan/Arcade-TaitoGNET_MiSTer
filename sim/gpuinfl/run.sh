#!/bin/bash
# Replay one GPU stream through tb_gpu_infl (2 MB VRAM, no video
# capture) in sim/gpuinfl/runs/<name>/, own work library, GPU libraries from
# sim/gpuinfl/work (built by sim/gpuinfl/build.sh), under nice -n 15.
#   sim/gpuinfl/run.sh <name> <stream.txt> <init.bin> <maxframe> [-gVRAM_RD_LAT=N ...]
# Writes ddr3_frames.txt (columns in tb_gpu_infl.vhd, BWMON) and run.log.
set -euo pipefail
cd "$(dirname "$0")"
NAME=$1; STREAM=$2; INIT=$3; MAXF=$4; shift 4
DUMPS=-gDUMPS=0; case " $* " in *" -gDUMPS="*) DUMPS= ;; esac
D=runs/$NAME; mkdir -p "$D" && cd "$D"; rm -rf work
nice -n 15 nvc --std=2008 -H 256m -L ../../work --work=work -a --relaxed ../../tb_gpu_infl.vhd \
  -e --no-save --jit tb_gpu_infl -gSTREAM="$STREAM" -gVRAM_INIT="$INIT" -gVRAM_Y_BITS=10 $DUMPS \
  -gMAXFRAME="$MAXF" -gVIDCAP=false "$@" \
  -r --exit-severity=failure --ieee-warnings=off > nvc.log 2>&1 || true
grep -E '^\*\* (Note|Error|Fatal|Failure)' nvc.log > run.log || true
date '+finished %Y-%m-%d %H:%M:%S' >> run.log
