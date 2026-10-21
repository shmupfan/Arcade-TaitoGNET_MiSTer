#!/bin/bash
# zn2_cardmem: the journal client off (CARD_JOURNAL = false) behaves exactly
# as alpha4's zn2_cardmem. Both VHDL files through ghdl --synth, then a
# Verilator co-simulation with random inputs (tb_eq_cardmem.sv), and the
# negative control with the journal client requesting (must differ).
#   sim/i9/eq_cardmem.sh [base revision, default alpha4]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W=$HERE/work/eq; mkdir -p "$W/g1" "$W/g2"
OSS=${OSS_CAD:-$HOME/tools/oss-cad-suite}
export PATH=$OSS/bin:$PATH GHDL_PREFIX=$OSS/lib/ghdl
git -C "$ROOT" show "${1:-alpha4}:rtl/gnet/zn2_cardmem.vhd" > "$W/old.vhd"
ghdl -a --std=08 -frelaxed --workdir="$W/g1" "$W/old.vhd"
ghdl --synth --std=08 -frelaxed --workdir="$W/g1" --out=verilog zn2_cardmem | sed 's/^module zn2_cardmem/module gold/' > "$W/old.v"
ghdl -a --std=08 -frelaxed --workdir="$W/g2" "$ROOT/rtl/gnet/zn2_cardmem.vhd"
for ul in 0 1; do
  gen=false; [ $ul = 1 ] && gen=true
  ghdl --synth --std=08 -frelaxed --workdir="$W/g2" -gCARD_JOURNAL=$gen --out=verilog zn2_cardmem | sed 's/^module zn2_cardmem/module gate/' > "$W/new$ul.v"
  def=; [ $ul = 1 ] && def=+define+UL_ON
  nice -n 15 verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style --top-module tb_eq_cardmem \
    -Mdir "$W/obj$ul" $def "$HERE/tb_eq_cardmem.sv" "$W/old.v" "$W/new$ul.v" > "$W/build$ul.log" 2>&1 || { tail "$W/build$ul.log"; exit 1; }
  r=$(nice -n 15 "$W/obj$ul/Vtb_eq_cardmem" | grep '^EQ')
  if [ $ul = 0 ]; then
    case "$r" in *"differing 0") echo "ok   CARD_JOURNAL false = alpha4: $r";; *) echo "FAIL CARD_JOURNAL false differs: $r";; esac
  else
    case "$r" in *"differing 0") echo "FAIL negative control not caught: $r";; *) echo "ok   negative control (journal client on) differs: $r";; esac
  fi
done
