#!/bin/bash
# Elaboration check of the VHDL side of the journal (psx_top, psx_mister,
# zn2_board, zn2_cardmem): ghdl --synth of psx_top as the GNET_Z1FULLR
# configuration (zn2full.sh generics), with CARD_JOURNAL 0 and 1. Uses the
# working tree (copied to work/vhdl/src) and sim/fullsys/convert.sh.
#   sim/i9/vhdl_check.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
F=$ROOT/sim/fullsys
for cj in 0 1; do
  T=i9vhdl$cj
  S=$F/work/$T/src
  rm -rf "$S"; mkdir -p "$S/sim/system/src"
  cp -R "$ROOT/rtl" "$S/rtl"; cp -R "$ROOT/sim/system/src/mem" "$S/sim/system/src/mem"
  R=$S/rtl; C=$R/gnet/cdc; P=$R/gnet/cpu_split
  export TAG=$T GTE_NARROW_MUL=3
  export EXTRA_VHD="$C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd $P/cpu_gpu_bridge.vhd $P/cpu_spu_bridge.vhd $P/cpu_reset_fill.vhd $P/cpu_split.vhd $R/gnet/zn_cat702.vhd $R/gnet/znmcu.vhd $S/../patched/gnet/zn_sio0.vhd $S/../patched/gnet/zn2_io.vhd $S/../patched/gnet/zn2_board.vhd $S/../patched/gnet/zn2_cardmem.vhd $R/gnet/zn2_cdc.vhd $R/gnet/zoom_cdc.vhd $R/gnet/zn2_ch3_arb.vhd $R/gnet/zn_dbg_regs.vhd"
  export EXTRA_GEN="-gZN2_BOARD=1 -gCPU_CLK_SPLIT=1 -gCLK_FAST_RATIO=2 -gZOOM_BOARD=1 -gZOOM_INFL=8 -gZN2_READ_OVERLAP=1 -gRAM_READ_NOWAIT=1 -gCARD_JOURNAL=$cj"
  export EXTRA_TOPS=""
  if nice -n 15 "$F/convert.sh" "$S" psx_top > "$F/work/$T/convert.out" 2>&1; then
    echo "ok   ghdl --synth psx_top, CARD_JOURNAL=$cj ($(grep -c '' "$F/work/$T/psx_top.v") netlist lines)"
  else
    echo "FAIL ghdl --synth psx_top, CARD_JOURNAL=$cj: see $F/work/$T/convert.out"; tail -20 "$F/work/$T/convert.out"
  fi
done
