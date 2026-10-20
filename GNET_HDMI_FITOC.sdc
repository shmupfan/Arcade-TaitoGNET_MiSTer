# Fitter-only over-constraint of the HDMI clock (docs/hdmi_timing.md, fix F1).
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
if {[info exists ::TimeQuestInfo(nameofexecutable)] && \
    $::TimeQuestInfo(nameofexecutable) eq "quartus_fit"} {
  set_clock_uncertainty -setup -add \
    -from [get_clocks $gnet_hdmi_clk] -to [get_clocks $gnet_hdmi_clk] $gnet_fit_oc
  catch { post_message -type info "GNET_HDMI_FITOC: fitter over-constraint +$gnet_fit_oc ns setup on HDMI to HDMI" }
}
