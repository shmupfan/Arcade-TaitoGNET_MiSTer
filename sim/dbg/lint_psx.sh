#!/bin/bash
# Verilator lint of PSX.sv as the G-NET test revisions build it
# (docs/hw_debug_overlay.md). The VHDL entities PSX.sv instantiates
# (psx_mister, zn_dbg_overlay, cdc_handshake, zn2_ch3_arb) become empty
# modules with their ports (sim/dbg/vhdl_stub.py), so port names, directions
# and widths at the PSX.sv boundary are checked; Intel primitives and the
# PLL wrappers are left out (MODMISSING is the only error class expected).
#
#   sim/dbg/lint_psx.sh cpu50   GNET_Z1_CPU50 macros
#   sim/dbg/lint_psx.sh z1      GNET_Z1 macros
#   sim/dbg/lint_psx.sh psx     upstream PSX revision macros
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
W="$HERE/work"
mkdir -p "$W"
[ -f "$W/build_id.v" ] || echo '`define BUILD_DATE "000000"' > "$W/build_id.v"
python3 "$HERE/vhdl_stub.py" --case-from "$ROOT/PSX.sv" "$W/stubs.sv" "$ROOT/rtl/psx_mister.vhd" "$ROOT/rtl/gnet/zn_dbg_overlay.vhd" \
   "$ROOT/rtl/gnet/cdc/cdc_handshake.vhd" "$ROOT/rtl/gnet/zn2_ch3_arb.vhd"

LEAN="-DGNET_LEAN=1 -DGNET_NO_CD=1 -DGNET_NO_PADS=1 -DGNET_NO_SAVESTATES=1 -DGNET_NO_CHEATS=1 -DGNET_NO_MDEC=1 -DGNET_VRAM_2MB=1 -DMISTER_FB=1 -DMISTER_DISABLE_YC=1 -DMISTER_DISABLE_ADAPTIVE=1 -DMISTER_DISABLE_ALSA=1"
case "${1:-cpu50}" in
   cpu50) DEFS="$LEAN -DGNET_ZN2=1 -DGNET_CPU50=1 -DGNET_CLK_RATIO2=1 -DGNET_GTE_NARROW_MUL=3" ;;
   z1)    DEFS="$LEAN -DGNET_ZN2=1 -DGNET_GTE_NARROW_MUL=1" ;;
   psx)   DEFS="-DMISTER_FB=1" ;;
   *)     echo "usage: $0 cpu50|z1|psx"; exit 1 ;;
esac

cd "$ROOT"
nice -n 15 verilator --lint-only -Wall -Wno-fatal -Wno-PROCASSWIRE --error-limit 500 $DEFS -Isys -I"$W" --top-module emu \
   PSX.sv sys/hps_io.sv sys/gamma_corr.sv sys/video_freak.sv sys/math.sv rtl/sdram.sv rtl/savestate_ui.sv \
   rtl/hps_ext.v "$W/stubs.sv" "$HERE/intel_stubs.sv" > "$W/lint_${1:-cpu50}.log" 2>&1 || true
echo "errors by class:"
grep -E "^%Error" "$W/lint_${1:-cpu50}.log" | sed -E 's/:[0-9]+:[0-9]+:/:/' | sort | uniq -c
echo "warnings on the debug overlay lines (zn_dbg, dbg_ovl, rgb_dbg, status[101]):"
grep -E "^%Warning" -A3 "$W/lint_${1:-cpu50}.log" | grep -E "zn_dbg|dbg_ovl|rgb_dbg|status\[101\]|hres_dbl" || echo "   none"
