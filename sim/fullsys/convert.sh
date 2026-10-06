#!/bin/bash
# Full-system simulation, step 1: PSX_MiSTer VHDL (LEAN generics) to one
# Verilog netlist with GHDL synthesis (ghdl --synth --out=verilog).
#   sim/fullsys/convert.sh [rtl_root] [top]
# rtl_root: directory holding rtl/ (default: this checkout). Output in
# sim/fullsys/work/<tag>/ (gitignored). Upstream RTL is never edited;
# simulation-only copies go to work/<tag>/patched.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$(cd "$HERE/../.." && pwd)}
TOP=${2:-psx_mister}
TAG=${TAG:-main}
OSS=${OSS_CAD:-$HOME/tools/oss-cad-suite}
export PATH=$OSS/bin:$PATH GHDL_PREFIX=$OSS/lib/ghdl
W=$HERE/work/$TAG; mkdir -p "$W/ghdl" "$W/patched"
R=$ROOT/rtl; M=$ROOT/sim/system/src/mem; P=$W/patched
G="ghdl -a --std=08 -frelaxed --workdir=$W/ghdl -P$W/ghdl"
cat > $P/altera_mf_stub.vhd <<'X'
package altera_mf_components is
end package;
X
$G --work=altera_mf $P/altera_mf_stub.vhd
# Simulation-only copies of upstream files (W1 to W3, W5: patch_vhdl.py)
python3 $HERE/patch_vhdl.py $R $P > /dev/null
# W4 RAM primitives: fs_mem.vhd shims (same entities) to Verilog models.
MEMF="$HERE/fs_mem.vhd $M/SyncFifo.vhd $R/SyncFifoFallThrough.vhd $R/SyncFifoFallThroughMLAB.vhd"
$G --work=mem $MEMF > $W/analyse_mem.log 2>&1 || { grep -A3 error $W/analyse_mem.log | head -40; exit 1; }
FILES="$HERE/fs_util.vhd $HERE/fs_mem.vhd $P/export.vhd $R/divider.vhd $R/pGPU.vhd $R/mul32u.vhd $R/mul9s.vhd $R/cheats.vhd
 $R/gpu_fillVram.vhd $R/gpu_cpu2vram.vhd $R/gpu_vram2vram.vhd $R/gpu_vram2cpu.vhd $P/gpu_line.vhd $R/gpu_rect.vhd
 $P/gpu_poly.vhd $R/gpu_pixelpipeline.vhd $P/gpu_overlay.vhd $R/gpu_dither.vhd $R/gpu_videoout_async.vhd
 $R/gpu_videoout_sync.vhd $P/gpu_crosshair.vhd $P/justifier_sensor.vhd $R/gpu_videoout.vhd $P/gpu.vhd $R/irq.vhd
 $R/pJoypad.vhd $R/joypad_pad.vhd $R/joypad_mem.vhd $R/joypad.vhd $R/timer.vhd $R/dma.vhd $R/exp2.vhd $R/pGTE.vhd
 $R/gte_mac0.vhd $R/gte_mac123.vhd $R/gte_UNRDivide.vhd $R/gte.vhd $R/mdec.vhd $R/cd_xa_zigzag.vhd $R/cd_xa.vhd
 $R/cd_top.vhd $R/memctrl.vhd $R/sio.vhd $R/spu_ram.vhd $R/spu_gauss.vhd $R/spu.vhd $R/datacache.vhd $R/cpu.vhd
 $R/memorymux.vhd $R/memcard.vhd $R/statemanager.vhd $R/savestates.vhd ${EXTRA_VHD:-} $R/psx_top.vhd $R/psx_mister.vhd"
$G --work=work $FILES > $W/analyse.log 2>&1 || { grep -A3 "error" $W/analyse.log | head -40; exit 1; }
GEN="-gHAS_CD=0 -gHAS_PADS=0 -gHAS_SAVESTATES=0 -gHAS_CHEATS=0 -gHAS_MDEC=0 -gVRAM_Y_BITS=10 -gGTE_NARROW_MUL=${GTE_NARROW_MUL:-0} ${EXTRA_GEN:-}"
time ghdl --synth --std=08 -frelaxed --workdir=$W/ghdl -P$W/ghdl $GEN --out=verilog $TOP > $W/$TOP.v 2> $W/synth.log || { grep -v -i warning $W/synth.log | head -40; exit 1; }
python3 $HERE/fix_netlist.py $W/$TOP.v
# EXTRA_TOPS: further entities PSX.sv instantiates next to psx_top (e.g.
# zn2_ch3_arb, zoom_sdram_link), each synthesised on its own; their internal
# modules get the prefix <top>__ so they cannot clash with psx_top.v's
for T in ${EXTRA_TOPS:-}; do
  ghdl --synth --std=08 -frelaxed --workdir=$W/ghdl -P$W/ghdl --out=verilog $T > $W/$T.v 2> $W/synth_$T.log || { grep -v -i warning $W/synth_$T.log | head -40; exit 1; }
  python3 $HERE/fix_netlist.py $W/$T.v
  python3 - "$W/$T.v" "$T" <<'PYEOF'
import re, sys
fn, top = sys.argv[1], sys.argv[2]
s = open(fn).read()
mods = [m for m in re.findall(r'^module\s+(\w+)', s, re.M) if m != top]
for m in sorted(mods, key=len, reverse=True):
    s = re.sub(r'\b%s\b' % re.escape(m), top + '__' + m, s)
open(fn, 'w').write(s)
PYEOF
  ls -l $W/$T.v
done
ls -l $W/$TOP.v
