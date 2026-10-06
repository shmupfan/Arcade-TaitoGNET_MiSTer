#!/bin/bash
# G-NET system simulation (docs/zn2_layer_design.md 16):
#   sim/zn2/system/run.sh <name> <run_ms> [card set]
# e.g. run.sh t1 300          T1: BIOS, keys, flash.u30, no card
#      run.sh t2 3000 raycris T2: plus the Ray Crisis card image and metadata
# Work, inputs and logs: sim/zn2/work/system/ (gitignored, game-derived).
# Env SPLIT=1: psx_top CPU_CLK_SPLIT = 1 (CPU group at 50.000 / 100.000 MHz,
# docs/r1_cpu_domain_design.md "ZN-2 layer in the CPU group"); use its own
# ZN2_WORK. READ_DQM=false: the SDRAM chip model ignores read DQM.
# READ_OVERLAP=1: psx_top ZN2_READ_OVERLAP (memorymux read overlap); zlat.log
# has the zn_req to zn_ack cycles of every expansion bus request.
# PHASE / CPU_PHASE (SPLIT=1, e.g. 7ns / 0ns, the defaults): start delays of
# the PS1 and the CPU clocks; sweep.sh runs a list of them.
# Needs roms/coh3002t.zip and, for a card, sim/cards/<set>.* from
# tools/extract_card.sh (main checkout paths via GNET_DATA, default the
# repository root).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
DATA=${GNET_DATA:-$ROOT}
NAME=$1; MS=$2; SET=${3:-}
# ZN2_WORK: separate work library (to run two simulations at once)
W=${ZN2_WORK:-$ROOT/sim/zn2/work/system}
SPLIT=${SPLIT:-0}
if [ ! -f "$W/.built" ] || [ -n "${REBUILD:-}" ]; then
  "$HERE/build.sh" "$W" "$SPLIT"
  touch "$W/.built"
fi
python3 "$HERE/gen_tb.py" "$ROOT/rtl/psx_top.vhd" "$W/tb_zn2_system.vhd" "$SPLIT"
LIB=$W/cosim/libgnetfc.so
[ "$SPLIT" = 1 ] && LIB=$W/cosim50/libgnetfc.so
R=$W/run_$NAME
mkdir -p "$R"
if [ -n "$SET" ]; then
  python3 "$HERE/prep.py" "$DATA/roms/coh3002t.zip" "$R" "$DATA/sim/cards" "$SET"
  META="-gMETA_FILE=$R/meta.hex -gCARD_FILE=$DATA/sim/cards/$SET.img"
else
  python3 "$HERE/prep.py" "$DATA/roms/coh3002t.zip" "$R"
  META=""
fi
cd "$W"
NV="nvc --std=2008 -H 2g"
$NV --work=work -L . -a --relaxed tb_zn2_system.vhd > "$R/tb_analyse.log" 2>&1 || { grep -m 10 -A6 Error "$R/tb_analyse.log"; exit 1; }
# Loader test (LOAD_MODE=1): the MRA downloads through the PSX.sv loader logic
# and an hps_io model; FLASH_SKIP / CARD_SKIP bytes are downloaded, the rest
# preloaded. FLASH_FILE replaces flash.u30 (e.g. a warm <set>.flash).
U30=${FLASH_FILE:-$R/u30.bin}
LOADG="-gEARLY_READY=${EARLY_READY:-0} -gREAD_OVERLAP=${READ_OVERLAP:-0} -gPHASE=${PHASE:-7ns} -gCPU_PHASE=${CPU_PHASE:-0ns} -gTRACE_US=${TRACE_US:-0} -gREAD_DQM=${READ_DQM:-true} -gLOAD_MODE=${LOAD_MODE:-0} -gFLASH_SKIP=${FLASH_SKIP:-0} -gCARD_SKIP=${CARD_SKIP:-0} -gKEYS_BIN=$R/keys.bin"
[ -n "$SET" ] && LOADG="$LOADG -gMETA_BIN=$R/meta.bin"
$NV --work=work -L . -e tb_zn2_system -gBIOS_FILE=$R/bios.bin -gU30_FILE=$U30 -gKEY_FILE=$R/keys.hex \
  $META $LOADG -gLOGDIR=$R -gRUN_MS=$MS > "$R/elab.log" 2>&1 || { grep -m 10 -A6 Error "$R/elab.log"; exit 1; }
nice -n 15 $NV --work=work -L . -r tb_zn2_system --ieee-warnings=off --load="$LIB" > "$R/run.log" 2>&1
tail -5 "$R/run.log"
