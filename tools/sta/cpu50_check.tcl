# After a GNET_F0_CPU50 compile: count CPU-side endpoints still failing the
# 20 ns max-delay (slack < 0), worst path per endpoint.
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]
project_open $project -revision $revision
create_timing_netlist -model slow
read_sdc
update_timing_netlist
set cpu_regs [get_registers -nowarn {*psx_top:ipsx_top|cpu:icpu|*}]
set dst [get_registers -nowarn {*psx_top:ipsx_top|cpu:icpu|* *psx_top:ipsx_top|memorymux:imemorymux|*}]
report_timing -setup -from $cpu_regs -to $dst -less_than_slack 0.0 -npaths 20000 -nworst 1 \
  -detail summary -file "output_files/cpu50_check.rpt"
report_timing -setup -from $cpu_regs -to $dst -npaths 1 -detail full_path -file "output_files/cpu50_worst.rpt"
project_close
