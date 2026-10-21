# Post-synthesis (post-map) timing of a revision, no fit needed: clock
# transfer path counts and the deepest setup paths per clock, from the
# synthesis netlist with estimated delays. Synthesis is deterministic (the
# same source gives the same map report on every seed), so this compares
# netlists without seed noise. docs/area_timing.md section 4.
#   quartus_sta -t tools/sta/postmap_paths.tcl PSX <revision> [prefix]
# Output in output_files/ ([prefix] defaults to postmap):
#   <prefix>_transfers.rpt         report_clock_transfers (setup), the path count per clock pair
#   <prefix>_<tag>_summary.rpt     100 worst endpoints into the clock, one path each
#   <prefix>_<tag>_families.rpt    the 2000 worst endpoints grouped into from-family -> to-family,
#                                  with count, worst slack, data delay and logic levels
#   <prefix>_worst.rpt             worst estimated setup slack and deepest logic level per clock
# Absolute post-map slacks are estimates and do not predict the fitted slack;
# compare them only between netlists of the same revision.
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
set pfx postmap
if {[llength $quartus(args)] > 2} {
  set pfx [lindex $quartus(args) 2]
}

set clocks [list \
  2x    {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} \
  1x    {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} \
  cpu   {emu|pll_cpu|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk} \
  cpu2x {emu|pll_cpu|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk} \
  hdmi  {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk} ]

proc family {name} {
  regsub -all {\[[0-9]+\]} $name {[*]} n
  regsub -all {(ram_block[0-9]+a)[0-9]+} $n {\1*} n
  regsub -all {(lutrama)[0-9]+} $n {\1*} n
  regsub -all {~_Duplicate_[0-9]+} $n {~_Duplicate_*} n
  return $n
}

project_open $project -revision $revision
create_timing_netlist -post_map
read_sdc
update_timing_netlist

report_clock_transfers -setup -file "output_files/${pfx}_transfers.rpt"

set fw [open "output_files/${pfx}_worst.rpt" w]
puts $fw "post-map setup, project $project revision $revision (estimated delays)"
foreach {cn clk} $clocks {
  if {[get_collection_size [get_clocks -nowarn $clk]] == 0} {
    puts $fw [format "%-6s clock not found: %s" $cn $clk]
    continue
  }
  report_timing -setup -to_clock $clk -npaths 100 -nworst 1 \
    -detail summary -file "output_files/${pfx}_${cn}_summary.rpt"

  array unset fam_n
  array unset fam_w
  array unset fam_x
  set worst ""
  set maxlev 0
  foreach_in_collection p [get_timing_paths -setup -to_clock $clk -npaths 2000 -nworst 1] {
    set sl [get_path_info $p -slack]
    if {$worst eq "" || $sl < $worst} { set worst $sl }
    set fn [get_node_info -name [get_path_info $p -from]]
    set tn [get_node_info -name [get_path_info $p -to]]
    set lc "?"
    catch { set lc [get_clock_info -name [get_path_info $p -from_clock]] }
    set dd "?"
    catch { set dd [format "%.3f" [get_path_info $p -data_delay]] }
    set nl "?"
    catch { set nl [get_path_info $p -num_logic_levels] }
    if {[string is integer -strict $nl] && $nl > $maxlev} { set maxlev $nl }
    set key "[family $fn]  ->  [family $tn]"
    if {$lc ne $clk} { append key "  (launch $lc)" }
    if {[info exists fam_n($key)]} {
      incr fam_n($key)
      if {$sl < $fam_w($key)} { set fam_w($key) $sl; set fam_x($key) [list $dd $nl] }
    } else {
      set fam_n($key) 1
      set fam_w($key) $sl
      set fam_x($key) [list $dd $nl]
    }
  }
  puts $fw [format "%-6s worst %8.3f  deepest path in the 2000 worst endpoints: %s levels" $cn $worst $maxlev]

  set ff [open "output_files/${pfx}_${cn}_families.rpt" w]
  puts $ff "post-map setup into $clk ($cn), 2000 worst endpoints (one worst path each)"
  puts $ff "   slack  count  data_dly  levels  from family -> to family (launch clock when not $cn)"
  set rows {}
  foreach key [array names fam_n] {
    lappend rows [list $fam_w($key) $fam_n($key) $fam_x($key) $key]
  }
  foreach r [lsort -real -index 0 $rows] {
    lassign [lindex $r 2] dd nl
    puts $ff [format "%8.3f  %5d  %8s  %6s  %s" [lindex $r 0] [lindex $r 1] $dd $nl [lindex $r 3]]
  }
  close $ff
}
close $fw
project_close
