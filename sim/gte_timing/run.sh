#!/bin/bash
# GTE command hold times at clock ratio 2 and 1.6 (docs/cpu_rate_probe.md).
# Work dir outside the repo. gte.vhd's simulation-only trace block writes to
# R:\debug_gte_sim.txt, so a copy with that block disabled is compiled.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../../rtl"
W="${TMPDIR:-/tmp}/gnet_gte_timing_work"
mkdir -p "$W" && cd "$W"
sed 's/goutput : if 1 = 1 generate/goutput : if 1 = 0 generate/' "$R/gte.vhd" > gte_nofile.vhd
nvc --std=2008 -a "$R/pGTE.vhd" "$R/gte_mac0.vhd" "$R/gte_mac123.vhd" "$R/gte_UNRDivide.vhd" gte_nofile.vhd "$HERE/tb_gte_busy_ratio.vhd"
run() { nvc --std=2008 -e tb_gte_busy_ratio -gCPU_NS=$1 -gSTROBE=$2 -gTURBO_I=$3 -gNM=${5:-0} >/dev/null
        nice -n 15 nvc -r tb_gte_busy_ratio --ieee-warnings=off | grep '^op' > "$4"; echo "$4"; }
run 20 0 0 ratio2_psxtop.txt      # PSX_MiSTer as built (psx_top strobe)
run 20 1 0 ratio2_strobe1.txt     # check: first-edge strobe at ratio 2 gives the same
run 16 1 0 ratio16.txt            # 1.6x, gte.vhd unmodified
run 16 1 1 ratio16_turbo.txt      # 1.6x, turbo step sequences
run 20 0 0 ratio2_psxtop_nm3.txt 3        # GTE NARROW_MUL = 3 (100 MHz option): must equal ratio2_psxtop.txt
run 20 0 1 ratio2_psxtop_turbo.txt 0      # turbo at 2x, upstream
run 20 0 1 ratio2_psxtop_turbo_nm3.txt 3  # turbo at 2x, NARROW_MUL = 3: must equal ratio2_psxtop_turbo.txt
cmp ratio2_psxtop.txt ratio2_psxtop_nm3.txt && cmp ratio2_psxtop_turbo.txt ratio2_psxtop_turbo_nm3.txt && echo "NARROW_MUL = 3: hold counts identical at 2x (turbo off and on)"
