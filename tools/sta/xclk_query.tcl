# R1 measurement 4 (docs/r1_cpu_domain_design.md): on an existing fit, the
# register paths that cross between clk_1x, clk_2x and clk_3x, with their data
# delays, to see what a CPU clock of 3/2 clk_1x (50.8032 MHz) would face.
# quartus_sta -t xclk_query.tcl PSX <revision>
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set c1 {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set c2 {emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk}
set c3 {emu|pll|pll_inst|altera_pll_i|general[2].gpll~PLL_OUTPUT_COUNTER|divclk}
foreach {a b n} [list $c1 $c2 1to2 $c2 $c1 2to1 $c1 $c3 1to3 $c3 $c1 3to1 $c2 $c3 2to3 $c3 $c2 3to2] {
   report_timing -setup -from_clock [get_clocks $a] -to_clock [get_clocks $b] -npaths 200 -nworst 1 -detail summary -file "output_files/xclk_$n.rpt"
}
project_close
