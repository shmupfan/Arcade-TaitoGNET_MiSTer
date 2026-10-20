#!/bin/bash
# MDEC equivalence (tb_mdec_equiv.vhd, NVC): rtl/mdec.vhd against the
# rtl/mdec.vhd of git revision REF (default alpha3), same command streams.
#
#   sim/mdec/run.sh            all cases below
#   case dc     one mono 8-bit DC-only block, expected 64 x 0x8C (hand value)
#   case mono   200 random mono 8-bit blocks, expected from gen_stim.py's model
#   case rS     random streams, seeds 1..4: all depths, standard and random
#               scale tables, random quant tables, saturating blocks
#
# Pass: result words and IDCT result RAM writes identical in order for both
# instances, and equal to the .expect file where there is one.
# Env: REF (git revision of the reference), NMB (decode commands per random
#      stream, default 150), MUT=1 negative control (the new copy's stage R
#      first flag is skipped; the bench must fail).
# Work data in $TMPDIR. Each simulation under nice -n 15, one at a time.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
R=$ROOT/rtl; M=$ROOT/sim/system/src/mem
REF=${REF:-alpha3}; NMB=${NMB:-150}; MUT=${MUT:-0}
W="${TMPDIR:-/tmp}/gnet_mdec_equiv_m$MUT"
NV="nvc --std=2008 -H 512m"
rm -rf "$W"; mkdir -p "$W/rtl"; cd "$W"

nodbg='s/goutput : if 1 = 1 generate/goutput : if 1 = 0 generate/'
git -C "$ROOT" show "$REF:rtl/mdec.vhd" | sed -e "$nodbg" \
   -e 's/^entity mdec is/entity mdec_ref is/' -e 's/^architecture arch of mdec is/architecture arch of mdec_ref is/' \
   > rtl/mdec_ref.vhd
sed -e "$nodbg" "$R/mdec.vhd" > rtl/mdec.vhd
if [ "$MUT" = 1 ]; then
   sed -i.bak 's/idct_calc1_first   <= idct_calcR_first;/idct_calc1_first   <= idct_calc0_first;/' rtl/mdec.vhd
   if cmp -s rtl/mdec.vhd rtl/mdec.vhd.bak; then echo "mutation did not apply"; exit 2; fi
fi
grep -q "entity mdec_ref is" rtl/mdec_ref.vhd || { echo "reference rename failed"; exit 2; }

$NV --work=mem -a --relaxed "$R/SyncFifoFallThrough.vhd" > build.log 2>&1
$NV --work=work -L . -a --relaxed "$M/dpram.vhd" rtl/mdec_ref.vhd rtl/mdec.vhd "$HERE/tb_mdec_equiv.vhd" >> build.log 2>&1 \
   || { grep -m 10 -A4 -i error build.log; exit 1; }

fail=0
run_case() {   # name, stimulus base, expected word count, expect file or ""
   local name=$1 base=$2 nout=$3 exp=$4
   mkdir -p "$W/$name"; cd "$W/$name"
   $NV --work="$W/work" -L "$W" -e tb_mdec_equiv -gSTIM="$base.stim" -gNOUT="$nout" > elab.log 2>&1 \
      || { echo "$name: elaboration failed"; tail -5 elab.log; fail=1; cd "$W"; return; }
   nice -n 15 $NV --work="$W/work" -L "$W" -r tb_mdec_equiv --ieee-warnings=off > run.log 2>&1 || true
   local msg; msg=$(grep -o "MDEC_EQUIV.*" run.log || echo "no result")
   local verdict=PASS
   case "$msg" in *TIMEOUT*|"no result") verdict=FAIL ;; esac
   cmp -s out_0.txt out_1.txt || verdict=FAIL
   cmp -s idct_0.txt idct_1.txt || verdict=FAIL
   [ "$(wc -l < out_1.txt)" -eq "$nout" ] || verdict=FAIL
   if [ -n "$exp" ]; then cmp -s out_1.txt "$exp" || verdict="FAIL (expect)"; fi
   echo "$name: $verdict  words $(wc -l < out_1.txt | tr -d ' ')  idct writes $(wc -l < idct_1.txt | tr -d ' ')  $msg"
   case "$verdict" in PASS) ;; *) fail=1 ;; esac
   cd "$W"
}

n=$(python3 "$HERE/gen_stim.py" dc "$W/dc"); run_case dc "$W/dc" "$n" "$W/dc.expect"
n=$(python3 "$HERE/gen_stim.py" mono 7 200 "$W/mono"); run_case mono "$W/mono" "$n" "$W/mono.expect"
for s in 1 2 3 4; do
   n=$(python3 "$HERE/gen_stim.py" random "$s" "$NMB" "$W/r$s"); run_case "r$s" "$W/r$s" "$n" ""
done
[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES (work in $W)"; exit 1; }
