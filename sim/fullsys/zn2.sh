#!/bin/bash
# Full-system simulation with the ZN-2 board and G-NET glue (zn2-layer
# branch, psx_top ZN2_BOARD = 1), read only: the branch's committed rtl/
# is exported to work/$TAG/src (COMMIT records the hash), converted and built.
#   sim/fullsys/zn2.sh [ref]       (default ref: zn2-layer; TAG default zn2;
#   GTE_NARROW_MUL passes through to convert.sh, default 0; OVERLAY below)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REF=${1:-zn2-layer}
T=${TAG:-zn2}
S=$HERE/work/$T/src
rm -rf $S; mkdir -p $S
git -C $HERE/../.. archive $(git -C $HERE/../.. rev-parse $REF) rtl sim/system/src/mem | tar -x -C $S
git -C $HERE/../.. rev-parse $REF > $S/COMMIT
# EXTRA_VHD_ADD: further VHDL files of newer trees (rtl/ paths are relative
# to the export, e.g. "rtl/gnet/zn_dbg_regs.vhd"), analysed after the board.
# OVERLAY="<ref>:<path> ...": files taken from another commit on top of the
# export (e.g. main's rtl/gpu.vhd before zn2-layer merges it); recorded in COMMIT
for o in ${OVERLAY:-}; do
  git -C $HERE/../.. show "$o" > "$S/${o#*:}"
  echo "overlay $(git -C $HERE/../.. rev-parse --short ${o%%:*}):${o#*:}" >> $S/COMMIT
done
R=$S/rtl
export TAG=$T RTL_ROOT=$S
export EXTRA_VHD="$R/gnet/zn_cat702.vhd $R/gnet/znmcu.vhd $S/../patched/gnet/zn_sio0.vhd $S/../patched/gnet/zn2_io.vhd $S/../patched/gnet/zn2_board.vhd $S/../patched/gnet/zn2_cardmem.vhd ${EXTRA_VHD_ADD:-}"
export EXTRA_GEN="-gZN2_BOARD=1"
export EXTRA_SV="$R/gnet/gnet_fc.sv $R/gnet/gnet_ctrl.sv $R/gnet/gnet_flash.sv $R/gnet/gnet_rf5c296.sv $R/gnet/gnet_ata.sv"
$HERE/convert.sh $S psx_top
printf 'RTL_ROOT=%s\nEXTRA_SV="%s"\nexport FS_DL=%s\n' "$S" "$EXTRA_SV" "${FS_DL:-}" > $HERE/work/$T/build.env
$HERE/build.sh
