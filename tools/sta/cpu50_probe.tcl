# CPU-rate timing probe (R1): which register-to-register paths inside the
# CPU-side blocks would fail if the CPU domain ran at 50 MHz (20 ns) or
# 67.7376 MHz (14.76 ns) instead of clk_1x (33.8688 MHz, 29.524 ns).
# No constraint is changed: a clk_1x path with setup slack s has a data path
# of about (29.524 - s) ns, so it fits 20 ns if s >= 9.524 and 14.76 ns if
# s >= 14.762 (clock skew and uncertainty kept as in the real constraint).
# Run in the build directory after a full compile:
#   quartus_sta -t cpu50_probe.tcl <project> <revision>
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist -model slow
read_sdc
update_timing_netlist

set clk1x {emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}
set blocks {cpu:icpu gte:igte dma:idma memctrl:imemctrl memorymux:imemorymux}
set regs [get_registers -nowarn {*psx_top:ipsx_top|cpu:icpu|* *psx_top:ipsx_top|gte:igte|* *psx_top:ipsx_top|dma:idma|* *psx_top:ipsx_top|memctrl:imemctrl|* *psx_top:ipsx_top|memorymux:imemorymux|*}]
post_message "registers in CPU-side blocks: [get_collection_size $regs]"

foreach {tag limit} {f50 9.524 f67 14.762} {
  report_timing -setup -from_clock $clk1x -to_clock $clk1x -from $regs -to $regs \
    -less_than_slack $limit -npaths 20000 -nworst 1 -detail summary -panel_name "probe_$tag" \
    -file "output_files/cpu_probe_$tag.rpt"
}
# also paths leaving/entering the CPU side (bus to GPU/SPU/DMA) for the bridge design
report_timing -setup -from_clock $clk1x -to_clock $clk1x -from $regs \
  -less_than_slack 9.524 -npaths 20000 -nworst 1 -detail summary -file "output_files/cpu_probe_out_f50.rpt"
report_timing -setup -from_clock $clk1x -to_clock $clk1x -to $regs \
  -less_than_slack 9.524 -npaths 20000 -nworst 1 -detail summary -file "output_files/cpu_probe_in_f50.rpt"
project_close
