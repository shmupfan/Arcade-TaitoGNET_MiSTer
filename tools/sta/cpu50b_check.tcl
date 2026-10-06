# After a GNET_F0_CPU50B compile: endpoints failing the experiment's max delays
# (worst path per endpoint), grouped later by tools/sta/summarise.py.
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set side [get_registers -nowarn {*psx_top:ipsx_top|cpu:icpu|* *psx_top:ipsx_top|dma:idma|* *psx_top:ipsx_top|memorymux:imemorymux|* *psx_top:ipsx_top|memctrl:imemctrl|*}]
set gte  [get_registers -nowarn {*psx_top:ipsx_top|gte:igte|*}]
report_timing -setup -from $side -to $side -less_than_slack 0.0 -npaths 20000 -nworst 1 -detail summary -file "output_files/cpu50b_side.rpt"
report_timing -setup -to $gte -less_than_slack 0.0 -npaths 20000 -nworst 1 -detail summary -file "output_files/cpu50b_gte_in.rpt"
report_timing -setup -from $gte -to $side -less_than_slack 0.0 -npaths 20000 -nworst 1 -detail summary -file "output_files/cpu50b_gte_out.rpt"
report_timing -setup -to $gte -npaths 1 -detail full_path -file "output_files/cpu50b_gte_worst.rpt"
project_close
