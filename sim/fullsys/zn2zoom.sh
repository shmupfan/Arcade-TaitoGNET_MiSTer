#!/bin/bash
# Full-system simulation of a tree with the ZN-2 board in the CPU group and
# the Taito Zoom board (branch zoom-into-z1, GNET_Z1_ZOOM.qsf: GNET_ZN2 +
# GNET_CPU50 + GNET_ZOOM + GNET_ZOOM_SDRAM), read only: the committed rtl/ is
# exported to work/$TAG/src. zn2_ch3_arb (three ports) and zoom_sdram_link
# are synthesised as extra tops and wired as PSX.sv does. Run with -cpu_mhz 50.
#   TAG=zn2zoom sim/fullsys/zn2zoom.sh [ref]     (default ref: zoom-into-z1)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REF=${1:-zoom-into-z1}
T=${TAG:-zn2zoom}
S=$HERE/work/$T/src
rm -rf $S; mkdir -p $S
git -C $HERE/../.. archive $(git -C $HERE/../.. rev-parse $REF) rtl sim/system/src/mem | tar -x -C $S
git -C $HERE/../.. rev-parse $REF > $S/COMMIT
R=$S/rtl
# sim-only copy: the MN10200 microcode hex paths are relative to the Quartus
# project root; make them absolute for the simulation binary
sed -i '' "s#\"rtl/zoom/#\"$R/zoom/#g" $R/zoom/*.sv
C=$R/gnet/cdc; P=$R/gnet/cpu_split
export TAG=$T RTL_ROOT=$S GTE_NARROW_MUL=3 FS_CPU50=1 FS_ZOOM=1
export EXTRA_VHD="$C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd $P/cpu_gpu_bridge.vhd $P/cpu_spu_bridge.vhd $P/cpu_reset_fill.vhd $P/cpu_split.vhd $R/gnet/zn_cat702.vhd $R/gnet/znmcu.vhd $S/../patched/gnet/zn_sio0.vhd $S/../patched/gnet/zn2_io.vhd $S/../patched/gnet/zn2_board.vhd $S/../patched/gnet/zn2_cardmem.vhd $R/gnet/zn2_cdc.vhd $R/gnet/zoom_cdc.vhd $R/gnet/zn2_ch3_arb.vhd $R/gnet/zoom_sdram_link.vhd"
export EXTRA_GEN="-gZN2_BOARD=1 -gCPU_CLK_SPLIT=1 -gCLK_FAST_RATIO=2 -gZOOM_BOARD=1 -gZOOM_INFL=4"
export EXTRA_TOPS="zn2_ch3_arb zoom_sdram_link"
Z=$R/zoom
ZSV="$Z/mn10200_decode.sv $Z/mn10200_rf.sv $Z/mn10200_core.sv $Z/mn10200_periph.sv $Z/mn10200.sv $Z/zsg2_ram.sv $Z/zsg2_fetch.sv $Z/zsg2.sv $Z/tms57002.sv $Z/zoom_tbase.sv $Z/zoom_tmsfeed.sv $Z/zoom_pcache.sv $Z/zoom_wram.sv $Z/zoom_mbox.sv $Z/zoom_host.sv $Z/zoom_bus.sv $Z/zoom_memarb.sv $Z/zoom_out.sv $Z/zoom_mix.sv $Z/zoom_board.sv"
W=$HERE/work/$T
export EXTRA_SV="$R/gnet/gnet_fc.sv $R/gnet/gnet_ctrl.sv $R/gnet/gnet_flash.sv $R/gnet/gnet_rf5c296.sv $R/gnet/gnet_ata.sv $ZSV $W/zn2_ch3_arb.v $W/zoom_sdram_link.v"
$HERE/convert.sh $S psx_top
printf 'RTL_ROOT=%s\nEXTRA_SV="%s"\nexport FS_CPU50=1\nexport FS_ZOOM=1\nexport FS_DL=\n' "$S" "$EXTRA_SV" > $W/build.env
$HERE/build.sh
