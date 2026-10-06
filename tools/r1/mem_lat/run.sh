#!/bin/bash
# R1 measurements 2 and 3 and the fast-clock ratio step
# (docs/r1_cpu_domain_design.md): memory latency of memorymux + memctrl +
# sdram.sv at a 3:1 and a 2:1 clk_1x : SDRAM clock ratio, plus a DMA phase
# through dma.vhd's output FIFO.
#
#   tools/r1/mem_lat/run.sh [variant ...]     (default: r3 r2p2)
#
# Variant name: r<C>[p<P>][e][d]
#   C  clocks the bench makes: SDRAM clock = C x clk_1x, C = 3 (today,
#      101.6064 / 33.8688 MHz) or 2 (101.6064 / 50.8032 MHz)
#   P  CLK_FAST_RATIO of sdram.sv and psx_top.vhd (the request strobe
#      generator), default 3 (upstream)
#   e  sdram.sv EARLY_READY = 1 (ready one fast edge earlier on plain
#      channel 1 reads, 2:1 only)
#   d  DMA phase only (ROWS = 0, no latency rows)
# Examples: r3 = today; r2 = 2:1 clocks with the upstream generator (the
# Measurement 3 failure); r2p2 = 2:1 with the 2:1 generator; r3p2 = check
# that the 2:1 generator is wrong at 3:1; r2d = DMA phase alone at 2:1 with
# the upstream generator.
#
# Env: NREP (samples per row, 400), DMA_N (DMA phase words, 2048; 0 = off),
# T_FAST (SDRAM clock period, default the bench's 9842 ps; for example 10ns
# gives exactly 100 / 50 MHz at C = 2, the CPU50 clocks; the variant's output
# directory then gets the suffix _t<T_FAST>).
# Build and results go to sim/r1/mem_lat/<variant>/ (gitignored). NVC 1.23
# (VHDL-2008, Verilog for the sdram.sv copy), each simulation under nice -n 15,
# at most 2 at a time.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
R=$ROOT/rtl
OUT=$ROOT/sim/r1/mem_lat
NV="nvc --std=2008"
NREP=${NREP:-400}
DMA_N=${DMA_N:-2048}
T_FAST=${T_FAST:-}
VARIANTS=${*:-r3 r2p2}

build_run() {
  local v=$1 ratio param=3 rows=1 early=0
  if [[ $v =~ ^r([23])(p([23]))?(e)?(d)?$ ]]; then
    ratio=${BASH_REMATCH[1]}
    [ -n "${BASH_REMATCH[3]}" ] && param=${BASH_REMATCH[3]}
    [ -n "${BASH_REMATCH[4]}" ] && early=1
    [ -n "${BASH_REMATCH[5]}" ] && rows=0
  else
    echo "unknown variant $v" >&2; return 2
  fi
  local B=$OUT/$v tgen=""
  if [ -n "$T_FAST" ]; then B=${B}_t$T_FAST; tgen="-gT_FAST=$T_FAST"; fi
  rm -rf "$B"; mkdir -p "$B"; cd "$B"
  python3 "$HERE/sdram_sim_copy.py" "$R/sdram.sv" sdram_sim.sv
  python3 "$HERE/psx_top_index_copy.py" "$R/psx_top.vhd" clk3x_index_copy.vhd
  $NV --work=mem -a --relaxed "$ROOT/sim/system/src/mem/RamMLAB.vhd" "$R/SyncFifoFallThroughMLAB.vhd" \
      "$R/SyncFifo.vhd" "$R/SyncFifoFallThrough.vhd" > build.log 2>&1
  $NV --work=work -L . -a --relaxed sdram_sim.sv clk3x_index_copy.vhd "$R/dma.vhd" "$R/memctrl.vhd" \
      "$R/memorymux.vhd" "$HERE/tb_r1_mem.vhd" >> build.log 2>&1
  $NV --work=work -L . -e tb_r1_mem -gRATIO=$ratio -gCLK_FAST_RATIO=$param -gEARLY_READY=$early -gROWS=$rows -gNREP=$NREP \
      -gDMA_N=$DMA_N $tgen -gOUTFILE=$B/mem_lat.txt >> build.log 2>&1
  nice -n 15 $NV --work=work -L . -r tb_r1_mem > run.log 2>&1 || true
  echo "$v: $(tail -1 "$B/mem_lat.txt" 2>/dev/null || echo 'no result')"
}

mkdir -p "$OUT"
set -- $VARIANTS
while [ $# -gt 0 ]; do
  build_run "$1" &
  if [ $# -gt 1 ]; then build_run "$2" & shift; fi
  wait
  shift
done
