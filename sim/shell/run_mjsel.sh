#!/bin/bash
# Mahjong Select + L / R (tb_mjsel.sv), Verilator, nice -n 15.
# Regenerates work/mjsel_psx.svh from PSX.sv.
set -euo pipefail
cd "$(dirname "$0")"
python3 gen_pausewd.py
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -j 1 \
  --top-module tb_mjsel -Iwork -Mdir obj_dir_mjsel \
  ../../rtl/gnet/gnet_coin_pulse.sv tb_mjsel.sv > obj_dir_mjsel.log 2>&1 \
  || { tail -30 obj_dir_mjsel.log; exit 1; }
nice -n 15 ./obj_dir_mjsel/Vtb_mjsel
