#!/bin/bash
# NVC benches for rtl/gnet/cdc (work dir and logs gitignored: sim/cdc/work).
#
#   sim/cdc/run.sh compile          analyse RTL and benches
#   sim/cdc/run.sh one TB G=V ...   one run (elaborated in memory, no files)
#   sim/cdc/run.sh all              full matrix, 2 runs at a time, nice -n 15;
#                                   RESULT lines in work/results.txt
#   sim/cdc/run.sh extra            other FIFO sizes, 3-stage synchronisers
#                                   (also part of all)
#   sim/cdc/run.sh neg              negative controls (expected to fail)
#
# Env: N (transfers per run, default 50000), SEEDS (default "1 2").
set -euo pipefail
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")"
R=../../../rtl/gnet/cdc
mkdir -p work
cd work

compile() {
  nvc --std=2008 -a $R/cdc_pkg.vhd $R/cdc_sync.vhd $R/cdc_capture.vhd \
    $R/cdc_pulse.vhd $R/cdc_handshake.vhd $R/cdc_bus_sync.vhd $R/cdc_fifo.vhd \
    $R/tick_accum.vhd \
    ../cdc_tb_pkg.vhd ../tb_cdc_sync.vhd ../tb_cdc_pulse.vhd ../tb_cdc_handshake.vhd \
    ../tb_cdc_bus_sync.vhd ../tb_cdc_fifo.vhd ../tb_tick_accum.vhd
}

# one <tb> [G=V ...]: elaborate in memory (safe to run in parallel) and run
one() {
  local tb=$1; shift
  local gens=()
  for g in "$@"; do gens+=("-g$g"); done
  nice -n 15 nvc --std=2008 -e --jit --no-save ${gens[@]+"${gens[@]}"} "$tb" -r --ieee-warnings=off 2>&1 \
    | grep -E 'RESULT|ERROR|Failure|Fatal|fatal' | head -20 || true
}

# periods in fs: 50, 100, 33.8688, 67.7376, 53.693175 MHz
P50=20000000; P100=10000000; P33=29525699; P67=14762850; P53=18624341
PAIRS="$P50:$P33 $P33:$P50 $P100:$P67 $P67:$P100 $P50:$P67 $P67:$P50 $P100:$P33 $P33:$P100 $P50:$P53 $P53:$P50"

jobs_list() {
  local n=${N:-50000}
  for seed in ${SEEDS:-1 2}; do
    for pr in $PAIRS; do
      a=${pr%%:*}; b=${pr##*:}
      for meta in 0 1; do
        s=$((seed * 100 + RANDOM % 97 + 1))
        echo "tb_cdc_sync PA=$a PB=$b SEED=$s META=$meta NX=$n"
        echo "tb_cdc_pulse PA=$a PB=$b SEED=$s META=$meta CNT_W=1 MODE=0 NX=$n"
        echo "tb_cdc_pulse PA=$a PB=$b SEED=$s META=$meta CNT_W=4 MODE=1 NX=$n"
        echo "tb_cdc_handshake PA=$a PB=$b SEED=$s META=$meta NX=$n"
        echo "tb_cdc_bus_sync PA=$a PB=$b SEED=$s META=$meta NX=$n"
        echo "tb_cdc_fifo PA=$a PB=$b SEED=$s META=$meta FWFT=1 NX=$n"
        echo "tb_cdc_fifo PA=$a PB=$b SEED=$s META=$meta FWFT=0 NX=$n"
      done
    done
  done
  extra_list
  echo "tb_tick_accum SEED=1 CE_MODE=0 WINDOWS=64"
  echo "tb_tick_accum SEED=2 CE_MODE=1 WINDOWS=64"
}

# other FIFO sizes (C8 8 x 27, minimum depth 2) and a 3-stage synchroniser
extra_list() {
  local n=${N:-50000}
  for pr in "$P50:$P33" "$P33:$P50" "$P100:$P33" "$P33:$P100" "$P100:$P67" "$P67:$P100"; do
    a=${pr%%:*}; b=${pr##*:}
    for fw in 0 1; do
      echo "tb_cdc_fifo PA=$a PB=$b SEED=$((RANDOM % 900 + 21)) META=1 FWFT=$fw AW=3 DW=27 NX=$n"
      echo "tb_cdc_fifo PA=$a PB=$b SEED=$((RANDOM % 900 + 21)) META=1 FWFT=$fw AW=1 DW=8 NX=$n"
    done
    echo "tb_cdc_sync PA=$a PB=$b SEED=$((RANDOM % 900 + 21)) META=1 STAGES=3 NX=$n"
    echo "tb_cdc_handshake PA=$a PB=$b SEED=$((RANDOM % 900 + 21)) META=1 STAGES=3 NX=$n"
  done
}

neg_list() {
  local n=${N:-20000}
  for pr in "$P50:$P33" "$P33:$P50" "$P100:$P33" "$P33:$P100"; do
    a=${pr%%:*}; b=${pr##*:}
    echo "tb_cdc_fifo PA=$a PB=$b SEED=11 META=1 FWFT=1 NEG_BINARY=1 NX=$n"
    echo "tb_cdc_fifo PA=$a PB=$b SEED=12 META=1 FWFT=1 STAGES=0 NX=$n"
    echo "tb_cdc_fifo PA=$a PB=$b SEED=17 META=1 FWFT=0 NEG_EARLY=1 NX=$n"
    echo "tb_cdc_handshake PA=$a PB=$b SEED=13 META=1 STAGES=0 NX=$n"
    echo "tb_cdc_bus_sync PA=$a PB=$b SEED=14 META=1 STAGES=0 NX=$n"
    echo "tb_cdc_pulse PA=$a PB=$b SEED=15 META=1 CNT_W=1 MODE=1 NX=$n"
  done
}

run_list() {
  local out=$1
  : > "$out"
  # two runs at a time (the Mac is shared)
  xargs -P 2 -L 1 "$SELF" one >> "$out"
}

case "${1:-}" in
  compile) compile ;;
  one) shift; one "$@" ;;
  all) compile; jobs_list | run_list results.txt
       echo "runs: $(grep -c RESULT results.txt), with errors: $(grep RESULT results.txt | grep -vc ' errors=0' || true)" ;;
  extra) compile; extra_list | run_list results_extra.txt
       echo "runs: $(grep -c RESULT results_extra.txt), with errors: $(grep RESULT results_extra.txt | grep -vc ' errors=0' || true)" ;;
  neg) compile; neg_list | run_list results_neg.txt
       echo "runs: $(grep -c RESULT results_neg.txt), caught (errors > 0): $(grep RESULT results_neg.txt | grep -vc ' errors=0' || true)" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
