#!/bin/bash
# Full replay of one game's glue trace against MAME's end state.
#   sim/gnet/run_replay.sh <set> [obj dir]   (run from the repository root)
# Inputs (gitignored): sim/gnet/work/tr_<set>/ (tools/mame/glue_trace_run.sh),
# sim/gnet/work/flash.u30, the extracted card in ../gnet-mister/sim/cards or
# $CARDS. Writes sim/gnet/work/replay_<set>.log.
set -euo pipefail
S=$1; OBJ=${2:-obj_mame}
W=sim/gnet/work; C=${CARDS:-sim/cards}
ref=""; [ -f $W/tr_$S/card_mame.img ] && ref="--card-ref $W/tr_$S/card_mame.img"
nice -n 15 sim/gnet/$OBJ/tb_gnet_fc --trace $W/tr_$S/glue.zst --card $C/$S.img --idnt $C/$S.idnt \
  --cis $C/$S.cis --key $C/$S.key --u30 $W/flash.u30 --nvram $W/tr_$S/nvram/$S $ref --max-mis 40 \
  > $W/replay_$S.log 2>&1 || true
tail -12 $W/replay_$S.log
