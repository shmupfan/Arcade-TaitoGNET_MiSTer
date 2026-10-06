#!/bin/bash
# Integration bench for the Taito Zoom board in the G-NET core
# (docs/zoom_board_design.md 14), Verilator 5.050:
#   1. GHDL (oss-cad-suite) synthesises sim/zoomlink/zl_vtop.vhd to Verilog:
#      zn2_board (ZOOM = 1) with zn2_io, zn_sio0, the CAT702 pair and znmcu,
#      zoom_cdc, zoom_sdram_link, zn2_ch3_arb and every rtl/gnet/cdc block
#      they use; gnet_fc and zoom_board stay components.
#   2. Verilator builds that netlist with gnet_fc (and its blocks) and
#      rtl/zoom as SystemVerilog, and tb_zoomlink.cpp.
#   3. Verilator builds the reference: zoom_board alone with the same
#      parameters, its host port and line port driven directly
#      (tb_zoomref.cpp, the same main-CPU script, no crossings).
#
#   sim/zoomlink/build.sh            output in sim/zoomlink/work/ (gitignored)
#
# Builds run under nice -n 15 with -j 2.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
R=$ROOT/rtl; G=$R/gnet; C=$G/cdc
OSS=${OSS_CAD:-$HOME/tools/oss-cad-suite}
# TMS_MAME=1: the TMS57002 parameter set bit-exact with MAME 0.288 (for the
# audio comparison against MAME); default 0, the core's (User's Guide)
# TIMER_X=1: the MN10200 timers in MAME's phase (TIMER_EXACT)
W=$HERE/work/build${TMS_MAME:+_m$TMS_MAME}${TIMER_X:+_t$TIMER_X}${ZOOM_RTL:+_alt}
mkdir -p "$W/ghdl"
GH="$OSS/bin/ghdl"
export GHDL_PREFIX=$OSS/lib/ghdl
A="$GH -a --std=08 -frelaxed --workdir=$W/ghdl"

$A $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd \
   $HERE/zl_dpram.vhd $G/zn_cat702.vhd $G/znmcu.vhd $G/zn_sio0.vhd $G/zn2_io.vhd $G/zn2_board.vhd \
   $G/zoom_cdc.vhd $G/zoom_sdram_link.vhd $G/zn2_ch3_arb.vhd $HERE/zl_vtop.vhd > "$W/ghdl_analyse.log" 2>&1 \
   || { grep -m 20 -i error "$W/ghdl_analyse.log"; exit 1; }
nice -n 15 $GH --synth --std=08 -frelaxed --workdir=$W/ghdl -gTMS_MAME=${TMS_MAME:-0} -gTIMER_X=${TIMER_X:-0} --out=verilog zl_vtop > "$W/zl_vtop.v" 2> "$W/ghdl_synth.log" \
   || { grep -v -i warning "$W/ghdl_synth.log" | head -40; exit 1; }
# GHDL writes a signal with an initial value and a concurrent assignment as
# "always @* x = y; initial x = <init>;", which never updates when y is a
# constant (sim/fullsys/fix_netlist.py on branch fullsys-sim, W8): make every
# "always @*" an always_comb and drop those initials
python3 - "$W/zl_vtop.v" <<'PY'
import re, sys
fn = sys.argv[1]
t = open(fn).read()
t, n1 = re.subn(r'  always @\*\n    (\S+) = ([^;]+); // \(isignal\)\n  initial\n    \1 = [^;]+;\n',
                r'  always_comb\n    \1 = \2; // (isignal)\n', t)
t, n2 = re.subn(r'always @\*', 'always_comb', t)
open(fn, 'w').write(t)
print(f'netlist: {n1} isignal initials dropped, {n1 + n2} always_comb')
PY

GF="$G/gnet_ctrl.sv $G/gnet_flash.sv $G/gnet_rf5c296.sv $G/gnet_ata.sv $G/gnet_fc.sv"
# ZOOM_RTL=<dir>: the rtl/zoom files from another tree (a comparison build)
Z=${ZOOM_RTL:-$R/zoom}
ZF="$Z/mn10200_decode.sv $Z/mn10200_rf.sv $Z/mn10200_core.sv $Z/mn10200_periph.sv $Z/mn10200.sv
 $Z/zsg2_ram.sv $Z/zsg2_fetch.sv $Z/zsg2.sv $Z/tms57002.sv $Z/zoom_tbase.sv $Z/zoom_tmsfeed.sv
 $Z/zoom_pcache.sv $Z/zoom_wram.sv $Z/zoom_mbox.sv $Z/zoom_host.sv $Z/zoom_bus.sv
 $Z/zoom_memarb.sv $Z/zoom_out.sv $Z/zoom_board.sv"
VF="-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING --x-assign 0 --x-initial 0"

cd "$ROOT"
# shellcheck disable=SC2086
nice -n 15 verilator --cc --exe --build -j 2 -O2 $VF --public-flat-rw --top-module zl_vtop \
  --Mdir "$W/obj_link" -o tb_zoomlink "$W/zl_vtop.v" $GF $ZF "$HERE/tb_zoomlink.cpp" > "$W/verilator_link.log" 2>&1 \
  || { grep -m 30 -E '%Error|error:' "$W/verilator_link.log"; exit 1; }
echo "built $W/obj_link/tb_zoomlink"
# shellcheck disable=SC2086
nice -n 15 verilator --cc --exe --build -j 2 -O2 $VF --public-flat-rw --top-module zoom_board \
  -GCLK_H=4 -GPACE_CAP=1024 -GZSG_INFL=4 -GTIMER_EXACT=0 -GDEBUG=0 \
  --Mdir "$W/obj_ref" -o tb_zoomref $ZF "$HERE/tb_zoomref.cpp" > "$W/verilator_ref.log" 2>&1 \
  || { grep -m 30 -E '%Error|error:' "$W/verilator_ref.log"; exit 1; }
echo "built $W/obj_ref/tb_zoomref"
