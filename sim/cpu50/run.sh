#!/bin/bash
# R1 steps 4 and 5 (docs/r1_cpu_domain_design.md): NVC benches for the CPU
# group split.
#
#   sim/cpu50/run.sh split [N_OPS]   crossing-level bench tb_cpu_split: 4 PS1
#                                     clock phases x 2 seeds, metastability
#                                     model on (window 9 ns) and off
#   sim/cpu50/run.sh neg              negative controls (mutants.py): each
#                                     mutated copy must make tb_cpu_split fail
#   sim/cpu50/run.sh top              analyse psx_top with every RTL file and
#                                     elaborate it with CPU_CLK_SPLIT 0 and 1
#   sim/cpu50/run.sh replay T...      GPU replay (sim/m1/tb_gpu_replay.vhd) of
#                                     the ps1-tests streams T (quad, triangle,
#                                     ...) with every word sent from a 50 MHz
#                                     clock through cpu_gpu_bridge, VRAM at
#                                     frame 3 compared with the direct replay's
#                                     dump in $PS1T/<T>/vram_3.bin (PS1T default
#                                     sim/m1/ps1t, docs/m1_gpu_zn2.md 2d)
#   sim/cpu50/run.sh system [US]      psx_top (LEAN, GTE 3, 2 MB VRAM) with
#                                     sdram.sv, an SDRAM chip model and a
#                                     DDR3 model running the smoke program
#                                     (smoke_prog.py) for US microseconds
#                                     after reset, once with CPU_CLK_SPLIT = 0
#                                     (33.8688 MHz, SDRAM 3:1) and once with 1
#                                     (50/100 MHz); the RAM results must match
#
# Work data in sim/cpu50/work/ (gitignored). Each simulation under nice -n 15,
# at most 2 at a time. NVC 1.23.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
R=$ROOT/rtl; C=$R/gnet/cdc; S=$R/gnet/cpu_split; M=$ROOT/sim/system/src/mem
W=$HERE/work
NV="nvc --std=2008 -H 1g"
mkdir -p "$W"

