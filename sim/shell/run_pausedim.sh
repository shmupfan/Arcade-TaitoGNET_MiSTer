#!/bin/bash
# Pause options and Service Menu (tb_pausedim.sv), Verilator, nice -n 15.
# Regenerates work/pausewd_psx.svh and work/pausesvc_psx.svh from PSX.sv.
set -euo pipefail
cd "$(dirname "$0")"
python3 gen_pausewd.py
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -j 1 \
  --top-module tb_pausedim -Iwork -Mdir obj_dir_pausedim \
  ../../rtl/gnet/gnet_pause_dim.sv tb_pausedim.sv > obj_dir_pausedim.log 2>&1 \
  || { tail -30 obj_dir_pausedim.log; exit 1; }
nice -n 15 ./obj_dir_pausedim/Vtb_pausedim
