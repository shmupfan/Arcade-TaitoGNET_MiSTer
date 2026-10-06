#!/bin/bash
# Compile the PSX_MiSTer core with the G-NET ZN-2 board (psx_top ZN2_BOARD = 1)
# for NVC system simulation (docs/zn2_layer_design.md 16):
#   sim/zn2/system/build.sh <workdir> [split]
# split 1 also builds the gnet_fc library with CLK_HZ 50,000,000 (cosim50)
# for psx_top CPU_CLK_SPLIT = 1; the rtl/gnet/cdc, cpu_split, zn2_cdc and
# zn2_ch3_arb files are analysed in both cases.
# gnet_fc (SystemVerilog) runs in Verilator behind VHPIDIRECT
# (sim/zn2/cosim); sdram.sv goes through the R1 simulation copy
# (tools/r1/mem_lat/sdram_sim_copy.py). The GPU files get the M1 simulation
# patches (sim/m1/build.sh, upstream RTL untouched).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
W=$1
SPLIT=${2:-0}
mkdir -p "$W"
cd "$W"
R=$ROOT/rtl; M=$ROOT/sim/system/src/mem
NV="nvc --std=2008 -H 1g"
"$ROOT/sim/zn2/cosim/build_gnet_fc.sh" "$W/cosim" > /dev/null
if [ "$SPLIT" = 1 ]; then
  GNET_FC_CLK_HZ=50000000 "$ROOT/sim/zn2/cosim/build_gnet_fc.sh" "$W/cosim50" > /dev/null
fi
C=$R/gnet/cdc; S=$R/gnet/cpu_split

# GPU simulation patches (as sim/m1/build.sh)
P=$W/patched; mkdir -p $P
DIVZ="inout div_type := (start => 'Z', done => 'Z', dividend => (others => 'Z'), divisor => (others => 'Z'), quotient => (others => 'Z'), remainder => (others => 'Z'));"
for f in gpu_line gpu_poly; do sed -E "s/inout div_type;/$DIVZ/" $R/$f.vhd > $P/$f.vhd; done
sed -i '' -E 's/to_integer\(xStart\(43 downto 32\)\) > drawingAreaRight\)/to_integer(xStart(43 downto 32)) > to_integer(drawingAreaRight))/' $P/gpu_poly.vhd
sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu.vhd > $P/gpu.vhd
sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu_vram2cpu.vhd > $P/gpu_vram2cpu.vhd
for f in gpu_videoout_async gpu_videoout_sync gpu_videoout; do
  python3 "$ROOT/sim/m1/wrap_to_unsigned.py" $R/$f.vhd > $P/$f.vhd
done
python3 "$ROOT/tools/r1/mem_lat/sdram_sim_copy.py" $R/sdram.sv $W/sdram_sim.sv

$NV --work=altera_mf -a "$HERE/altera_mf_stub.vhd"
MEMF="$M/dpram.vhd $M/RamMLAB.vhd $M/SyncFifo.vhd $M/SyncRamDualByteEnable.vhd $R/SyncFifoFallThrough.vhd $R/SyncFifoFallThroughMLAB.vhd $R/SyncRam.vhd $R/SyncRamDual.vhd $R/SyncRamDualNotPow2.vhd"
$NV --work=mem -L . -a --relaxed $MEMF
$NV --work=work -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd \
  $R/export.vhd $R/divider.vhd $R/pGPU.vhd $R/mul32u.vhd $R/mul9s.vhd \
  $R/gpu_fillVram.vhd $R/gpu_cpu2vram.vhd $R/gpu_vram2vram.vhd $P/gpu_vram2cpu.vhd $P/gpu_line.vhd \
  $R/gpu_rect.vhd $P/gpu_poly.vhd $R/gpu_pixelpipeline.vhd $R/gpu_overlay.vhd $R/gpu_dither.vhd \
  $P/gpu_videoout_async.vhd $P/gpu_videoout_sync.vhd $R/gpu_crosshair.vhd $R/justifier_sensor.vhd \
  $P/gpu_videoout.vhd $P/gpu.vhd $R/irq.vhd $R/pJoypad.vhd $R/joypad_pad.vhd $R/joypad_mem.vhd $R/joypad.vhd \
  $R/timer.vhd $R/dma.vhd $R/exp2.vhd $R/pGTE.vhd $R/gte_mac0.vhd $R/gte_mac123.vhd $R/gte_UNRDivide.vhd \
  $R/gte.vhd $R/mdec.vhd $R/cd_xa_zigzag.vhd $R/cd_xa.vhd $R/cd_top.vhd $R/memctrl.vhd $R/sio.vhd \
  $R/spu_ram.vhd $R/spu_gauss.vhd $R/spu.vhd $R/datacache.vhd $R/cpu.vhd $R/memorymux.vhd $R/memcard.vhd \
  $R/statemanager.vhd $R/savestates.vhd $R/cheats.vhd \
  $ROOT/sim/zn2/cosim/gnet_fc_cosim.vhd $R/gnet/zn_cat702.vhd $R/gnet/znmcu.vhd $R/gnet/zn_sio0.vhd \
  $R/gnet/zn2_io.vhd $R/gnet/zn2_board.vhd $R/gnet/zn2_cardmem.vhd \
  $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd \
  $C/cdc_fifo.vhd $C/tick_accum.vhd $S/cpu_gpu_bridge.vhd $S/cpu_spu_bridge.vhd $S/cpu_reset_fill.vhd $S/cpu_split.vhd \
  $R/gnet/zn2_cdc.vhd $R/gnet/zn2_ch3_arb.vhd $R/gnet/zn_dbg_regs.vhd \
  $R/psx_top.vhd > analyse.log 2>&1 || { grep -m 20 -B2 -A6 "Error" analyse.log; exit 1; }
$NV --work=work -L . -a --relaxed $W/sdram_sim.sv >> analyse.log 2>&1 || { tail -20 analyse.log; exit 1; }
echo "analysed into $W"