split() {
  local nops=${1:-20000}
  local B=$W/split
  rm -rf "$B"; mkdir -p "$B"; cd "$B"
  $NV -a $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd \
      $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd \
      $S/cpu_gpu_bridge.vhd $S/cpu_spu_bridge.vhd $S/cpu_reset_fill.vhd $S/cpu_split.vhd \
      $HERE/tb_cpu_split.vhd > build.log 2>&1
  : > results.txt
  local jobs=()
  for win in 9ns 0ns; do
    for ph in 0ns 3ns 11ns 23ns; do
      for seed in 1 2; do
        local tag=w${win}_p${ph}_s${seed}
        (
          mkdir -p "$B/$tag"; cd "$B/$tag"
          cp -R ../work ./work   # one elaboration per directory (runs go in parallel)
          $NV --work=work -e tb_cpu_split -gPHASE=$ph -gSEED=$seed -gWINDOW=$win -gN_OPS=$nops \
              -gOUTTAG=$tag > elab.log 2>&1
          nice -n 15 $NV --work=work -r tb_cpu_split --ieee-warnings=off > run.log 2>&1 || true
          grep "^$tag" run.log >> "$B/results.txt" || echo "$tag: no result (see $B/$tag/run.log)" >> "$B/results.txt"
        ) &
        jobs+=($!)
        if [ ${#jobs[@]} -ge 2 ]; then wait "${jobs[0]}"; jobs=("${jobs[@]:1}"); fi
      done
    done
  done
  wait
  cat "$B/results.txt"
}

neg() {
  local B=$W/neg
  rm -rf "$B"; mkdir -p "$B"; : > "$B/results.txt"
  local jobs=()
  for m in gpu_nostall spu_nostall gpu_noquiet fill_noce; do
    (
      mkdir -p "$B/$m/src"; cd "$B/$m"
      python3 $HERE/mutants.py $m $S "$B/$m/src"
      $NV -a $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd \
          $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $C/tick_accum.vhd \
          src/cpu_gpu_bridge.vhd src/cpu_spu_bridge.vhd src/cpu_reset_fill.vhd src/cpu_split.vhd \
          $HERE/tb_cpu_split.vhd > build.log 2>&1
      $NV -e tb_cpu_split -gPHASE=3ns -gSEED=1 -gWINDOW=9ns -gN_OPS=2000 -gMAXT=20ms -gOUTTAG=$m > elab.log 2>&1
      nice -n 15 $NV -r tb_cpu_split --ieee-warnings=off > run.log 2>&1 || true
      local res=$(grep -o 'errors [0-9]*$' run.log || echo 'no result')
      echo "$m: $res, error reports $(grep -c '\*\* Error' run.log), timeout $(grep -c TIMEOUT run.log)" >> "$B/results.txt"
    ) &
    jobs+=($!)
    if [ ${#jobs[@]} -ge 2 ]; then wait "${jobs[0]}"; jobs=("${jobs[@]:1}"); fi
  done
  wait
  cat "$B/results.txt"
}

system() {
  local us=${1:-1500} B=$W/system
  rm -rf "$B"; mkdir -p "$B/patched"; cd "$B"
  local P=$B/patched
  local DIVZ="inout div_type := (start => 'Z', done => 'Z', dividend => (others => 'Z'), divisor => (others => 'Z'), quotient => (others => 'Z'), remainder => (others => 'Z'));"
  for f in gpu_line gpu_poly; do sed -E "s/inout div_type;/$DIVZ/" $R/$f.vhd > $P/$f.vhd; done
  sed -i '' -E 's/to_integer\(xStart\(43 downto 32\)\) > drawingAreaRight\)/to_integer(xStart(43 downto 32)) > to_integer(drawingAreaRight))/' $P/gpu_poly.vhd
  sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu.vhd > $P/gpu.vhd
  sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu_vram2cpu.vhd > $P/gpu_vram2cpu.vhd
  for f in gpu_videoout_async gpu_videoout_sync gpu_videoout; do
    python3 $ROOT/sim/m1/wrap_to_unsigned.py $R/$f.vhd > $P/$f.vhd
  done
  python3 $ROOT/tools/r1/mem_lat/sdram_sim_copy.py $R/sdram.sv $B/sdram_sim.sv
  python3 $HERE/gen_system_tb.py $R/psx_top.vhd $B/tb_cpu50_system.vhd
  python3 $HERE/smoke_prog.py $B/bios.bin
  $NV --work=altera_mf -a $HERE/altera_mf_stub.vhd > build.log 2>&1
  $NV --work=mem -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd $M/SyncFifo.vhd $M/SyncRamDualByteEnable.vhd \
      $R/SyncFifoFallThrough.vhd $R/SyncFifoFallThroughMLAB.vhd $R/SyncRam.vhd $R/SyncRamDual.vhd $R/SyncRamDualNotPow2.vhd >> build.log 2>&1
  $NV --work=work -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd \
    $R/export.vhd $R/divider.vhd $R/pGPU.vhd $R/mul32u.vhd $R/mul9s.vhd $R/cheats.vhd $R/gpu_fillVram.vhd $R/gpu_cpu2vram.vhd \
    $R/gpu_vram2vram.vhd $P/gpu_vram2cpu.vhd $P/gpu_line.vhd $R/gpu_rect.vhd $P/gpu_poly.vhd \
    $R/gpu_pixelpipeline.vhd $R/gpu_overlay.vhd $R/gpu_dither.vhd $P/gpu_videoout_async.vhd \
    $P/gpu_videoout_sync.vhd $R/gpu_crosshair.vhd $R/justifier_sensor.vhd $P/gpu_videoout.vhd $P/gpu.vhd \
    $R/irq.vhd $R/pJoypad.vhd $R/joypad_pad.vhd $R/joypad_mem.vhd $R/joypad.vhd $R/timer.vhd $R/dma.vhd $R/exp2.vhd \
    $R/pGTE.vhd $R/gte_mac0.vhd $R/gte_mac123.vhd $R/gte_UNRDivide.vhd $R/gte.vhd $R/mdec.vhd $R/cd_xa_zigzag.vhd \
    $R/cd_xa.vhd $R/cd_top.vhd $R/memctrl.vhd $R/sio.vhd $R/spu_ram.vhd $R/spu_gauss.vhd $R/spu.vhd $R/datacache.vhd \
    $R/cpu.vhd $R/memorymux.vhd $R/memcard.vhd $R/statemanager.vhd $R/savestates.vhd \
    $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd \
    $C/cdc_fifo.vhd $C/tick_accum.vhd $S/cpu_gpu_bridge.vhd $S/cpu_spu_bridge.vhd $S/cpu_reset_fill.vhd $S/cpu_split.vhd \
    $R/psx_top.vhd >> build.log 2>&1 || { grep -m 10 -A6 Error build.log; exit 1; }
  $NV --work=work -L . -a --relaxed $B/sdram_sim.sv $B/tb_cpu50_system.vhd >> build.log 2>&1 || { grep -m 10 -A6 Error build.log; exit 1; }
  for sp in 0 1; do
    (
      mkdir -p "$B/split$sp"; cd "$B/split$sp"
      cp -R ../work ./work
      $NV --work=work -L .. -e tb_cpu50_system -gSPLIT=$sp -gRUN_US=$us -gBIOS_FILE=$B/bios.bin > elab.log 2>&1
      nice -n 15 $NV --work=work -L .. -r tb_cpu50_system --ieee-warnings=off > run.log 2>&1 || true
    ) &
  done
  wait
  for sp in 0 1; do
    echo "CPU_CLK_SPLIT=$sp:"; cut -d' ' -f1-3 "$B/split$sp/ram.log"
    grep -h 'done marker' "$B/split$sp/run.log" || echo "  no done marker"
  done
  # last value per address: a store may run twice when the CPU executes a few
  # instructions between the engine's first reset and its pause (reset retry)
  local last0 last1
  last0=$(awk '{v[$1] = $2} END {for (a in v) print a, v[a]}' "$B/split0/ram.log" | sort | grep -v '^110 \|^114 ')
  last1=$(awk '{v[$1] = $2} END {for (a in v) print a, v[a]}' "$B/split1/ram.log" | sort | grep -v '^110 \|^114 ')
  if [ -n "$last0" ] && [ "$last0" = "$last1" ]; then
    echo "final RAM values identical (timer values 0x110/0x114 excluded: the CPU rate differs)"
  else
    echo "RESULTS DIFFER"
  fi
}

top() {
  local B=$W/top
  rm -rf "$B"; mkdir -p "$B"; cd "$B"
  $NV --work=altera_mf -a $HERE/altera_mf_stub.vhd
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
    $R/psx_top.vhd $R/psx_mister.vhd > analyse.log 2>&1 || { grep -m 10 -A6 Error analyse.log; exit 1; }
  $NV --work=psx -L . -e psx_top -gCPU_CLK_SPLIT=0 > elab0.log 2>&1 && echo "psx_top CPU_CLK_SPLIT=0: elaborated"
  $NV --work=psx -L . -e psx_top -gCPU_CLK_SPLIT=1 -gHAS_CD=0 -gHAS_PADS=0 -gHAS_SAVESTATES=0 -gHAS_CHEATS=0 \
      -gHAS_MDEC=0 -gCLK_FAST_RATIO=2 -gGTE_NARROW_MUL=3 -gVRAM_Y_BITS=10 > elab1.log 2>&1 \
      && echo "psx_top CPU_CLK_SPLIT=1 (LEAN, ratio 2, GTE 3, 2 MB VRAM): elaborated"
}

replay() {
  local B=$W/replay PS1T=${PS1T:-$ROOT/sim/m1/ps1t}
  rm -rf "$B"; mkdir -p "$B/patched"; cd "$B"
  local P=$B/patched
  # GPU simulation copies as sim/m1/build.sh makes them (upstream RTL untouched)
  local DIVZ="inout div_type := (start => 'Z', done => 'Z', dividend => (others => 'Z'), divisor => (others => 'Z'), quotient => (others => 'Z'), remainder => (others => 'Z'));"
  for f in gpu_line gpu_poly; do sed -E "s/inout div_type;/$DIVZ/" $R/$f.vhd > $P/$f.vhd; done
  sed -i '' -E 's/to_integer\(xStart\(43 downto 32\)\) > drawingAreaRight\)/to_integer(xStart(43 downto 32)) > to_integer(drawingAreaRight))/' $P/gpu_poly.vhd
  sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu.vhd > $P/gpu.vhd
  sed -E 's/^( *g[a-z0-9_]* : if )1 = 1 generate/\11 = 0 generate/' $R/gpu_vram2cpu.vhd > $P/gpu_vram2cpu.vhd
  for f in gpu_videoout_async gpu_videoout_sync gpu_videoout; do
    python3 $ROOT/sim/m1/wrap_to_unsigned.py $R/$f.vhd > $P/$f.vhd
  done
  python3 $HERE/replay_split.py $ROOT/sim/m1/tb_gpu_replay.vhd $B/tb_gpu_replay_split.vhd
  local MEMF="$M/dpram.vhd $M/RamMLAB.vhd $M/SyncFifo.vhd $M/SyncRamDualByteEnable.vhd $R/SyncFifoFallThrough.vhd $R/SyncFifoFallThroughMLAB.vhd $R/SyncRam.vhd $R/SyncRamDual.vhd $R/SyncRamDualNotPow2.vhd"
  $NV --work=mem -a --relaxed $MEMF > build.log 2>&1
  $NV --work=psx -L . -a --relaxed $M/dpram.vhd $M/RamMLAB.vhd \
    $R/divider.vhd $R/pGPU.vhd $R/mul32u.vhd $R/mul9s.vhd $R/gpu_fillVram.vhd $R/gpu_cpu2vram.vhd \
    $R/gpu_vram2vram.vhd $P/gpu_vram2cpu.vhd $P/gpu_line.vhd $R/gpu_rect.vhd $P/gpu_poly.vhd \
    $R/gpu_pixelpipeline.vhd $R/gpu_overlay.vhd $R/gpu_dither.vhd $P/gpu_videoout_async.vhd \
    $P/gpu_videoout_sync.vhd $R/gpu_crosshair.vhd $R/justifier_sensor.vhd $P/gpu_videoout.vhd $P/gpu.vhd >> build.log 2>&1
  $NV --work=work -L . -a --relaxed $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd \
    $C/cdc_handshake.vhd $C/cdc_fifo.vhd $S/cpu_gpu_bridge.vhd $B/tb_gpu_replay_split.vhd >> build.log 2>&1
  : > results.txt
  local jobs=()
  for t in "$@"; do
    (
      mkdir -p "$B/$t"; cd "$B/$t"
      cp -R ../work ./work
      $NV --work=work -L .. -e tb_gpu_replay_split -gSTREAM=$PS1T/$t/stream.txt -gDUMPS=2,3 -gMAXFRAME=4 \
          -gVRAM_Y_BITS=9 -gVIDCAP=false > elab.log 2>&1
      nice -n 15 $NV --work=work -L .. -r tb_gpu_replay_split --exit-severity=failure --ieee-warnings=off > run.log 2>&1 || true
      local words=$(grep -o 'stream done, words [0-9]*' run.log | grep -o '[0-9]*$' || true)
      if [ -f vram_3.bin ] && cmp -s vram_3.bin $PS1T/$t/vram_3.bin; then
        echo "$t: words ${words:-?}, vram_3.bin identical to the direct replay" >> "$B/results.txt"
      else
        echo "$t: words ${words:-?}, vram_3.bin DIFFERS or missing (see $B/$t/run.log)" >> "$B/results.txt"
      fi
    ) &
    jobs+=($!)
    if [ ${#jobs[@]} -ge 2 ]; then wait "${jobs[0]}"; jobs=("${jobs[@]:1}"); fi
  done
  wait
  cat "$B/results.txt"
}

case "${1:-}" in
  split)  split "${2:-20000}" ;;
  top)    top ;;
  neg)    neg ;;
  system) system "${2:-1500}" ;;
  replay) shift; replay "$@" ;;
  *) sed -n '2,29p' "$0"; exit 1 ;;
esac
