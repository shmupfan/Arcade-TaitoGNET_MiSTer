#!/bin/bash
# Benches for the ZN-2 layer in the CPU group (docs/r1_cpu_domain_design.md,
# "ZN-2 layer in the CPU group"). NVC 1.23, every run under nice -n 15, at
# most 2 at a time. Work data in sim/zn2cpu50/work/ (gitignored).
#
#   sim/zn2cpu50/run.sh unit     tb_zn2_cdc (rtl/gnet/zn2_cdc.vhd with the real
#                                zn2_cardmem) and tb_zn2_ch3_arb (zn2_ch3_arb
#                                behind PSX.sv's channel 3 handshake): clock
#                                pairs clk_cpu 50 MHz against 33.8688 MHz
#                                (clk2x 67.7376) and clk_cpu 28.5714 MHz (35 ns,
#                                slower than clk1x) against 33.8688 MHz, 4 seeds
#                                (random start phases), synchroniser model on
#                                and off; RESULT lines in work/unit/results.txt
#   sim/zn2cpu50/run.sh neg      negative controls (mutants.py): each mutated
#                                copy must make its bench fail
#   sim/zn2cpu50/run.sh sio50 <oracle run dir> [max_s] [coh3002t.zip]
#                                the M0 oracle's SIO0 and znsecsel traffic
#                                (sec.log, game-derived, vectors in work/) into
#                                zn_sio0 + CAT702 x2 + znmcu twice: at 33.8688
#                                MHz with sys_tick at its default
#                                (sim/zn2/tb_sio0_replay.vhd, the zn2-layer
#                                check) and at 50 MHz with tick_accum's
#                                sys_tick and znmcu CLK_HZ 50,000,000
#                                (tb_sio0_replay50.vhd)
#
# Env: N (card port ops and flash ops per run, default 20000).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
R=$ROOT/rtl/gnet; C=$R/cdc
W=$HERE/work
mkdir -p "$W"

P50=20000000; P35=35000000; P33=29525699

analyse() {   # analyse <dir> <zn2_cdc.vhd> <zn2_ch3_arb.vhd>
  ( cd "$1" && nvc --std=2008 -a $C/cdc_pkg.vhd $C/cdc_sync.vhd $C/cdc_capture.vhd $C/cdc_pulse.vhd \
      $C/cdc_handshake.vhd $C/cdc_bus_sync.vhd $C/cdc_fifo.vhd $R/zn2_cardmem.vhd "$2" "$3" \
      $ROOT/sim/cdc/cdc_tb_pkg.vhd $HERE/tb_zn2_cdc.vhd $HERE/tb_zn2_ch3_arb.vhd > analyse.log 2>&1 ) \
    || { grep -m 10 -A6 Error "$1/analyse.log"; exit 1; }
}

# one <dir> <tb> [G=V ...]: elaborate in memory and run, print RESULT lines
one() {
  local d=$1 tb=$2; shift 2
  local gens=()
  for g in "$@"; do gens+=("-g$g"); done
  ( cd "$d" && nice -n 15 nvc --std=2008 -e --jit --no-save ${gens[@]+"${gens[@]}"} "$tb" -r --ieee-warnings=off 2>&1 \
      | grep -E 'RESULT|Error|Failure|Fatal|fatal' ) || true
}

