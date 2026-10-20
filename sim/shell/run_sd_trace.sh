#!/bin/bash
# Issue #11: replay a video-out trace (run_vtrace.sh) through the GNET_SHELL
# video chain and gnet_arcade_video for every Scandoubler Fx setting
# (tb_sd_trace.sv), Verilator. Usage: run_sd_trace.sh <mode> [fix|alpha1]
# "fix" adds rtl/gnet/gnet_sd_blank.sv (SD_BLANK) as PSX.sv wires it;
# "alpha1" puts the framework's sys/arcade_video.v in place of the copy.
set -euo pipefail
cd "$(dirname "$0")"
M="${1:-1}"
FIX="${2:-}"
OBJ=obj_dir_sdt${FIX:+_$FIX}
DEFS=""; EXTRA=""
if [ "$FIX" = fix ]; then DEFS="-DSD_BLANK"; EXTRA="../../rtl/gnet/gnet_sd_blank.sv"; fi
if [ "$FIX" = alpha1 ]; then DEFS="-DALPHA1"; EXTRA="../../sys/arcade_video.v"; fi
mkdir -p $OBJ
case $M in 0) W=256 ;; 1) W=320 ;; 2|5) W=512 ;; *) W=640 ;; esac
sed -n '/^module sync_fix/,/^endmodule/p' ../../sys/sys_top.v > $OBJ/sync_fix.v
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -Wno-PROCASSWIRE -j 1 $DEFS \
  --top-module tb_sd_trace -Mdir $OBJ \
  ../../sys/video_mixer.sv ../../sys/scandoubler.v ../../sys/hq2x.sv \
  ../../sys/gamma_corr.sv ../../sys/video_freezer.sv $OBJ/sync_fix.v \
  ../../rtl/gnet/gnet_arcade_video.sv $EXTRA tb_sd_trace.sv > $OBJ.log 2>&1 \
  || { tail -30 $OBJ.log; exit 1; }
nice -n 15 ./$OBJ/Vtb_sd_trace +trace=work/vtrace_$M.txt +width=$W
