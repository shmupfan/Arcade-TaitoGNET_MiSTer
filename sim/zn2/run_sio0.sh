#!/bin/bash
# SIO0 + CAT702 x2 + znmcu replay against MAME 0.288 sec.log traffic
# (docs/zn2_layer_design.md 16).
#   sim/zn2/run_sio0.sh <oracle run dir with sec.log> [max_seconds] [coh3002t.zip]
# Vectors and keys go to sim/zn2/work/ (gitignored: game-derived).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RUN=$1
MAX=${2:-}
ZIP=${3:-$ROOT/roms/coh3002t.zip}
W=$HERE/work/sio0_$(basename "$RUN")
mkdir -p "$W"
python3 "$ROOT/tools/gnet/cat702_ref.py" vectors "$RUN/sec.log" "$ZIP" "$W" > /dev/null
python3 "$ROOT/tools/gnet/sio0_vectors.py" "$RUN/sec.log" "$W/sio0.vec" $MAX
cd "$W"
nvc --std=2008 -a "$ROOT/rtl/gnet/zn_cat702.vhd" "$ROOT/rtl/gnet/znmcu.vhd" "$ROOT/rtl/gnet/zn_sio0.vhd" "$HERE/tb_sio0_replay.vhd"
nvc --std=2008 -e tb_sio0_replay -gDIR="$W"
nice -n 15 nvc --std=2008 -r tb_sio0_replay --ieee-warnings=off
