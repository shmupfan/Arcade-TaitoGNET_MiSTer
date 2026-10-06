#!/bin/bash
# Full-GTE equivalence: gte NARROW_MUL = 0 (upstream) against NARROW_MUL = NB
# (default 3) on the same random input sequence, every clk2x cycle
# (docs/cpu_rate_probe.md, "GTE at 100 MHz"). NVC.
#
# Env: N     clk2x cycles (default 2000000)
#      SEED  stimulus seed (default 1)
#      NB    NARROW_MUL of the second instance (default 3)
#      MUT   negative control: apply mutation MUT (1..11, list below) to a copy
#            of the RTL; the bench must then report a mismatch. The sim-only
#            req3 self-check in gte.vhd is disabled for these runs, so only the
#            bench's own comparison can catch the mutation.
#
# The work dir is outside the repository. gte.vhd's simulation trace block
# writes to R:\debug_gte_sim.txt, so a copy with that block disabled is used.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
R="$HERE/../../rtl"
N=${N:-2000000}; SEED=${SEED:-1}; NB=${NB:-3}; MUT=${MUT:-0}
W="${TMPDIR:-/tmp}/gnet_gte_equiv_s${SEED}_nb${NB}_m${MUT}"
rm -rf "$W"; mkdir -p "$W/rtl" && cd "$W"
cp "$R/pGTE.vhd" "$R/gte_mac0.vhd" "$R/gte_mac123.vhd" "$R/gte_UNRDivide.vhd" rtl/
sed 's/goutput : if 1 = 1 generate/goutput : if 1 = 0 generate/' "$R/gte.vhd" > rtl/gte.vhd

mut() {   # file, sed expression: must change the file
   cp "rtl/$1" "rtl/$1.orig"
   sed -i.bak "$2" "rtl/$1"
   if cmp -s "rtl/$1" "rtl/$1.orig"; then echo "mutation $MUT did not apply"; exit 2; fi
   sed -i.bak 's/gcheck3 : if NARROW_MUL = 3 generate/gcheck3 : if false generate/' rtl/gte.vhd
}
case "$MUT" in
  0) ;;
  1)  mut gte.vhd 's/if (tv \/= "10") then r.uRes/if (tv = "10") then r.uRes/' ;;            # MVMVA step 3 accumulate flag inverted
  2)  mut gte.vhd 's/=> r3S(r, true);/=> r3S(r, false);/' ;;                                   # NCCS/CC step 13/8 without the sf/lm flags
  3)  mut gte.vhd 's/s45(r.k0 or (r.kGPL and not gpl1000)/s45(r.k0 or (r.kGPL and gpl1000)/' ;; # GPL shift amount inverted (x1 path)
  4)  mut gte_UNRDivide.vhd 's/(calc_prod + x"8000")/(calc_prod + x"4000")/' ;;                # divider rounding constant
  5)  mut gte.vhd 's/when CALC_DPCT             => if (s =  8) then r.lp/when CALC_DPCT             => if (s =  7) then r.lp/' ;; # DPCT loop one step early
  6)  mut gte_mac123.vhd "s/(opP \& MACreq.sub)/(opP \& '0')/" ;;                              # a - p and p - a without the carry in
  7)  mut gte.vhd 's/r.a0IR2_2 := /r.a0IR2_1 := /' ;;                                         # RTPT step 16 uses IR2 of round 1
  8)  mut gte.vhd 's/REG_V2Z, REG_IR1, REG_IR3, REG_IR0/REG_V2Z, REG_IR1, REG_IR1, REG_IR0/' ;; # OP MAC2 second product IR1 for IR3
  9)  mut gte.vhd 's/MAC0mul3.ena  <= procEna3 and req3.t0;/MAC0mul3.ena  <= req3.t0;/' ;;      # MAC0 product not held while ce = 0 or reset
  10) mut gte.vhd 's/MAC1mul3.ena     <= procEna3 and req3.t;/MAC1mul3.ena     <= req3.t;/' ;;  # MAC1 product not held while ce = 0 or reset
  11) mut gte.vhd "s/(req3.lp = '1' and batchCount = 2)/(req3.lp = '1' and batchCount = 1)/" ;;          # triple commands: turbo exit after the second vertex
  *) echo "unknown MUT $MUT"; exit 2 ;;
esac

nvc --std=2008 -a rtl/pGTE.vhd rtl/gte_mac0.vhd rtl/gte_mac123.vhd rtl/gte_UNRDivide.vhd rtl/gte.vhd "$HERE/tb_gte_equiv.vhd"
nvc --std=2008 -e tb_gte_equiv -gN=$N -gSEED=$SEED -gNB=$NB
nice -n 15 nvc -r tb_gte_equiv --ieee-warnings=off
