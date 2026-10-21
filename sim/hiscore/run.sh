#!/bin/bash
# High score save bench (tb_hs.sv, docs/hiscore.md 5): builds the bench
# without and with GNET_HISCORE, runs both (the GNET_HISCORE build twice:
# the main sequence, and +old, a load with a file from an older release),
# compares the 2 KB EEPROM-only files of the two builds, then the
# negative-control mutants of gnet_hiscore.sv (each must FAIL). At most 2
# simulations at once.
#   sim/hiscore/run.sh [main|on|mutants|all]   (default all)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W=$HERE/work
WHAT=${1:-all}
mkdir -p "$W"
python3 "$HERE/gen_glue.py" "$ROOT/PSX.sv" "$W"

# cdc_handshake (64-bit request, 32-bit response, as PSX.sv's ch3_cdc) and
# zn2_ch3_arb, VHDL to Verilog
OSS=${OSS_CAD:-$HOME/tools/oss-cad-suite}
( export PATH=$OSS/bin:$PATH GHDL_PREFIX=$OSS/lib/ghdl
  rm -rf "$W/ghdl"; mkdir -p "$W/ghdl"
  ghdl -a --std=08 -frelaxed --workdir="$W/ghdl" "$ROOT/rtl/gnet/cdc/cdc_pkg.vhd" "$ROOT/rtl/gnet/cdc/cdc_sync.vhd" \
    "$ROOT/rtl/gnet/cdc/cdc_capture.vhd" "$ROOT/rtl/gnet/cdc/cdc_handshake.vhd" "$ROOT/rtl/gnet/zn2_ch3_arb.vhd"
  ghdl --synth --std=08 -frelaxed --workdir="$W/ghdl" -gREQ_W=64 -gRSP_W=32 --out=verilog cdc_handshake > "$W/cdc_handshake.v"
  ghdl --synth --std=08 -frelaxed --workdir="$W/ghdl" --out=verilog zn2_ch3_arb > "$W/zn2_ch3_arb.v" )
python3 "$ROOT/sim/fullsys/fix_netlist.py" "$W/cdc_handshake.v" > /dev/null
python3 "$ROOT/sim/fullsys/fix_netlist.py" "$W/zn2_ch3_arb.v" > /dev/null

build() {   # build <name> <gnet_hiscore.sv or -> <defines...>
  local name=$1 hsv=$2; shift 2
  local files="$HERE/tb_hs.sv $ROOT/sys/hps_io.sv $W/cdc_handshake.v $W/zn2_ch3_arb.v"
  [ "$hsv" != "-" ] && files="$files $hsv $ROOT/rtl/gnet/hiscore.v"
  nice -n 15 verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-PROCASSWIRE -Wno-TIMESCALEMOD \
    -Wno-PINMISSING --top-module tb_hs -Mdir "$W/obj_$name" -I"$W" "$@" $files > "$W/build_$name.log" 2>&1 \
    || { tail -30 "$W/build_$name.log"; exit 1; }
}
run() {     # run <name> <outdir> <plusargs...>
  local name=$1 out=$2; shift 2
  mkdir -p "$out"
  nice -n 15 "$W/obj_$name/Vtb_hs" +out="$out" "$@" > "$out/run.log" 2>&1 || true
  grep -E "^RESULT" "$out/run.log" || echo "RESULT none (crashed?) in $out/run.log"
}

if [ "$WHAT" = main ] || [ "$WHAT" = all ]; then
  build off -
  run off "$W/off"
fi
if [ "$WHAT" = main ] || [ "$WHAT" = all ] || [ "$WHAT" = on ]; then
  build on "$ROOT/rtl/gnet/gnet_hiscore.sv" +define+HS
  run on "$W/on"
  run on "$W/on_old" +old
  if [ -f "$W/off/out_a.hex" ]; then
    if cmp -s "$W/off/out_a.hex" "$W/on/out_a.hex"; then
      echo "ok   EEPROM-only 2 KB file byte-identical without and with GNET_HISCORE"
    else
      echo "FAIL EEPROM-only 2 KB file differs between the builds"
    fi
  fi
fi

if [ "$WHAT" = mutants ] || [ "$WHAT" = all ]; then
  rm -rf "$W/mut"
  python3 "$HERE/mutants.py" "$ROOT/rtl/gnet/gnet_hiscore.sv" "$W/mut"
  names=$(cd "$W/mut" && ls -d */ | tr -d /)
  for m in $names; do build "m_$m" "$W/mut/$m/gnet_hiscore.sv" +define+HS; done
  set -- $names
  while [ $# -gt 0 ]; do
    a=$1; shift; b=${1:-}; [ -n "$b" ] && shift
    run "m_$a" "$W/mut/$a" $(cat "$W/mut/$a/args") +quick > "$W/mut/$a.result" &
    [ -n "$b" ] && run "m_$b" "$W/mut/$b" $(cat "$W/mut/$b/args") +quick > "$W/mut/$b.result" &
    wait
  done
  for m in $names; do
    r=$(cat "$W/mut/$m.result")
    case "$r" in *FAIL*) echo "ok   mutant $m caught: $r";; *) echo "FAIL mutant $m not caught: $r";; esac
  done
fi
