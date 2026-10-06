#!/bin/bash
# Benches for the Taito Zoom board in the full core (docs/zoom_board_design.md
# 14). Every simulation runs under nice -n 15, one at a time. Work data in
# sim/zoomlink/work/ (gitignored).
#
#   sim/zoomlink/run.sh unit     tb_zoom_cdc (rtl/gnet/zoom_cdc.vhd,
#                                zoom_sdram_link.vhd and zn2_ch3_arb, NVC
#                                1.23): clk_cpu 50 MHz and 28.57 MHz against
#                                clk1x 33.8688 MHz, 2 seeds, synchroniser model
#                                on and off, then 4 runs with random resets on
#                                both sides; RESULT lines in work/unit/results.txt
#   sim/zoomlink/run.sh neg      negative controls (mutants.py): each mutated
#                                copy must make tb_zoom_cdc fail
#   sim/zoomlink/run.sh arb      the existing tb_zn2_ch3_arb (sim/zn2cpu50) on
#                                the arbiter with port c added and idle: the
#                                two-port behaviour must be unchanged
#   sim/zoomlink/run.sh top      analyse psx_top with every RTL file it needs
#                                and elaborate it with ZN2_BOARD 1,
#                                CPU_CLK_SPLIT 1 and ZOOM_BOARD 1, then 0
#   sim/zoomlink/run.sh lint     Verilator lint of the rtl/zoom files and of
#                                PSX.sv with the GNET_Z1_ZOOM macros
#   sim/zoomlink/build.sh, tb_zoomlink.cpp: the integration bench
#                                (Verilator; see build.sh)
#
# Env: N (host accesses and lines per unit run, default 4000).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
R=$ROOT/rtl; G=$R/gnet; C=$G/cdc
W=$HERE/work
mkdir -p "$W"
P50=20000000; P35=35000000; P33=29525699

analyse() {   # analyse <dir> <zoom_cdc.vhd> <zoom_sdram_link.vhd>
  ( cd "$1" && nvc --std=2008 -a $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd \
      $C/cdc_handshake.vhd "$2" "$3" $G/zn2_ch3_arb.vhd $ROOT/sim/cdc/cdc_tb_pkg.vhd $HERE/tb_zoom_cdc.vhd > analyse.log 2>&1 ) \
    || { grep -m 10 -A6 Error "$1/analyse.log"; exit 1; }
}

one() {   # one <dir> [G=V ...]: elaborate in memory and run, print RESULT lines
  local d=$1; shift
  local gens=()
  for g in "$@"; do gens+=("-g$g"); done
  ( cd "$d" && nice -n 15 nvc --std=2008 -e --jit --no-save ${gens[@]+"${gens[@]}"} tb_zoom_cdc -r --ieee-warnings=off 2>&1 \
      | grep -E 'RESULT|Error|Failure|Fatal|fatal' | head -20 ) || true
}

unit() {
  local B=$W/unit n=${N:-4000}
  rm -rf "$B"; mkdir -p "$B"
  analyse "$B" $G/zoom_cdc.vhd $G/zoom_sdram_link.vhd
  : > "$B/results.txt"
  for pr in $P50:$P33 $P35:$P33; do
    a=${pr%%:*}; b=${pr##*:}
    for seed in 1 2; do
      for meta in 1 0; do
        one "$B" PA=$a PB=$b SEED=$seed META=$meta N_H=$n N_L=$n N_B=$((n / 2)) OUTTAG=s${seed}m${meta} | tee -a "$B/results.txt"
      done
    done
  done
  for seed in 3 4 5 6; do
    one "$B" PA=$P50 PB=$P33 SEED=$seed META=1 N_H=$n N_L=$n N_B=$((n / 2)) RST_PER=20 OUTTAG=rst_s${seed} | tee -a "$B/results.txt"
  done
  echo "runs: $(grep -c RESULT "$B/results.txt") of 12; with errors: $(grep RESULT "$B/results.txt" | grep -vc 'errors 0$' || true)"
}

neg() {
  local B=$W/neg
  rm -rf "$B"; mkdir -p "$B"; : > "$B/results.txt"
  for m in $(python3 "$HERE/mutants.py" list); do
    mkdir -p "$B/$m"
    python3 "$HERE/mutants.py" $m "$G" "$B/$m"
    analyse "$B/$m" "$B/$m/zoom_cdc.vhd" "$B/$m/zoom_sdram_link.vhd"
    case $m in
      start_in_reset)        extra="RST_PER=20 SEED=3 N_H=4000 N_L=4000 N_B=2000" ;;
      stale_line|stale_host) extra="RST_PER=20 SEED=3 N_H=1500 N_L=1500 N_B=500" ;;
      *)                     extra="SEED=1 N_H=1500 N_L=1500 N_B=500" ;;
    esac
    # shellcheck disable=SC2086
    out=$(one "$B/$m" PA=$P50 PB=$P33 META=1 OUTTAG=$m $extra)
    echo "$m: error reports $(echo "$out" | grep -c Error || true); $(echo "$out" | grep RESULT || echo 'no RESULT line')" | tee -a "$B/results.txt"
  done
}

