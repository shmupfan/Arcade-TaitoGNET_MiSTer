# R1 CPU50 (docs/r1_cpu_domain_design.md, steps 4 and 5): on a
# GNET_CPU50_B1 fit, every register path between the CPU group clocks
# (pll_cpu: clk_cpu, clk_cpu2x) and the PS1 group and video clocks, both
# directions, plus the worst paths inside the CPU group. A crossing that
# starts anywhere but a cdc_tx_* register (or a quasi-static register that
# GNET_CPU50_B1.sdc cuts) is a design error.
# quartus_sta -t tools/sta/cpu50_xclk.tcl PSX GNET_CPU50_B1
# Output: output_files/cpu50x_<from>_<to>.rpt
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set clk {
  c1    {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  c2    {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
  c3    {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}
  vid   {emu|pll2|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  cpu   {emu|pll_cpu|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
  cpu2x {emu|pll_cpu|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
}
array set C $clk
foreach a {cpu cpu2x} {
  foreach b {c1 c2 c3 vid} {
    report_timing -setup -from_clock [get_clocks $C($a)] -to_clock [get_clocks $C($b)] -npaths 200 -nworst 1 -detail summary -file "output_files/cpu50x_${a}_${b}.rpt"
    report_timing -setup -from_clock [get_clocks $C($b)] -to_clock [get_clocks $C($a)] -npaths 200 -nworst 1 -detail summary -file "output_files/cpu50x_${b}_${a}.rpt"
  }
}
foreach {a b} {cpu cpu cpu cpu2x cpu2x cpu cpu2x cpu2x} {
  report_timing -setup -from_clock [get_clocks $C($a)] -to_clock [get_clocks $C($b)] -npaths 200 -nworst 1 -detail summary -file "output_files/cpu50x_${a}_${b}.rpt"
  report_timing -hold  -from_clock [get_clocks $C($a)] -to_clock [get_clocks $C($b)] -npaths 50 -nworst 1 -detail summary -file "output_files/cpu50x_${a}_${b}_hold.rpt"
}
# the single worst path into clk_2x with its full detail
report_timing -setup -to_clock [get_clocks $C(c2)] -npaths 5 -nworst 1 -detail full_path -file "output_files/cpu50x_worst_c2.rpt"
project_close
