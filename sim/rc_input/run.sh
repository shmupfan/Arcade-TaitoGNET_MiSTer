#!/bin/bash
# Bench for the Go By RC wheel and trigger mapping in PSX.sv (issue #4).
# Takes the rc_x .. zn_an1 block out of PSX.sv as it is, wraps it in
# tb_rc_input.sv and checks every stick X/Y pair, the D-pad, the paddle and
# other sets against MAME's ranges (rest 80h/80h, wheel 80h + X, trigger
# 80h - Y). Usage: sim/rc_input/run.sh [PSX.sv]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:-$HERE/../../PSX.sv}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
awk '/^wire \[7:0\] rc_x    =/{f=1} f{print} /^                    zj1\[3\] \? 8.hFF/{f=0}' "$SRC" > "$OUT/rc_block.svh"
[ -s "$OUT/rc_block.svh" ] || { echo "rc block not found in $SRC" >&2; exit 2; }
cp "$HERE/tb_rc_input.sv" "$OUT/"
cd "$OUT"
verilator --binary --timing -Wno-fatal -Wno-WIDTH tb_rc_input.sv --top-module tb -o tb_rc > build.log 2>&1 || { cat build.log; exit 1; }
./obj_dir/tb_rc | grep -v '^- ' | tail -20
./obj_dir/tb_rc | grep -q 'checks, 0 failures'
