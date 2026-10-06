# After a CPU50 compile (CPU_CLK_SPLIT = 1): the worst setup paths into the
# CPU PLL's 100 MHz clock (pll_cpu general[1], clk_cpu2x: sdram.sv's clk at
# CLK_FAST_RATIO 2, the CPU group's clk2x), in every operating condition.
#   quartus_sta -t tools/sta/cpu2x_worst.tcl <project> <revision>
# Output in output_files/: cpu2x_worst_<cond>.rpt (the 40 worst endpoints,
# one path each, summary) and cpu2x_worst_full_<cond>.rpt (the 3 worst with
# the full path), cpu2x_by_source.rpt (the worst path per launch clock).
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist
read_sdc
update_timing_netlist
set clk2x [get_clocks -nowarn {*pll_cpu*general[1]*divclk}]
set fs [open "output_files/cpu2x_by_source.rpt" w]
foreach_in_collection cond [get_available_operating_conditions] {
   set_operating_conditions $cond
   update_timing_netlist
   set c [get_operating_conditions_info $cond -display_name]
   regsub -all {[^A-Za-z0-9]+} $c "_" cn
   report_timing -setup -to_clock $clk2x -npaths 40 -nworst 1 -detail summary \
     -file "output_files/cpu2x_worst_$cn.rpt"
   report_timing -setup -to_clock $clk2x -npaths 3 -nworst 1 -detail full_path \
     -file "output_files/cpu2x_worst_full_$cn.rpt"
   puts $fs "== $c"
   foreach_in_collection src [all_clocks] {
      set p [get_timing_paths -setup -from_clock $src -to_clock $clk2x -npaths 1]
      foreach_in_collection q $p {
         puts $fs [format "  %8.3f  %s  ->  %s  (from %s)" [get_path_info $q -slack] \
           [get_node_info -name [get_path_info $q -from]] [get_node_info -name [get_path_info $q -to]] \
           [get_clock_info -name $src]]
      }
   }
}
close $fs
project_close