arb() {
  local B=$W/arb
  rm -rf "$B"; mkdir -p "$B"
  ( cd "$B" && nvc --std=2008 -a $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd \
      $C/cdc_handshake.vhd $G/zn2_ch3_arb.vhd $ROOT/sim/cdc/cdc_tb_pkg.vhd $ROOT/sim/zn2cpu50/tb_zn2_ch3_arb.vhd > analyse.log 2>&1 ) \
    || { grep -m 10 -A6 Error "$B/analyse.log"; exit 1; }
  for seed in 1 2; do
    ( cd "$B" && nice -n 15 nvc --std=2008 -e --jit --no-save -gPA=$P50 -gPB=$P33 -gSEED=$seed -gMETA=1 -gN_A=4000 -gN_B=20000 \
        -gOUTTAG=s$seed tb_zn2_ch3_arb -r --ieee-warnings=off 2>&1 | grep -E 'RESULT|Error|Fatal' | head ) || true
  done
  # sim/zn2cpu50's no_gap mutant (now three answers go straight to IDLE) must still fail
  local M=$B/no_gap
  mkdir -p "$M"
  python3 "$ROOT/sim/zn2cpu50/mutants.py" no_gap "$G" "$M"
  ( cd "$M" && nvc --std=2008 -a $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd \
      $C/cdc_handshake.vhd "$M/zn2_ch3_arb.vhd" $ROOT/sim/cdc/cdc_tb_pkg.vhd $ROOT/sim/zn2cpu50/tb_zn2_ch3_arb.vhd > analyse.log 2>&1 ) \
    || { grep -m 10 -A6 Error "$M/analyse.log"; exit 1; }
  local out
  out=$( ( cd "$M" && nice -n 15 nvc --std=2008 -e --jit --no-save -gPA=$P50 -gPB=$P33 -gSEED=1 -gMETA=1 -gN_A=1000 -gN_B=5000 \
      -gOUTTAG=no_gap tb_zn2_ch3_arb -r --ieee-warnings=off 2>&1 ) || true )
  echo "no_gap mutant: error reports $(echo "$out" | grep -c Error || true); $(echo "$out" | grep RESULT || echo 'no RESULT line')"
}

