#!/bin/bash
# M1: compile the PSX_MiSTer GPU and the replay testbench with NVC (VHDL-2008).
# Memory models are PSX_MiSTer's simulation versions (sim/system/src/mem),
# FIFOs and RAM wrappers are the plain-VHDL ones from rtl/.
# M1_BUILD=<dir> builds into sim/m1/<dir> (default work) with its own patched
# copies in sim/m1/<dir>/patched, so a second build does not touch work/.
set -euo pipefail
cd "$(dirname "$0")"
B=${M1_BUILD:-work}
mkdir -p "$B" && cd "$B"
R=../../../rtl; M=../../system/src/mem; T=../../system/src/tb
NV="nvc --std=2008"
# Simulation-only copies of three upstream files (upstream RTL untouched):
#  - gpu_line/gpu_poly: 'Z' default on the inout divider record ports, so the
#    fields these modules never drive (done, quotient, remainder) resolve to
#    the divider's value; NVC follows the LRM and makes undriven port elements
#    drive their default ('U') otherwise.
#  - gpu_videoout*: to_unsigned(x, N) -> to_unsigned((x) mod 2**N, N); at time
#    0 the display registers are 0 and the hardware wraps, NVC stops.
P=../patched; [ "$B" = work ] || P=patched; mkdir -p $P
DIVZ="inout div_type := (start => 'Z', done => 'Z', dividend => (others => 'Z'), divisor => (others => 'Z'), quotient => (others => 'Z'), remainder => (others => 'Z'));"
for f in gpu_line gpu_poly; do sed -E "s/inout div_type;/$DIVZ/" $R/$f.vhd > $P/$f.vhd; done
# gpu_poly: to_integer(xStart(43 downto 32)) > drawingAreaRight uses numeric_std
# ">"(NATURAL, UNSIGNED); xStart can be negative (span starting left of the
# screen) and NVC stops. The copy compares two integers (the intended
# meaning). What Quartus builds for a negative operand is open (M1 note).
sed -i '' -E 's/to_integer\(xStart\(43 downto 32\)\) > drawingAreaRight\)/to_integer(xStart(43 downto 32)) > to_integer(drawingAreaRight))/' $P/gpu_poly.vhd
# every to_unsigned(<integer>, N) in the video-out files wraps mod 2**N as the
# hardware's truncation does (negative intermediates before the display
# registers are written)
# gpu*.vhd debug logs (R:\\debug_*.txt, "if 1 = 1 generate" under
# translate_off) are switched off in the copies: they write tens of MB per
# run and slow the simulation
sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu.vhd > $P/gpu.vhd
sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu_vram2cpu.vhd > $P/gpu_vram2cpu.vhd
for f in gpu_videoout_async gpu_videoout_sync gpu_videoout; do
  python3 ../wrap_to_unsigned.py $R/$f.vhd > $P/$f.vhd
done
MEMF="$M/dpram.vhd $M/RamMLAB.vhd $M/SyncFifo.vhd $M/SyncRamDualByteEnable.vhd $R/SyncFifoFallThrough.vhd $R/SyncFifoFallThroughMLAB.vhd $R/SyncRam.vhd $R/SyncRamDual.vhd $R/SyncRamDualNotPow2.vhd"
$NV --work=mem -a --relaxed $MEMF
$NV --work=psx -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd \
  $R/divider.vhd $R/pGPU.vhd $R/mul32u.vhd $R/mul9s.vhd $R/gpu_fillVram.vhd $R/gpu_cpu2vram.vhd \
  $R/gpu_vram2vram.vhd $P/gpu_vram2cpu.vhd $P/gpu_line.vhd $R/gpu_rect.vhd $P/gpu_poly.vhd \
  $R/gpu_pixelpipeline.vhd $R/gpu_overlay.vhd $R/gpu_dither.vhd $P/gpu_videoout_async.vhd \
  $P/gpu_videoout_sync.vhd $R/gpu_crosshair.vhd $R/justifier_sensor.vhd $P/gpu_videoout.vhd $P/gpu.vhd
$NV --work=work -L . -a --relaxed ../tb_gpu_replay.vhd
echo "GPU and testbench compiled"
