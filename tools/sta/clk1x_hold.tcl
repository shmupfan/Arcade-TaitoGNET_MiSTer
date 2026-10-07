# Worst hold paths into clk_1x (emu PLL general[0], 33.8688 MHz) after a full
# compile, in every operating condition (corner) the device model has: the
# 100 worst endpoints with hold slack below 0.1 ns (summary), the 10 worst in
# full detail (clock skew and data arrival per element), and the worst hold
# path from each source clock, so a crossing into clk_1x is told apart from a
# clk_1x or clk_2x path with skew.
#   quartus_sta -t tools/sta/clk1x_hold.tcl PSX <revision> [clock [prefix]]
# [clock] defaults to clk_1x; pass another clock name to check that one.
# [prefix] (default hold) names the reports, so two clocks can be checked
# into the same output_files (for example hold1x and hold2x).
# Output, per corner <oc>: output_files/<prefix>_<oc>_summary.rpt,
#   <prefix>_<oc>_full.rpt, <prefix>_<oc>_by_source.rpt; and
#   output_files/<prefix>_corners.rpt (worst hold slack and TNS per corner).
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
set clk {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
if {[llength $quartus(args)] > 2} {
  set clk [lindex $quartus(args) 2]
}
set pfx hold
if {[llength $quartus(args)] > 3} {
  set pfx [lindex $quartus(args) 3]
}
project_open $project -revision $revision
create_timing_netlist
read_sdc
update_timing_netlist

set fc [open "output_files/${pfx}_corners.rpt" w]
puts $fc "hold into $clk"
foreach_in_collection oc [get_available_operating_conditions] {
  set_operating_conditions $oc
  update_timing_netlist
  set ocn [get_operating_conditions_info $oc -display_name]
  set tag [regsub -all {[^A-Za-z0-9]+} $ocn {_}]

  report_timing -hold -to_clock $clk -less_than_slack 0.1 -npaths 100 -nworst 1 \
    -detail summary -file "output_files/${pfx}_${tag}_summary.rpt"
  report_timing -hold -to_clock $clk -npaths 10 -nworst 1 \
    -detail full_path -file "output_files/${pfx}_${tag}_full.rpt"

  set f [open "output_files/${pfx}_${tag}_by_source.rpt" w]
  foreach_in_collection c [get_clocks] {
    set name [get_clock_info -name $c]
    set paths [get_timing_paths -hold -from_clock $name -to_clock $clk -npaths 1]
    foreach_in_collection p $paths {
      puts $f [format "%8.3f  %s  ->  %s  (from clock %s)" [get_path_info $p -slack] \
        [get_node_info -name [get_path_info $p -from]] [get_node_info -name [get_path_info $p -to]] $name]
    }
  }
  close $f

  # worst slack, and TNS over the failing endpoints (one path per endpoint)
  set worst ""
  set tns 0.0
  set n 0
  foreach_in_collection p [get_timing_paths -hold -to_clock $clk -less_than_slack 0.0 -npaths 100000 -nworst 1] {
    set sl [get_path_info $p -slack]
    if {$worst eq "" || $sl < $worst} { set worst $sl }
    set tns [expr {$tns + $sl}]
    incr n
  }
  if {$worst eq ""} {
    foreach_in_collection p [get_timing_paths -hold -to_clock $clk -npaths 1] { set worst [get_path_info $p -slack] }
  }
  puts $fc [format "%-40s worst %8.3f  TNS %8.3f  failing endpoints %d" $ocn $worst $tns $n]
}
close $fc
project_close
