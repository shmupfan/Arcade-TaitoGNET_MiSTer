#!/bin/bash
# Full-system simulation, step 2: Verilator build of the GHDL netlist, the
# sdram.sv copy, the RAM models and the C++ harness.
#   sim/fullsys/build.sh            (TAG=main by default, as convert.sh)
# Runs under nice with at most 4 compile jobs (shared Mac).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${TAG:-main}
W=$HERE/work/$TAG
# settings of the tree this netlist came from (written by zn2.sh)
[ -f $W/build.env ] && . $W/build.env
ROOT=${RTL_ROOT:-$(cd "$HERE/../.." && pwd)}
python3 $HERE/sdram_copy.py $ROOT/rtl/sdram.sv $W/sdram_v.sv
python3 $HERE/gen_top.py $W/psx_top.v $W/fs_top.sv
cd $W
time nice -n 15 verilator --cc --exe --build -j 4 -O3 ${VFLAGS:-} --x-assign fast --x-initial unique \
  -Wno-fatal -Wno-lint -Wno-style -Wno-ALWNEVER \
  --output-split 20000 --output-split-cfuncs 2000 \
  -CFLAGS "${COPT:--O2} -I$W ${VFLAGS:+$( [[ $VFLAGS == *--savable* ]] && echo -DFS_SAVABLE)}" ${LOPT:+-LDFLAGS "$LOPT"} \
  --top-module fs_top -Mdir ${MDIR:-obj_dir} \
  fs_top.sv psx_top.v sdram_v.sv $HERE/fs_mem.v ${EXTRA_SV:-} $HERE/tb_fullsys.cpp > build${MDIR:+_$MDIR}.log 2>&1 || { grep -m 20 -E "error|Error" build${MDIR:+_$MDIR}.log; exit 1; }
ls -l ${MDIR:-obj_dir}/Vfs_top
