#!/bin/bash
# Build the gnet_fc replay testbench. Variant via env: VARIANT (object dir
# suffix), CLK (default 67737600, the PSX core's clk2x), FLASH_PRESET
# (default 1 = MAME), PROGRAM_AND (default 1).
set -euo pipefail
cd "$(dirname "$0")"
V=${VARIANT:-mame}
OBJ=obj_$V
verilator --cc --exe --build -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-WIDTH \
  -Mdir $OBJ --top-module gnet_fc \
  -GCLK_HZ=${CLK:-67737600} -GFLASH_PRESET=${FLASH_PRESET:-1} -GPROGRAM_AND=${PROGRAM_AND:-1} \
  -CFLAGS "-O2 -DCLK_HZ=${CLK:-67737600}ull" \
  ../../rtl/gnet/gnet_ctrl.sv ../../rtl/gnet/gnet_flash.sv ../../rtl/gnet/gnet_rf5c296.sv \
  ../../rtl/gnet/gnet_ata.sv ../../rtl/gnet/gnet_fc.sv tb_gnet_fc.cpp -o tb_gnet_fc > $OBJ.build.log 2>&1 \
  || { tail -30 $OBJ.build.log; exit 1; }
echo "built $OBJ/tb_gnet_fc"
