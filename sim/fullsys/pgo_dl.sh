#!/bin/bash
# Profile-guided rebuild of the download-path builds of zn2fulldl.sh
# (docs/i12_ddr3_load.md 6.2): as pgo.sh, but the training run is TRAIN_MS
# (default 300) of a -dl list, since these builds need one.
#   TAG=i12 sim/fullsys/pgo_dl.sh obj_dir <dl list> [VFLAGS]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TAG=${TAG:-i12}; MD=$1; DL=$2; VF=${3:-}
W=$HERE/work/$TAG
P=$W/pgo_$MD; rm -rf $P; mkdir -p $P
export TAG
MDIR=${MD}_gen VFLAGS="$VF" COPT="-O2 -fprofile-instr-generate=$P/fs-%p.profraw" LOPT="-fprofile-instr-generate" $HERE/build.sh
nice -n 15 $W/${MD}_gen/Vfs_top -dl $DL -cpu_mhz 50 -dqm 1 -ms ${TRAIN_MS:-300} -ppm 0 -pre_ms 5 -out $W/pgo_train_$MD > /dev/null
xcrun llvm-profdata merge -o $P/fs.profdata $P/*.profraw
MDIR=$MD VFLAGS="$VF" COPT="-O2 -fprofile-instr-use=$P/fs.profdata -Wno-profile-instr-out-of-date -Wno-profile-instr-unprofiled" $HERE/build.sh