unit() {
  local B=$W/unit n=${N:-20000}
  rm -rf "$B"; mkdir -p "$B"
  analyse "$B" $R/zn2_cdc.vhd $R/zn2_ch3_arb.vhd
  : > "$B/results.txt"
  local list=()
  for pr in $P50:$P33 $P35:$P33; do
    a=${pr%%:*}; b=${pr##*:}
    for seed in 1 2 3 4; do
      for meta in 1 0; do
        list+=("tb_zn2_cdc PA=$a PB=$b SEED=$seed META=$meta N_OPS=$n N_LD=$n OUTTAG=s${seed}m${meta}")
        list+=("tb_zn2_ch3_arb PA=$a PB=$b SEED=$seed META=$meta N_A=$((n / 5)) N_B=$n OUTTAG=s${seed}m${meta}")
      done
      # loader at one word per clk1x cycle, held off by p_ld_busy (ioctl_wait)
      list+=("tb_zn2_cdc PA=$a PB=$b SEED=$seed META=1 N_OPS=$((n / 4)) N_LD=$n LD_STRESS=1 OUTTAG=ldstress_s${seed}")
    done
  done
  local jobs=()
  for j in "${list[@]}"; do
    # shellcheck disable=SC2086
    ( one "$B" $j | grep -E "RESULT|Fatal|fatal" >> "$B/results.txt" ) &
    jobs+=($!)
    if [ ${#jobs[@]} -ge 2 ]; then wait "${jobs[0]}"; jobs=("${jobs[@]:1}"); fi
  done
  wait
  cat "$B/results.txt"
  echo "runs: $(grep -c RESULT "$B/results.txt") of ${#list[@]}; with errors: $(grep RESULT "$B/results.txt" | grep -vc 'errors 0$' || true)"
}

neg() {
  local B=$W/neg
  rm -rf "$B"; mkdir -p "$B"; : > "$B/results.txt"
  local jobs=()
  for m in stale_ack ld_every_cycle no_hold no_gap ready_swap ld_ignore_busy; do
    (
      mkdir -p "$B/$m"
      python3 "$HERE/mutants.py" $m "$R" "$B/$m"
      analyse "$B/$m" "$B/$m/zn2_cdc.vhd" "$B/$m/zn2_ch3_arb.vhd"
      case $m in
        no_gap|ready_swap) tb="tb_zn2_ch3_arb N_A=1000 N_B=5000" ;;
        ld_ignore_busy)    tb="tb_zn2_cdc N_OPS=2000 N_LD=5000 LD_STRESS=2" ;;
        *)          tb="tb_zn2_cdc N_OPS=5000 N_LD=5000 RST_PER=50" ;;
      esac
      # shellcheck disable=SC2086
      out=$(one "$B/$m" $tb PA=$P50 PB=$P33 SEED=1 META=1 OUTTAG=$m)
      echo "$m: error reports $(echo "$out" | grep -c Error || true); $(echo "$out" | grep RESULT || echo 'no RESULT line')" >> "$B/results.txt"
    ) &
    jobs+=($!)
    if [ ${#jobs[@]} -ge 2 ]; then wait "${jobs[0]}"; jobs=("${jobs[@]:1}"); fi
  done
  wait
  cat "$B/results.txt"
}

sio50() {
  local run=$1 max=${2:-} zip=${3:-$ROOT/roms/coh3002t.zip}
  local B=$W/sio50_$(basename "$run")
  rm -rf "$B"; mkdir -p "$B"
  python3 "$ROOT/tools/gnet/cat702_ref.py" vectors "$run/sec.log" "$zip" "$B" > /dev/null
  python3 "$ROOT/tools/gnet/sio0_vectors.py" "$run/sec.log" "$B/sio0.vec" $max
  ( cd "$B" && nvc --std=2008 -a $C/cdc_pkg.vhd $C/tick_accum.vhd $R/zn_cat702.vhd $R/znmcu.vhd $R/zn_sio0.vhd \
      $ROOT/sim/zn2/tb_sio0_replay.vhd $HERE/tb_sio0_replay50.vhd > analyse.log 2>&1 ) \
    || { grep -m 10 -A6 Error "$B/analyse.log"; exit 1; }
  for tb in tb_sio0_replay tb_sio0_replay50; do
    echo "== $tb"
    ( cd "$B" && nice -n 15 nvc --std=2008 -e --jit --no-save -gDIR="$B" $tb -r --ieee-warnings=off 2>&1 \
        | grep -E 'SIO0 replay|late by|Error|Failure' | head -12 ) || true
  done
}

case "${1:-}" in
  unit)  unit ;;
  neg)   neg ;;
  sio50) shift; sio50 "$@" ;;
  *) sed -n '2,29p' "$0"; exit 1 ;;
esac
