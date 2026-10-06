#!/bin/bash
# Build libgnetfc.so: rtl/gnet/gnet_fc.sv (and its blocks) through Verilator,
# with the VHPIDIRECT shim gnet_fc_step.cpp, for NVC co-simulation
# (sim/zn2/cosim/gnet_fc_cosim.vhd).
#   sim/zn2/cosim/build_gnet_fc.sh <outdir>
# Env GNET_FC_CLK_HZ: gnet_fc's CLK_HZ (default 33868800; 50000000 for the
# CPU group of psx_top CPU_CLK_SPLIT = 1).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OUT=$1
mkdir -p "$OUT"
cd "$OUT"
R=$ROOT/rtl/gnet
verilator --cc -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-WIDTH -Mdir obj --top-module gnet_fc \
  -GCLK_HZ=${GNET_FC_CLK_HZ:-33868800} -GFLASH_PRESET=1 -GWD_TIMEOUT_S=8 \
  $R/gnet_ctrl.sv $R/gnet_flash.sv $R/gnet_rf5c296.sv $R/gnet_ata.sv $R/gnet_fc.sv > verilator.log 2>&1 \
  || { tail -20 verilator.log; exit 1; }
VI=$(verilator --getenv VERILATOR_ROOT)/include
c++ -std=c++17 -O2 -fPIC -shared -DGNET_FC_CLK_HZ=${GNET_FC_CLK_HZ:-33868800} -I obj -I "$VI" -I "$VI/vltstd" \
  "$HERE/gnet_fc_step.cpp" obj/*.cpp "$VI/verilated.cpp" "$VI/verilated_threads.cpp" \
  -o libgnetfc.so > cxx.log 2>&1 || { tail -20 cxx.log; exit 1; }
echo "built $OUT/libgnetfc.so"
