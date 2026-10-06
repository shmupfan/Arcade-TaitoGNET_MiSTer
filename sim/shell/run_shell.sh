#!/bin/bash
# Unit bench of gnet_sync_keeper and gnet_volume (tb_shell.sv), Verilator.
set -euo pipefail
cd "$(dirname "$0")"
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -j 1 \
  --top-module tb_shell -Mdir obj_dir \
  ../../rtl/gnet/gnet_sync_keeper.sv ../../rtl/gnet/gnet_volume.sv tb_shell.sv > obj_dir.log 2>&1 \
  || { tail -30 obj_dir.log; exit 1; }
nice -n 15 ./obj_dir/Vtb_shell
