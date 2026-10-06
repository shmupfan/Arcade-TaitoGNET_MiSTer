#!/bin/bash
# Profile-guided build of the full-system simulation (docs/fullsys_sim.md 4):
# an instrumented build, a training run of TRAIN_MS (default 1000) of the
# G-NET BIOS without a card, then the final build in work/<TAG>/obj_dir
# with the profile. About 1.7x faster than the plain build, same results.
#   TAG=zn2 sim/fullsys/pgo.sh      (after zn2.sh or convert.sh)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${TAG:-zn2}
W=$HERE/work/$TAG
P=$W/pgo; rm -rf $P; mkdir -p $P
D=$HERE/work/data
DATA=${GNET_DATA:-$(git -C "$HERE" worktree list | head -1 | awk '{print $1}')}
[ -f $D/bios.bin ] || python3 $HERE/prep.py $DATA/roms/coh3002t.zip $D
export TAG
MDIR=obj_pgogen COPT="-O2 -fprofile-instr-generate=$P/fs-%p.profraw" LOPT="-fprofile-instr-generate" $HERE/build.sh
ARGS="-bios $D/bios.bin -u30 $D/u30.bin"
[ "$TAG" = main ] || ARGS="$ARGS -keys $D/keys.hex"
nice -n 15 $W/obj_pgogen/Vfs_top $ARGS -ms ${TRAIN_MS:-1000} -ppm 0 -out $W/pgo_train > /dev/null
xcrun llvm-profdata merge -o $P/fs.profdata $P/*.profraw
COPT="-O2 -fprofile-instr-use=$P/fs.profdata -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" $HERE/build.sh
