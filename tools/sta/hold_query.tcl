# Worst hold paths per clock on an existing fit (full path detail for the worst).
# quartus_sta -t hold_query.tcl PSX <revision>
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist -model fast
read_sdc
update_timing_netlist
report_timing -hold -npaths 20 -nworst 1 -less_than_slack 0.2 -detail summary -file "output_files/hold_fast_summary.rpt"
report_timing -hold -npaths 1 -detail full_path -file "output_files/hold_fast_worst.rpt"
delete_timing_netlist
create_timing_netlist -model slow
read_sdc
update_timing_netlist
report_timing -hold -npaths 20 -nworst 1 -less_than_slack 0.2 -detail summary -file "output_files/hold_slow_summary.rpt"
report_timing -hold -npaths 1 -detail full_path -file "output_files/hold_slow_worst.rpt"
project_close
