#!/bin/bash
# OSD Crop 224 lines: replay video-out traces (run_vtrace.sh) through
# rtl/gnet/gnet_crop224.sv with the crop On and Off (tb_crop224.sv),
# Verilator. Modes 0, 1, 3 (256, 320, 640 dots 240p) and 4 (640 480i);
# run run_vtrace.sh 0 1 3 4 first.
set -euo pipefail
cd "$(dirname "$0")"
OBJ=obj_dir_crop224
mkdir -p $OBJ
nice -n 15 verilator --binary --timing -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PROCASSINIT -Wno-TIMESCALEMOD -j 1 \
  --top-module tb_crop224 -Mdir $OBJ \
  ../../rtl/gnet/gnet_crop224.sv tb_crop224.sv > $OBJ.log 2>&1 \
  || { tail -30 $OBJ.log; exit 1; }
grep -E "%Warning" $OBJ.log | grep gnet_crop224 || true
for m in 0 1 3 4; do
  case $m in 0) W=256 ;; 1) W=320 ;; *) W=640 ;; esac
  IL=0; [ $m -ge 4 ] && IL=1
  for en in 1 0; do
    echo "mode $m crop $en: $(./$OBJ/Vtb_crop224 +trace=work/vtrace_$m.txt +width=$W +ilace=$IL +en=$en | grep -E "^(PASS|FAIL)")"
  done
done
