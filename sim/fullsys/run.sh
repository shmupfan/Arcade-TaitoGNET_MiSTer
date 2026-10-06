#!/bin/bash
# Run the full-system simulation (docs/fullsys_sim.md):
#   sim/fullsys/run.sh <name> <ms> [set] [extra harness args]
# e.g. run.sh t1 1500            BIOS, U30, keys, no card (zn2 build)
#      run.sh t2 4000 raycris    plus the Ray Crisis card image and metadata
# TAG selects the build (default zn2; main = PSX_MiSTer without the ZN-2
# board). Game data comes from GNET_DATA (default: the main checkout,
# roms/coh3002t.zip and sim/cards/<set>.*). Output: work/<TAG>/run_<name>/.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${TAG:-zn2}
DATA=${GNET_DATA:-$(git -C "$HERE" worktree list | head -1 | awk '{print $1}')}
NAME=$1; MS=$2; SET=${3:-}; shift $(( $# < 3 ? $# : 3 ))
D=$HERE/work/data
[ -f $D/bios.bin ] || python3 $HERE/prep.py $DATA/roms/coh3002t.zip $D
ARGS="-bios $D/bios.bin -u30 $D/u30.bin -keys $D/keys.hex"
if [ -n "$SET" ]; then
  [ -f $D/${SET}_meta.hex ] || python3 $HERE/prep.py $DATA/roms/coh3002t.zip $D $DATA/sim/cards $SET
  ARGS="$ARGS -meta $D/${SET}_meta.hex -card $DATA/sim/cards/$SET.img"
fi
nice -n 15 $HERE/work/$TAG/obj_dir/Vfs_top $ARGS -ms $MS -vram_ms ${VRAM_MS:-1000} -ppm ${PPM:-30} \
  -out $HERE/work/$TAG/run_$NAME "$@"
tail -1 $HERE/work/$TAG/run_$NAME/progress.log
