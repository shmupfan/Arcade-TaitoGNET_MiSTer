#!/bin/bash
# Pause against the 8 s MB3773 watchdog and the shell's 8.5 s grace
# (tb_pausewd.sv), Verilator, nice -n 15. Regenerates work/pausewd_psx.svh
# from PSX.sv first. Optional argument nomask / nograce: negative controls
# (the mask removed / only the pause masked); those must FAIL.
set -euo pipefail
cd "$(dirname "$0")"
python3 gen_pausewd.py ${1:-}
nice -n 15 verilator --cc --exe --build -O3 -Wno-fatal -Wno-WIDTH -Wno-PROCASSINIT -j 2 \
  --top-module tb_pausewd -Iwork -Mdir obj_dir_pausewd \
  ../../rtl/gnet/gnet_ctrl.sv tb_pausewd.sv tb_pausewd.cpp -o tb_pausewd > obj_dir_pausewd.log 2>&1 \
  || { tail -30 obj_dir_pausewd.log; exit 1; }
nice -n 15 ./obj_dir_pausewd/tb_pausewd
