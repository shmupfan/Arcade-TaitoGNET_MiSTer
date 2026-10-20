#!/bin/bash
# Bench of gnet_dash and gnet_dash_remap (tb_dash.sv, issue #7), Verilator.
set -euo pipefail
cd "$(dirname "$0")"
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -j 1 \
  --top-module tb_dash -Mdir obj_dir_dash \
  ../../rtl/gnet/gnet_dash.sv tb_dash.sv > obj_dir_dash.log 2>&1 \
  || { tail -30 obj_dir_dash.log; exit 1; }
nice -n 15 ./obj_dir_dash/Vtb_dash