top() {
  local B=$W/top M=$ROOT/sim/system/src/mem S=$G/cpu_split
  local NV="nvc --std=2008 -H 1g"
  rm -rf "$B"; mkdir -p "$B"; cd "$B"
  $NV --work=altera_mf -a $ROOT/sim/cpu50/altera_mf_stub.vhd
  $NV --work=mem -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd $M/SyncFifo.vhd $M/SyncRamDualByteEnable.vhd \
      $R/SyncFifoFallThrough.vhd $R/SyncFifoFallThroughMLAB.vhd $R/SyncRam.vhd $R/SyncRamDual.vhd $R/SyncRamDualNotPow2.vhd
  $NV --work=psx -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd \
    $R/export.vhd $R/divider.vhd $R/pGPU.vhd $R/mul32u.vhd $R/mul9s.vhd $R/cheats.vhd $R/gpu_fillVram.vhd $R/gpu_cpu2vram.vhd \
    $R/gpu_vram2vram.vhd $R/gpu_vram2cpu.vhd $R/gpu_line.vhd $R/gpu_rect.vhd $R/gpu_poly.vhd \
    $R/gpu_pixelpipeline.vhd $R/gpu_overlay.vhd $R/gpu_dither.vhd $R/gpu_videoout_async.vhd \
    $R/gpu_videoout_sync.vhd $R/gpu_crosshair.vhd $R/justifier_sensor.vhd $R/gpu_videoout.vhd $R/gpu.vhd \
    $R/irq.vhd $R/pJoypad.vhd $R/joypad_pad.vhd $R/joypad_mem.vhd $R/joypad.vhd $R/timer.vhd $R/dma.vhd $R/exp2.vhd \
    $R/pGTE.vhd $R/gte_mac0.vhd $R/gte_mac123.vhd $R/gte_UNRDivide.vhd $R/gte.vhd $R/mdec.vhd $R/cd_xa_zigzag.vhd \
    $R/cd_xa.vhd $R/cd_top.vhd $R/memctrl.vhd $R/sio.vhd $R/spu_ram.vhd $R/spu_gauss.vhd $R/spu.vhd $R/datacache.vhd \
    $R/cpu.vhd $R/memorymux.vhd $R/memcard.vhd $R/statemanager.vhd $R/savestates.vhd \
    $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd \
    $C/cdc_fifo.vhd $C/tick_accum.vhd $S/cpu_gpu_bridge.vhd $S/cpu_spu_bridge.vhd $S/cpu_reset_fill.vhd $S/cpu_split.vhd \
    $G/zn_cat702.vhd $G/znmcu.vhd $G/zn_sio0.vhd $G/zn2_io.vhd $G/zn2_cardmem.vhd $G/zn2_board.vhd $G/zn2_cdc.vhd \
    $G/zoom_cdc.vhd $G/zoom_sdram_link.vhd $R/psx_top.vhd $R/psx_mister.vhd > analyse.log 2>&1 \
    || { grep -m 10 -A6 Error analyse.log; exit 1; }
  echo "analysed"
  local LEAN="-gHAS_CD=0 -gHAS_PADS=0 -gHAS_SAVESTATES=0 -gHAS_CHEATS=0 -gHAS_MDEC=0 -gCLK_FAST_RATIO=2 -gGTE_NARROW_MUL=3 -gVRAM_Y_BITS=10"
  for z in 1 0; do
    # shellcheck disable=SC2086
    if nice -n 15 $NV --work=psx -L . -e psx_top -gCPU_CLK_SPLIT=1 -gZN2_BOARD=1 -gZOOM_BOARD=$z $LEAN > elab$z.log 2>&1; then
      echo "psx_top ZN2_BOARD 1, CPU_CLK_SPLIT 1, ZOOM_BOARD $z: elaborated ($(grep -ci warning elab$z.log || true) warnings, $B/elab$z.log)"
    else
      echo "ZOOM_BOARD $z: elaboration failed"; grep -m 12 -B2 -A8 -i error elab$z.log || true
    fi
  done
}

