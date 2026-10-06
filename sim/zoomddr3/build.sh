#!/bin/bash
# Build tb_zd3 (Verilator), nice -n 15. Env ZSG_INFL (default 8).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
R=$ROOT/rtl
INFL=${ZSG_INFL:-8}
OBJ=$HERE/work/obj_infl$INFL
mkdir -p "$HERE/work"
ZF="$R/zoom/mn10200_decode.sv $R/zoom/mn10200_rf.sv $R/zoom/mn10200_core.sv $R/zoom/mn10200_periph.sv $R/zoom/mn10200.sv
 $R/zoom/zsg2_ram.sv $R/zoom/zsg2_fetch.sv $R/zoom/zsg2.sv $R/zoom/tms57002.sv $R/zoom/zoom_tbase.sv $R/zoom/zoom_tmsfeed.sv
 $R/zoom/zoom_pcache.sv $R/zoom/zoom_wram.sv $R/zoom/zoom_mbox.sv $R/zoom/zoom_host.sv $R/zoom/zoom_bus.sv
 $R/zoom/zoom_memarb.sv $R/zoom/zoom_out.sv $R/zoom/zoom_board.sv"
DF="$R/gnet/gnet_ddr3_arb.sv $R/gnet/gnet_ddr3_zport.sv $R/gnet/gnet_ddr3_mirror.sv"
VF="-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING --x-assign 0 --x-initial 0"
cd "$ROOT"
# shellcheck disable=SC2086
nice -n 15 verilator --cc --exe --build -j 2 -O2 $VF --public-flat-rw --top-module zd3_top -GZSG_INFL=$INFL \
  --Mdir "$OBJ" -o tb_zd3 "$HERE/zd3_top.sv" $ZF $DF "$HERE/tb_zd3.cpp" > "$OBJ.log" 2>&1 \
  || { grep -m 30 -E '%Error|error:' "$OBJ.log"; exit 1; }
echo "built $OBJ/tb_zd3"
