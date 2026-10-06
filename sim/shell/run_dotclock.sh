#!/bin/bash
# DV1 integer pixel clock check of the GPU video out (tb_dotclock.vhd), NVC.
# The video-out copy has every to_unsigned(x, N) wrapped mod 2**N, as
# sim/m1/build.sh does (NVC stops on the negative intermediates the hardware
# truncates). Run one simulation at a time, niced.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work/patched
cd work
R=../../../rtl
NV="nvc --std=2008"
python3 ../../m1/wrap_to_unsigned.py $R/gpu_videoout_async.vhd > patched/gpu_videoout_async.vhd
$NV --work=mem -a --relaxed ../../system/src/mem/dpram.vhd
$NV --work=work -L . -a --relaxed ../../system/src/mem/dpram.vhd $R/pGPU.vhd $R/gpu_dither.vhd patched/gpu_videoout_async.vhd ../tb_dotclock.vhd
$NV --work=work -L . -e tb_dotclock
nice -n 15 $NV --work=work -L . -r tb_dotclock 2>&1 | grep -iE "RESULT|failure|error" || true