lint() {
  local B=$W/lint
  rm -rf "$B"; mkdir -p "$B"
  local ZF="$R/zoom/mn10200_decode.sv $R/zoom/mn10200_rf.sv $R/zoom/mn10200_core.sv $R/zoom/mn10200_periph.sv $R/zoom/mn10200.sv
    $R/zoom/zsg2_ram.sv $R/zoom/zsg2_fetch.sv $R/zoom/zsg2.sv $R/zoom/tms57002.sv $R/zoom/zoom_tbase.sv $R/zoom/zoom_tmsfeed.sv
    $R/zoom/zoom_pcache.sv $R/zoom/zoom_wram.sv $R/zoom/zoom_mbox.sv $R/zoom/zoom_host.sv $R/zoom/zoom_bus.sv
    $R/zoom/zoom_memarb.sv $R/zoom/zoom_out.sv $R/zoom/zoom_mix.sv $R/zoom/zoom_board.sv"
  local rc
  echo "== rtl/zoom, zoom_board top with ZSG_INFL 4 and 8 (GNET_Z1_ZOOM.qsf file list)"
  for infl in 4 8; do
    # shellcheck disable=SC2086
    ( cd "$ROOT" && nice -n 15 verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNUSEDPARAM \
        -Wno-MULTIDRIVEN -GZSG_INFL=$infl --top-module zoom_board $ZF > "$B/zoom$infl.log" 2>&1 ) && rc=0 || rc=$?
    echo "ZSG_INFL $infl: rc $rc, $(grep -c '%Error' "$B/zoom$infl.log" || true) errors, $(grep -c '%Warning' "$B/zoom$infl.log" || true) warnings ($B/zoom$infl.log)"
  done
  ( cd "$ROOT" && nice -n 15 verilator --lint-only -Wall -Wno-fatal --top-module zoom_mix $R/zoom/zoom_mix.sv > "$B/mix.log" 2>&1 ) && rc=0 || rc=$?
  echo "zoom_mix: rc $rc, $(grep -c '%Error' "$B/mix.log" || true) errors, $(grep -c '%Warning' "$B/mix.log" || true) warnings"
  # build_id.v is written by sys/build_id.tcl at compile time: a stand-in
  printf '`define BUILD_DATE "000000"\n' > "$B/build_id.v"
  local base="+define+MISTER_FB=1 +define+MISTER_DOWNSCALE_NN=1 +define+MISTER_DISABLE_ALSA=1 +define+GNET_NO_CD=1 +define+GNET_NO_PADS=1 +define+GNET_NO_SAVESTATES=1 +define+GNET_NO_CHEATS=1 +define+GNET_LEAN=1 +define+MISTER_DISABLE_YC=1 +define+MISTER_DISABLE_ADAPTIVE=1 +define+GNET_NO_MDEC=1 +define+GNET_VRAM_2MB=1 +define+GNET_GTE_NARROW_MUL=3 +define+GNET_ZN2=1 +define+GNET_CLK_RATIO2=1 +define+GNET_CPU50=1"
  for cfg in z1zoom z1cpu50 ddr3arb; do
    local defs=$base
    case $cfg in
      z1zoom)  defs="$defs +define+GNET_ZOOM=1 +define+GNET_ZOOM_SDRAM=1" ;;
      ddr3arb) defs="$defs +define+GNET_ZOOM=1 +define+GNET_DDR3_ARB=1" ;;
    esac
    echo "== PSX.sv, $cfg macros"
    # Verilator sees only PSX.sv and rtl/zoom/zoom_mix.sv: the VHDL entities
    # and framework modules it cannot find are the only expected errors
    # shellcheck disable=SC2086
    ( cd "$ROOT" && nice -n 15 verilator --lint-only -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTH -Wno-PINMISSING \
        $defs -I"$B" -Isys -Irtl --top-module emu PSX.sv rtl/zoom/zoom_mix.sv > "$B/psx_$cfg.log" 2>&1 ) || true
    grep '%Error' "$B/psx_$cfg.log" | grep -v 'Cannot find file containing module' | grep -v 'Exiting due to' | head -20 || true
    # the same with stand-ins for the missing modules (lint_stubs.py), so
    # Verilator elaborates the whole emu module
    python3 "$HERE/lint_stubs.py" "$B/stubs.sv"
    # shellcheck disable=SC2086
    ( cd "$ROOT" && nice -n 15 verilator --lint-only -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSED -Wno-WIDTH -Wno-PINMISSING \
        -Wno-PROCASSWIRE $defs -I"$B" -Isys -Irtl --top-module emu PSX.sv rtl/zoom/zoom_mix.sv sys/math.sv "$B/stubs.sv" > "$B/psx_${cfg}_full.log" 2>&1 ) || true
    echo "with stand-ins: $(grep -c '%Error' "$B/psx_${cfg}_full.log" || true) errors, $(grep -c '%Warning' "$B/psx_${cfg}_full.log" || true) warnings ($B/psx_${cfg}_full.log)"
    grep '%Error' "$B/psx_${cfg}_full.log" | head -10 || true
    echo "module-not-found errors: $(grep -c 'Cannot find file containing module' "$B/psx_$cfg.log" || true); other errors: $(grep '%Error' "$B/psx_$cfg.log" | grep -v 'Cannot find file containing module' | grep -vc 'Exiting due to' || true)"
    echo "modules not found: $(grep 'Cannot find file containing module' "$B/psx_$cfg.log" | sed -E "s/.*module: '([^']*)'.*/\1/" | sort -u | tr '\n' ' ')"
  done
  echo "== PSX.sv connections to the VHDL entities (check_ports.py)"
  for m in "GNET_ZN2 GNET_CPU50 GNET_ZOOM GNET_ZOOM_SDRAM" "GNET_ZN2 GNET_CPU50 GNET_ZOOM GNET_DDR3_ARB" "GNET_ZN2 GNET_CPU50" ""; do
    # shellcheck disable=SC2086
    python3 "$HERE/check_ports.py" $m | tail -1 || true
  done
}

case "${1:-}" in
  unit) unit ;;
  neg)  neg ;;
  arb)  arb ;;
  top)  top ;;
  lint) lint ;;
  *) sed -n '2,25p' "$0"; exit 1 ;;
esac
