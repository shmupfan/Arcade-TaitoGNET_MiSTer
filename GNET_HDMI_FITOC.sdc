# Fitter-only over-constraint of the HDMI clock (docs/hdmi_timing.md, fix F1).
#
# Copyright (C) 2026 Lee Foot
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Origin: written for this core. Evidence: the fit reports and STA path
# lists in docs/hdmi_timing.md (tools/sta/hdmi_paths.tcl). Read by
# GNET_Z1FULLR.qsf from alpha 4.
#
# The HDMI setup failures of GNET_Z1FULLR are paths inside the framework
# scaler (sys/ascal.vhd, o_clk = pll_hdmi counter[0], 6.732 ns): every setup
# transfer into this clock is HDMI to HDMI, the crossings are false paths in
# sys_top.sdc and GNET_LEAN.sdc. The same RTL meets with +0.135 to +0.729 ns
# in the glue cores (33 to 72 % ALMs), and five seeds of one G-NET commit
# (1f6d3dc, 87 %) span -0.227 to +0.260 ns, so placement decides it.
#
# Here quartus_fit (and only quartus_fit) sees 0.25 ns more setup
# uncertainty on HDMI to HDMI paths, so the placer and router keep margin on
# that clock. quartus_sta never applies it: the sign-off STA, the release
# gate and tools/sta/*.tcl time the real 6.732 ns relationship with the
# derived uncertainty only. Timing-driven synthesis (quartus_map) does not
# apply it either.
#
# Check after a fit: compile.log has the message below once, from quartus_fit,
# and not from quartus_sta.
set gnet_hdmi_clk {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
set gnet_fit_oc 0.25
# Revision-free toggle (docs/area_timing.md): the environment variable
# GNET_FIT_OC overrides the 0.25 ns for one fit (tools/pc_build.sh FIT_OC=<ns>
# writes it into the task); 0 turns F1 off. Unset, the fit is as before.
if {[info exists ::env(GNET_FIT_OC)] && [string is double -strict $::env(GNET_FIT_OC)]} {
  set gnet_fit_oc $::env(GNET_FIT_OC)
}
if {[info exists ::TimeQuestInfo(nameofexecutable)] && \
    $::TimeQuestInfo(nameofexecutable) eq "quartus_fit" && $gnet_fit_oc > 0} {
  set_clock_uncertainty -setup -add \
    -from [get_clocks $gnet_hdmi_clk] -to [get_clocks $gnet_hdmi_clk] $gnet_fit_oc
  catch { post_message -type info "GNET_HDMI_FITOC: fitter over-constraint +$gnet_fit_oc ns setup on HDMI to HDMI" }
} elseif {[info exists ::TimeQuestInfo(nameofexecutable)] && \
          $::TimeQuestInfo(nameofexecutable) eq "quartus_fit"} {
  catch { post_message -type info "GNET_HDMI_FITOC: off for this fit (GNET_FIT_OC=$gnet_fit_oc)" }
}
