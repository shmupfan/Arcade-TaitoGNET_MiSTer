#!/bin/bash
# NVC equivalence run for the narrow GTE multiplier (work dir gitignored via sim/gte_narrow/work)
set -e
cd "$(dirname "$0")"
R=../../../rtl
mkdir -p work && cd work
nvc --std=2008 -a $R/pGTE.vhd $R/gte_mac123.vhd ../tb_mac_narrow.vhd
nvc --std=2008 -e tb_mac_narrow -gN=${N:-2000000} -gNM=${NM:-1}
nice -n 15 nvc -r tb_mac_narrow --ieee-warnings=off
