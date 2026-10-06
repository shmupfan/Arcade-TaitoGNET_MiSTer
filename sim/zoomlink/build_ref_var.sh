#!/bin/bash
# tb_zoomref (zoom_board alone, ideal memory) with extra zoom_board -G
# overrides, built into sim/zoomlink/work/build/obj_ref_<name>:
#   sim/zoomlink/build_ref_var.sh <name> [-GTMS_MAME=1 ...]
# (sim/zoomlink/build.sh builds the default obj_ref.)
set -euo pipefail
cd "$(dirname "$0")/../.."
N=$1; shift
R=rtl
ZF="$R/zoom/mn10200_decode.sv $R/zoom/mn10200_rf.sv $R/zoom/mn10200_core.sv $R/zoom/mn10200_periph.sv $R/zoom/mn10200.sv $R/zoom/zsg2_ram.sv $R/zoom/zsg2_fetch.sv $R/zoom/zsg2.sv $R/zoom/tms57002.sv $R/zoom/zoom_tbase.sv $R/zoom/zoom_tmsfeed.sv $R/zoom/zoom_pcache.sv $R/zoom/zoom_wram.sv $R/zoom/zoom_mbox.sv $R/zoom/zoom_host.sv $R/zoom/zoom_bus.sv $R/zoom/zoom_memarb.sv $R/zoom/zoom_out.sv $R/zoom/zoom_board.sv"
W=sim/zoomlink/work/build
nice -n 15 verilator --cc --exe --build -j 2 -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING --x-assign 0 --x-initial 0 --public-flat-rw --top-module zoom_board -GCLK_H=4 -GPACE_CAP=1024 -GZSG_INFL=4 -GTIMER_EXACT=0 -GDEBUG=0 "$@" --Mdir $W/obj_ref_$N -o tb_zoomref $ZF sim/zoomlink/tb_zoomref.cpp > $W/obj_ref_$N.log 2>&1 || { grep -m 10 Error $W/obj_ref_$N.log; exit 1; }
echo built $W/obj_ref_$N/tb_zoomref
