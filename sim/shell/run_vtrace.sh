#!/bin/bash
# Issue #11: write video-out traces (tb_vtrace.vhd, NVC) for the modes given
# (default 1 3 2 4), into work/vtrace_<mode>.txt, for run_sd_trace.sh.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work/patched
cd work
R=../../../rtl
NV="nvc --std=2008"
python3 ../../m1/wrap_to_unsigned.py $R/gpu_videoout_async.vhd > patched/gpu_videoout_async.vhd
$NV --work=mem -a --relaxed ../../system/src/mem/dpram.vhd
$NV --work=work -L . -a --relaxed ../../system/src/mem/dpram.vhd $R/pGPU.vhd $R/gpu_dither.vhd patched/gpu_videoout_async.vhd ../tb_vtrace.vhd
MODES="${*:-1 3 2 4}"
for m in $MODES; do
  F=4; [ "$m" -ge 4 ] && F=6
  $NV --work=work -L . -e -gMODE=$m -gFRAMES=$F -gOUTFILE=vtrace_$m.txt tb_vtrace
  nice -n 15 $NV --work=work -L . -r tb_vtrace 2>&1 | grep -iE "failure|error" || true
  echo "mode $m: $(wc -l < vtrace_$m.txt) dot enables"
done
