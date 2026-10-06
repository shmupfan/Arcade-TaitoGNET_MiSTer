#!/bin/bash
# zn2_io directed tests with NVC (docs/zn2_layer_design.md 16).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
W=$HERE/work/zn2_io
mkdir -p "$W"
cd "$W"
nvc --std=2008 -a --relaxed "$ROOT/sim/system/src/mem/dpram.vhd" "$ROOT/rtl/gnet/zn2_io.vhd" "$HERE/tb_zn2_io.vhd"
nvc --std=2008 -e tb_zn2_io
nice -n 15 nvc --std=2008 -r tb_zn2_io --ieee-warnings=off
# Replay of a MAME ZN-2 map trace, if given:
#   sim/zn2/run_zn2_io.sh <zn2map run dir> <at28c16 NVRAM the run started from>
if [ $# -ge 2 ]; then
  V=$HERE/work/zn2io_$(basename "$1")
  mkdir -p "$V"
  python3 "$ROOT/tools/gnet/zn2io_vectors.py" "$1/zn2map.log" "$2" "$V"
  nvc --std=2008 -a "$HERE/tb_zn2_io_replay.vhd"
  nvc --std=2008 -e tb_zn2_io_replay -gDIR="$V"
  nice -n 15 nvc --std=2008 -r tb_zn2_io_replay --ieee-warnings=off
fi
