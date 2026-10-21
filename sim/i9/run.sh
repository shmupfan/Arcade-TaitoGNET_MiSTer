#!/bin/bash
# Issue #9 bench (tb_cj.sv): builds the bench without and with
# GNET_CARD_JOURNAL, runs both, compares the Go By RC files, then the
# negative-control mutants (each must FAIL). At most 2 simulations at once.
#   sim/i9/run.sh [main|on|mutants|all]   (default all; on = journal build only)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W=$HERE/work
WHAT=${1:-all}
mkdir -p "$W"
python3 "$HERE/gen_glue.py" "$ROOT/PSX.sv" "$W"
[ -f "$W/card_orig.bin" ] || python3 "$HERE/prep_data.py"

# zn2_cardmem (VHDL) to Verilog, CARD_JOURNAL = true
OSS=${OSS_CAD:-$HOME/tools/oss-cad-suite}
( export PATH=$OSS/bin:$PATH GHDL_PREFIX=$OSS/lib/ghdl
  mkdir -p "$W/ghdl"
  ghdl -a --std=08 -frelaxed --workdir="$W/ghdl" "$ROOT/rtl/gnet/zn2_cardmem.vhd"
  ghdl --synth --std=08 -frelaxed --workdir="$W/ghdl" -gCARD_JOURNAL=true --out=verilog zn2_cardmem > "$W/zn2_cardmem.v" )
python3 "$ROOT/sim/fullsys/fix_netlist.py" "$W/zn2_cardmem.v" > /dev/null

build() {   # build <name> <journal.sv or -> <defines...>
  local name=$1 jsv=$2; shift 2
  local files="$HERE/tb_cj.sv $ROOT/sys/hps_io.sv $ROOT/rtl/gnet/gnet_ata.sv $W/zn2_cardmem.v"
  [ "$jsv" != "-" ] && files="$files $jsv"
  nice -n 15 verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-PROCASSWIRE -Wno-TIMESCALEMOD \
    --top-module tb_cj -Mdir "$W/obj_$name" -I"$W" "$@" $files > "$W/build_$name.log" 2>&1 \
    || { tail -30 "$W/build_$name.log"; exit 1; }
}
run() {     # run <name> <outdir> <plusargs...>
  local name=$1 out=$2; shift 2
  mkdir -p "$out"
  nice -n 15 "$W/obj_$name/Vtb_cj" +work="$W" +out="$out" "$@" > "$out/run.log" 2>&1 || true
  grep -E "^RESULT" "$out/run.log" || echo "RESULT none (crashed?) in $out/run.log"
}

if [ "$WHAT" = main ] || [ "$WHAT" = all ]; then
  build off -
  run off "$W/off"
fi
if [ "$WHAT" = main ] || [ "$WHAT" = all ] || [ "$WHAT" = on ]; then
  build on "$ROOT/rtl/gnet/gnet_card_journal.sv" +define+CJ
  run on "$W/on" +fold="$W/off/out_old.hex" +fsyn="$W/off/syn_journal.hex"
  if cmp -s "$W/off/out_p1.hex" "$W/on/out_p1.hex"; then
    echo "ok   Go By RC 2 KB file byte-identical without and with GNET_CARD_JOURNAL"
  else
    echo "FAIL Go By RC 2 KB file differs between the builds"
  fi
fi

if [ "$WHAT" = mutants ] || [ "$WHAT" = all ]; then
  python3 "$HERE/mutants.py" "$ROOT/rtl/gnet/gnet_card_journal.sv" "$W/mut"
  names=$(ls "$W/mut")
  for m in $names; do build "m_$m" "$W/mut/$m/gnet_card_journal.sv" +define+CJ; done
  set -- $names
  while [ $# -gt 0 ]; do
    a=$1; shift; b=${1:-}; [ -n "$b" ] && shift
    run "m_$a" "$W/mut/$a" +quick +fold="$W/off/out_old.hex" +fsyn="$W/off/syn_journal.hex" > "$W/mut/$a.result" &
    [ -n "$b" ] && run "m_$b" "$W/mut/$b" +quick +fold="$W/off/out_old.hex" +fsyn="$W/off/syn_journal.hex" > "$W/mut/$b.result" &
    wait
  done
  for m in $names; do
    r=$(cat "$W/mut/$m.result")
    case "$r" in *FAIL*) echo "ok   mutant $m caught: $r";; *) echo "FAIL mutant $m not caught: $r";; esac
  done
fi
