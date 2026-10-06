#!/bin/bash
# Build and run the directed tests. Env: FLASH_PRESET (1, 2 or 3), CLK,
# WD (MB3773 period in s, default 8 as gnet_ctrl.sv).
set -euo pipefail
cd "$(dirname "$0")"
P=${FLASH_PRESET:-1}; CLKV=${CLK:-67737600}; WDS=${WD:-8}; OBJ=obj_dir_p$P
verilator --cc --exe --build -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-WIDTH -Mdir $OBJ --top-module gnet_fc \
  -GCLK_HZ=$CLKV -GFLASH_PRESET=$P -GWD_TIMEOUT_S=$WDS -CFLAGS "-O2 -DCLK_HZ=${CLKV}ull -DPRESET=$P -DWD_S=$WDS" \
  ../../rtl/gnet/gnet_ctrl.sv ../../rtl/gnet/gnet_flash.sv ../../rtl/gnet/gnet_rf5c296.sv \
  ../../rtl/gnet/gnet_ata.sv ../../rtl/gnet/gnet_fc.sv tb_directed.cpp -o tb_directed > $OBJ.build.log 2>&1 \
  || { tail -30 $OBJ.build.log; exit 1; }
./$OBJ/tb_directed
