#!/bin/bash
# Full-system simulation of a tree with the ZN-2 board in the CPU group
# (branch gnet-cpu50, GNET_Z1_CPU50.qsf: GNET_ZN2 + GNET_CPU50, CPU_CLK_SPLIT
# = 1, CLK_FAST_RATIO = 2, GTE_NARROW_MUL = 3), read only: the committed rtl/
# is exported to work/$TAG/src and built. Run with -cpu_mhz 50.
#   TAG=zn2c50 sim/fullsys/zn2cpu50.sh [ref]     (default ref: gnet-cpu50)
# EXTRA_GEN_ADD: more psx_top generics (e.g. -gRAM_READ_NOWAIT=1); FS_EARLY_READY=1:
# sdram.sv EARLY_READY = 1 (PSX.sv GNET_EARLY_READY); see zn2full.sh.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REF=${1:-gnet-cpu50}
T=${TAG:-zn2c50}
S=$HERE/work/$T/src
rm -rf $S; mkdir -p $S
git -C $HERE/../.. archive $(git -C $HERE/../.. rev-parse $REF) rtl sim/system/src/mem | tar -x -C $S
git -C $HERE/../.. rev-parse $REF > $S/COMMIT
R=$S/rtl
C=$R/gnet/cdc; P=$R/gnet/cpu_split
export TAG=$T RTL_ROOT=$S GTE_NARROW_MUL=3 FS_CPU50=1
export EXTRA_VHD="$C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd $P/cpu_gpu_bridge.vhd $P/cpu_spu_bridge.vhd $P/cpu_reset_fill.vhd $P/cpu_split.vhd $R/gnet/zn_cat702.vhd $R/gnet/znmcu.vhd $S/../patched/gnet/zn_sio0.vhd $S/../patched/gnet/zn2_io.vhd $S/../patched/gnet/zn2_board.vhd $S/../patched/gnet/zn2_cardmem.vhd $R/gnet/zn2_cdc.vhd"
export EXTRA_GEN="-gZN2_BOARD=1 -gCPU_CLK_SPLIT=1 -gCLK_FAST_RATIO=2 ${EXTRA_GEN_ADD:-}"
export EXTRA_SV="$R/gnet/gnet_fc.sv $R/gnet/gnet_ctrl.sv $R/gnet/gnet_flash.sv $R/gnet/gnet_rf5c296.sv $R/gnet/gnet_ata.sv $HERE/fs_ch3_arb.sv"
$HERE/convert.sh $S psx_top
printf 'RTL_ROOT=%s\nEXTRA_SV="%s"\nexport FS_CPU50=1\nexport FS_DL=\nexport FS_EARLY_READY=%s\n' "$S" "$EXTRA_SV" "${FS_EARLY_READY:-}" > $HERE/work/$T/build.env
$HERE/build.sh
