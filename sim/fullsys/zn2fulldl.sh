#!/bin/bash
# Full-system simulation of the release tree with the MiSTer download path
# (docs/i12_ddr3_load.md 6): zn2full.sh's top (GNET_ZN2 + GNET_CPU50 +
# GNET_ZOOM + GNET_DDR3_ARB) with FS_DL=1, so gen_top.py includes
# fs_psxdl_full.svh (PSX.sv's download path, channel 3 handshake,
# zn2_ch3_arb, flash mirror, DDR3 arbiter). The psx_top generics are those
# of GNET_Z1FULLR (PSX.sv localparams at the macros of GNET_Z1FULLR.qsf).
# Two Verilator builds from one netlist:
#   work/$TAG/obj_dir      PSX.sv without GNET_DDR3_LOAD (GNET_Z1FULLR)
#   work/$TAG/obj_ddr3     with +define+GNET_DDR3_LOAD=1 (GNET_Z1FULLD)
#   TAG=i12 sim/fullsys/zn2fulldl.sh [ref]     (default ref: HEAD)
# Run with -cpu_mhz 50 -dqm 1 -dl <list> (index@address for a DDR3 load).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REF=${1:-HEAD}
T=${TAG:-i12}
S=$HERE/work/$T/src
rm -rf $S; mkdir -p $S
git -C $HERE/../.. archive $(git -C $HERE/../.. rev-parse $REF) rtl sim/system/src/mem | tar -x -C $S
git -C $HERE/../.. rev-parse $REF > $S/COMMIT
R=$S/rtl
sed -i '' "s#\"rtl/zoom/#\"$R/zoom/#g" $R/zoom/*.sv
C=$R/gnet/cdc; P=$R/gnet/cpu_split
export TAG=$T RTL_ROOT=$S GTE_NARROW_MUL=3 FS_CPU50=1 FS_ZOOM=1 FS_DDR3ARB=1 FS_DL=1 FS_EARLY_READY=1
export EXTRA_VHD="$C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd $P/cpu_gpu_bridge.vhd $P/cpu_spu_bridge.vhd $P/cpu_reset_fill.vhd $P/cpu_split.vhd $R/gnet/zn_cat702.vhd $R/gnet/znmcu.vhd $S/../patched/gnet/zn_sio0.vhd $S/../patched/gnet/zn2_io.vhd $S/../patched/gnet/zn2_board.vhd $S/../patched/gnet/zn2_cardmem.vhd $R/gnet/zn2_cdc.vhd $R/gnet/zoom_cdc.vhd $R/gnet/zn2_ch3_arb.vhd $R/gnet/zn_dbg_regs.vhd $HERE/fs_ch3_cdc.vhd"
# GNET_Z1FULLR's psx_top generics (PSX.sv 1562-1680 with that revision's macros)
export EXTRA_GEN="-gZN2_BOARD=1 -gCPU_CLK_SPLIT=1 -gCLK_FAST_RATIO=2 -gZOOM_BOARD=1 -gZOOM_INFL=8 -gZN2_READ_OVERLAP=1 -gRAM_READ_NOWAIT=1 -gHAS_MDEC=1 -gRECT_FLIP=1 -gGPU_READ_INFL=2 -gTEX_FETCH_QW=4 -gTEX_FETCH_ROWS=2 -gTEX_MISS_DELAY=13 ${EXTRA_GEN_ADD:-}"
export EXTRA_TOPS="zn2_ch3_arb fs_ch3_cdc"
Z=$R/zoom
ZSV="$Z/mn10200_decode.sv $Z/mn10200_rf.sv $Z/mn10200_core.sv $Z/mn10200_periph.sv $Z/mn10200.sv $Z/zsg2_ram.sv $Z/zsg2_fetch.sv $Z/zsg2.sv $Z/tms57002.sv $Z/zoom_tbase.sv $Z/zoom_tmsfeed.sv $Z/zoom_pcache.sv $Z/zoom_wram.sv $Z/zoom_mbox.sv $Z/zoom_host.sv $Z/zoom_bus.sv $Z/zoom_memarb.sv $Z/zoom_out.sv $Z/zoom_mix.sv $Z/zoom_board.sv"
W=$HERE/work/$T
export EXTRA_SV="$R/gnet/gnet_fc.sv $R/gnet/gnet_ctrl.sv $R/gnet/gnet_flash.sv $R/gnet/gnet_rf5c296.sv $R/gnet/gnet_ata.sv $ZSV $R/gnet/gnet_ddr3_arb.sv $R/gnet/gnet_ddr3_zport.sv $R/gnet/gnet_ddr3_mirror.sv $R/gnet/gnet_ddr3_gmux.sv $R/gnet/gnet_ddr3_flcopy.sv $W/zn2_ch3_arb.v $W/fs_ch3_cdc.v"
$HERE/convert.sh $S psx_top
printf 'RTL_ROOT=%s\nEXTRA_SV="%s"\nexport FS_CPU50=1\nexport FS_ZOOM=1\nexport FS_DDR3ARB=1\nexport FS_DL=1\nexport FS_EARLY_READY=1\n' "$S" "$EXTRA_SV" > $W/build.env
MDIR=obj_dir $HERE/build.sh
MDIR=obj_ddr3 VFLAGS="+define+GNET_DDR3_LOAD=1" $HERE/build.sh
