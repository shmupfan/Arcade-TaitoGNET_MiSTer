#!/bin/bash
# Equivalence of sys/ascal.vhd (working tree) against git HEAD's copy
# (docs/hdmi_timing.md F5). Usage: run.sh [scenario ...] (default 0 1 2 3).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p work && cd work
REF=${ASCAL_REF:-HEAD}
git show "$REF":sys/ascal.vhd |
  sed -e 's/^ENTITY ascal IS/ENTITY ascal_orig IS/' \
      -e 's/^END ENTITY ascal;/END ENTITY ascal_orig;/' \
      -e 's/^ARCHITECTURE rtl OF ascal IS/ARCHITECTURE rtl OF ascal_orig IS/' > ascal_orig.vhd
# Simulation-only wraps in both copies: natural registers that the hardware
# wraps at their bit width (o_pshift is 4 bits: o_off - 1 at o_off = 0 is 15)
# stop NVC with a range error.
# o_ihsizem: o_ihsize is 0 until the first input frame is measured.
WRAP='s/o_pshift<=o_off\(0\) -1;/o_pshift<=(o_off(0)+15) MOD 16;/;s/o_pshift<=o_pshift-1;/o_pshift<=(o_pshift+15) MOD 16;/;s/o_ihsizem<=o_ihsize \+ o_off\(0\) - 2;/o_ihsizem<=(o_ihsize + o_off(0) + 4094) MOD 4096;/'
sed -i '' -E "$WRAP" ascal_orig.vhd
sed -E "$WRAP" ../../../sys/ascal.vhd > ascal_new.vhd
NV="nvc --std=2008 --ieee-warnings=off"
$NV -a ascal_orig.vhd ascal_new.vhd ../tb_ascal_equiv.vhd
for s in "${@:-0 1 2 3}"; do
  for t in $s; do
    $NV -H 512m -e tb -gSCEN=$t -r --exit-severity=failure 2>&1 | grep -v "^\*\* Note" | tail -12
  done
done
