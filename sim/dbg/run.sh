#!/bin/bash
# Benches for the G-NET debug overlay (docs/hw_debug_overlay.md), NVC 1.23,
# every run under nice -n 15, one at a time. Work files and frames go to
# sim/dbg/work/ (gitignored).
#
#   sim/dbg/run.sh regs      capture unit bench at 33.868 kHz and 50 kHz scaled clocks
#   sim/dbg/run.sh overlay   end-to-end: 320 wide (model on), 640 wide with
#                            doubling, model off, DR row (DDR3 arbiter status on
#                            its own clock); each frame decoded by check_frame.py
#   sim/dbg/run.sh neg       negative controls (mutants must fail, DR row included)
#   sim/dbg/run.sh all       all of the above
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
W="$HERE/work"
mkdir -p "$W"
cd "$W"
NVC="nice -n 15 nvc --std=2008"

analyse() {
   $NVC -a "$ROOT/rtl/gnet/cdc/cdc_pkg.vhd" "$ROOT/rtl/gnet/cdc/cdc_sync.vhd" \
      "$ROOT/rtl/gnet/cdc/cdc_capture.vhd" "$ROOT/rtl/gnet/cdc/cdc_handshake.vhd" \
      "$ROOT/rtl/gnet/zn_dbg_regs.vhd" "${1:-$ROOT/rtl/gnet/zn_dbg_overlay.vhd}" \
      "$HERE/tb_zn_dbg_regs.vhd" "$HERE/tb_zn_dbg_overlay.vhd"
}

run_regs() {
   for hz in 33868 50000; do
      $NVC -e -gCLK_HZ=$hz tb_zn_dbg_regs -r 2>&1 | grep -E "checks|FAIL|Failure"
   done
}

# $1 out name, then generics; prints the bench result and the decode
run_frame() {
   local out=$1; shift
   local dbl="" dr=""
   for g in "$@"; do [ "$g" = "-gDBL=1" ] && dbl="--dbl"; [ "$g" = "-gDR=1" ] && dr="--dr"; done
   $NVC -e "$@" -gOUTF="$out.ppm" tb_zn_dbg_overlay -r 2>&1 | grep -E "off:|on:|PASS|FAILED" || true
   [ -f "$out.ppm" ] && python3 "$HERE/check_frame.py" "$out.ppm" $dbl $dr --png "$out.png" | tail -1
}

run_overlay() {
   rm -f frame*.ppm
   run_frame frame320
   run_frame frame640 -gHA=640 -gHBL=96 -gDIV=4 -gDBL=1 -gPH_VID=5
   run_frame frame_nometa -gMETA=0 -gPH_VID=0 -gPH_SRC=0
   run_frame frame_dr -gDR=1
   run_frame frame_dr640 -gDR=1 -gHA=640 -gHBL=96 -gDIV=4 -gDBL=1 -gPH_DR=2
}

run_neg() {
   # mutant 1: the mixer ignores the OSD bit (Off must then differ)
   sed 's/show <= en_v(0) and box2;/show <= box2;/' "$ROOT/rtl/gnet/zn_dbg_overlay.vhd" > mut_en.vhd
   grep -q "show <= box2;" mut_en.vhd
   analyse "$W/mut_en.vhd"
   echo "mutant: overlay ignores the option (expect off differ > 0 and FAILED)"
   rm -f mut1.ppm; run_frame mut1 || true
   # mutant 2: next request without waiting for src_done (index and word misaligned)
   sed 's/hs_start <= vb and (not hs_busy) and (not hs_done);/hs_start <= vb and (not hs_busy);/' "$ROOT/rtl/gnet/zn_dbg_overlay.vhd" > mut_hs.vhd
   grep -q "hs_start <= vb and (not hs_busy);" mut_hs.vhd
   analyse "$W/mut_hs.vhd"
   echo "mutant: request issued in the src_done cycle (expect a decode FAIL)"
   rm -f mut2.ppm; run_frame mut2 || true
   # mutant 3: the DR row shows the word RAM instead of the clk_dr answer
   sed 's/q <= dr_rsp when/q <= q_ram when/' "$ROOT/rtl/gnet/zn_dbg_overlay.vhd" > mut_dr.vhd
   grep -q "q <= q_ram when" mut_dr.vhd
   analyse "$W/mut_dr.vhd"
   echo "mutant: DR row not taken from dr_word (expect a DR decode FAIL)"
   rm -f mut3.ppm; run_frame mut3 -gDR=1 || true
   analyse
}

case "${1:-all}" in
   regs)    analyse; run_regs ;;
   overlay) analyse; run_overlay ;;
   neg)     run_neg ;;
   all)     analyse; run_regs; run_overlay; run_neg ;;
   *)       echo "usage: $0 regs|overlay|neg|all"; exit 1 ;;
esac
