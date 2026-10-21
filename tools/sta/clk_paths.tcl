# Setup paths into chosen clocks of a fitted database, in both slow
# operating conditions (the flow's own STA reports only Slow 1100mV 100C,
# TIMEQUEST_MULTICORNER_ANALYSIS is OFF in the release QSF). The same reports
# as tools/sta/hdmi_paths.tcl, for any of the core clocks, plus clock skew,
# logic levels and launch clock per path family, so a failing family can be
# told apart as a crossing (launch clock differs), a long route (high data
# delay, few levels) or a deep path (many levels). docs/area_timing.md.
#   quartus_sta -t tools/sta/clk_paths.tcl PSX <revision> <prefix> <tag> [<tag> ...]
# <tag>: 2x   emu pll general[1], clk_2x, 67.7376 MHz (GPU, SPU, DDR3 side)
#        1x   emu pll general[0], clk_1x, 33.8688 MHz
#        cpu  pll_cpu general[0], clk_cpu, 50 MHz
#        cpu2x pll_cpu general[1], clk_cpu2x, 100 MHz
#        vid  emu pll2 general[0], clk_vid, 53.693175 MHz
#        hdmi pll_hdmi counter[0], 148.5 MHz in the SDC
# Output in output_files/, <oc> = corner tag:
#   <prefix>_corners.rpt               worst slack, TNS, failing endpoints, per clock and corner
#   <prefix>_<tag>_<oc>_summary.rpt    200 worst endpoints, one path each
#   <prefix>_<tag>_<oc>_full.rpt       30 worst endpoints, full path (cells, routing, clock skew)
#   <prefix>_<tag>_<oc>_families.rpt   endpoints with slack < 0.1 ns grouped by from-register
#                                      family -> to-register family (bus and RAM block indices
#                                      folded), with count, worst slack, data delay, clock skew,
#                                      logic levels and launch clock of the worst path
#   <prefix>_<tag>_<oc>_by_source.rpt  worst path from each launch clock
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
set pfx      [lindex $quartus(args) 2]
set tags     [lrange $quartus(args) 3 end]
if {$pfx eq "" || [llength $tags] == 0} {
  post_message -type error "usage: quartus_sta -t tools/sta/clk_paths.tcl PSX <revision> <prefix> <tag> \[<tag> ...\]"
  qexit -error
}
set margin 0.1

array set clkname {
  2x    {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
  1x    {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  cpu   {emu|pll_cpu|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  cpu2x {emu|pll_cpu|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
  vid   {emu|pll2|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  hdmi  {pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}
}
foreach t $tags {
  if {![info exists clkname($t)]} {
    post_message -type error "clk_paths.tcl: unknown clock tag $t (2x 1x cpu cpu2x vid hdmi)"
    qexit -error
  }
}

# register name with bus and RAM block indices folded, so one family is one key
proc family {name} {
  regsub -all {\[[0-9]+\]} $name {[*]} n
  regsub -all {(ram_block[0-9]+a)[0-9]+} $n {\1*} n
  regsub -all {(lutrama)[0-9]+} $n {\1*} n
  regsub -all {~_Duplicate_[0-9]+} $n {~_Duplicate_*} n
  return $n
}

project_open $project -revision $revision
create_timing_netlist
read_sdc
update_timing_netlist

set fc [open "output_files/${pfx}_corners.rpt" w]
puts $fc "setup, project $project revision $revision, clocks $tags"
foreach_in_collection oc [get_available_operating_conditions] {
  set ocn [get_operating_conditions_info $oc -display_name]
  if {![string match -nocase "*slow*" $ocn]} { continue }
  set_operating_conditions $oc
  update_timing_netlist
  set tag [regsub -all {[^A-Za-z0-9]+} $ocn {_}]

  foreach cn $tags {
    set clk $clkname($cn)
    if {[get_collection_size [get_clocks -nowarn $clk]] == 0} {
      puts $fc [format "%-6s %-28s clock not found: %s" $cn $ocn $clk]
      continue
    }
    set base "output_files/${pfx}_${cn}_${tag}"
    report_timing -setup -to_clock $clk -npaths 200 -nworst 1 \
      -detail summary -file "${base}_summary.rpt"
    report_timing -setup -to_clock $clk -npaths 30 -nworst 1 \
      -detail full_path -file "${base}_full.rpt"

    array unset fam_n
    array unset fam_w
    array unset fam_x
    set worst ""
    set tns 0.0
    set nfail 0
    foreach_in_collection p [get_timing_paths -setup -to_clock $clk -less_than_slack $margin -npaths 100000 -nworst 1] {
      set sl [get_path_info $p -slack]
      if {$worst eq "" || $sl < $worst} { set worst $sl }
      if {$sl < 0.0} {
        set tns [expr {$tns + $sl}]
        incr nfail
      }
      set fn [get_node_info -name [get_path_info $p -from]]
      set tn [get_node_info -name [get_path_info $p -to]]
      set lc "?"
      catch { set lc [get_clock_info -name [get_path_info $p -from_clock]] }
      set dd "?"
      catch { set dd [format "%.3f" [get_path_info $p -data_delay]] }
      set sk "?"
      catch { set sk [format "%.3f" [get_path_info $p -clock_skew]] }
      set nl "?"
      catch { set nl [get_path_info $p -num_logic_levels] }
      set key "[family $fn]  ->  [family $tn]"
      if {$lc ne $clk} { append key "  (launch $lc)" }
      if {[info exists fam_n($key)]} {
        incr fam_n($key)
        if {$sl < $fam_w($key)} { set fam_w($key) $sl; set fam_x($key) [list $dd $sk $nl] }
      } else {
        set fam_n($key) 1
        set fam_w($key) $sl
        set fam_x($key) [list $dd $sk $nl]
      }
    }
    if {$worst eq ""} {
      foreach_in_collection p [get_timing_paths -setup -to_clock $clk -npaths 1] {
        set worst [get_path_info $p -slack]
      }
    }
    puts $fc [format "%-6s %-28s worst %8.3f  TNS %8.3f  failing endpoints %d" $cn $ocn $worst $tns $nfail]

    set ff [open "${base}_families.rpt" w]
    puts $ff "setup into $clk ($cn), $ocn, endpoints with slack < $margin ns (one worst path per endpoint)"
    puts $ff "   slack  count  data_dly  clk_skew  levels  from family -> to family (launch clock when not $cn)"
    set rows {}
    foreach key [array names fam_n] {
      lappend rows [list $fam_w($key) $fam_n($key) $fam_x($key) $key]
    }
    foreach r [lsort -real -index 0 $rows] {
      lassign [lindex $r 2] dd sk nl
      puts $ff [format "%8.3f  %5d  %8s  %8s  %6s  %s" [lindex $r 0] [lindex $r 1] $dd $sk $nl [lindex $r 3]]
    }
    close $ff

    set fs [open "${base}_by_source.rpt" w]
    foreach_in_collection c [get_clocks] {
      set name [get_clock_info -name $c]
      foreach_in_collection p [get_timing_paths -setup -from_clock $name -to_clock $clk -npaths 1] {
        puts $fs [format "%8.3f  %s  ->  %s  (from clock %s)" [get_path_info $p -slack] \
          [get_node_info -name [get_path_info $p -from]] [get_node_info -name [get_path_info $p -to]] $name]
      }
    }
    close $fs
  }
}
close $fc
project_close
