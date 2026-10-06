#!/bin/bash
# CAT702 RTL replay against MAME 0.288 traffic (docs/zn2_layer_design.md 16.1).
#   sim/zn2/run_cat702.sh <oracle run dir with sec.log> [coh3002t.zip]
# Vectors and keys go to sim/zn2/work/ (gitignored: derived from the BIOS).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RUN=$1
ZIP=${2:-$ROOT/roms/coh3002t.zip}
W=$HERE/work/cat702_$(basename "$RUN")
mkdir -p "$W"
python3 "$ROOT/tools/gnet/cat702_ref.py" vectors "$RUN/sec.log" "$ZIP" "$W"
cd "$W"
nvc --std=2008 -a "$ROOT/rtl/gnet/zn_cat702.vhd" "$HERE/tb_cat702.vhd"
for n in 0 1; do
  nvc --std=2008 -e tb_cat702 -gDIR="$W" -gN=$n
  nice -n 15 nvc -r tb_cat702 --ieee-warnings=off
done
