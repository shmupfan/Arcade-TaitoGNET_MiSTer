#!/bin/bash
# Build tb_rot (Verilator), nice -n 15: sim/rotfx/build.sh <feed 0|1>
# video_mixer comes from sim/rotfx/video_mixer_sim.sv (Verilator-friendly copy).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FEED=${1:-0}
OBJ=$HERE/work/obj_feed$FEED
mkdir -p "$HERE/work"
cd "$ROOT"
nice -n 15 verilator --cc --exe --build -j 2 -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PROCASSWIRE \
  --x-assign 0 --x-initial 0 --top-module rot_top -GFEED=$FEED -Isys --Mdir "$OBJ" -o tb_rot \
  "$HERE/rot_top.sv" sys/arcade_video.v "$HERE/video_mixer_sim.sv" sys/scandoubler.v sys/hq2x.sv sys/gamma_corr.sv sys/video_freezer.sv \
  rtl/gnet/gnet_ddr3_arb.sv "$HERE/tb_rot.cpp" > "$OBJ.log" 2>&1 || { grep -m 30 -E '%Error|error:' "$OBJ.log"; exit 1; }
echo "built $OBJ/tb_rot"
