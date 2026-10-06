#!/bin/bash
# Full-system simulation of branch r1-cpu50 (docs/fullsys_sim.md 5.4), read
# only: the committed rtl/ is exported to work/$TAG/src and built with the
# CPU group split (CPU_CLK_SPLIT = 1, CLK_FAST_RATIO = 2, GTE_NARROW_MUL = 3,
# as GNET_CPU50_B1.qsf) or, with SPLIT=0, the same tree on the PS1 clocks.
#   TAG=cpu50 sim/fullsys/cpu50.sh [ref]            (default ref: r1-cpu50)
#   TAG=cpu50s0 SPLIT=0 sim/fullsys/cpu50.sh [ref]
# The ZN-2 board is not on r1-cpu50: the G-NET BIOS runs on the PS1 memory map.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REF=${1:-r1-cpu50}
T=${TAG:-cpu50}
SPLIT=${SPLIT:-1}
S=$HERE/work/$T/src
rm -rf $S; mkdir -p $S
git -C $HERE/../.. archive $(git -C $HERE/../.. rev-parse $REF) rtl sim/system/src/mem | tar -x -C $S
git -C $HERE/../.. rev-parse $REF > $S/COMMIT
R=$S/rtl
C=$R/gnet/cdc; P=$R/gnet/cpu_split
export TAG=$T RTL_ROOT=$S GTE_NARROW_MUL=3
export EXTRA_VHD="$C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd $P/cpu_gpu_bridge.vhd $P/cpu_spu_bridge.vhd $P/cpu_reset_fill.vhd $P/cpu_split.vhd"
if [ "$SPLIT" = 1 ]; then
  export EXTRA_GEN="-gCPU_CLK_SPLIT=1 -gCLK_FAST_RATIO=2" FS_CPU50=1
else
  export EXTRA_GEN="-gCPU_CLK_SPLIT=0 -gCLK_FAST_RATIO=3" FS_CPU50=0
fi
$HERE/convert.sh $S psx_top
printf 'RTL_ROOT=%s\nEXTRA_SV=""\nexport FS_CPU50=%s\n' "$S" "$FS_CPU50" > $HERE/work/$T/build.env
$HERE/build.sh
