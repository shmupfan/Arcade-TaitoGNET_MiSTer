#!/bin/bash
# Unit bench of gnet_crt_pos (tb_crt_pos.sv), Verilator.
set -euo pipefail
cd "$(dirname "$0")"
nice -n 15 verilator --binary --timing -Wno-fatal -Wno-PROCASSINIT -Wno-WIDTH -j 1 \
  --top-module tb_crt_pos -Mdir obj_dir_crt \
  ../../rtl/gnet/gnet_crt_pos.sv tb_crt_pos.sv > obj_dir_crt.log 2>&1 \
  || { tail -30 obj_dir_crt.log; exit 1; }
nice -n 15 ./obj_dir_crt/Vtb_crt_pos
