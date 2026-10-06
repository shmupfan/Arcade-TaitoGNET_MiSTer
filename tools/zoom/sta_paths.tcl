# Worst setup paths of a fitted revision, for retiming (docs/zoom_board_design.md 6.5).
#   quartus_sta -t tools/zoom/sta_paths.tcl <project> <revision>
# Writes, per clock, <revision>.paths_summary.<clock>.rpt (the 300 worst
# paths, one per endpoint) and <revision>.paths_full.<clock>.rpt (the 30
# worst, every cell and delay) next to the project.
set proj [lindex $quartus(args) 0]
set rev  [lindex $quartus(args) 1]
project_open $proj -revision $rev
create_timing_netlist
read_sdc
update_timing_netlist
foreach_in_collection c [get_clocks] {
    set n [get_clock_info -name $c]
    report_timing -setup -to_clock $n -npaths 300 -nworst 1 -detail summary -file "$rev.paths_summary.$n.rpt"
    report_timing -setup -to_clock $n -npaths 30 -nworst 1 -detail full_path -file "$rev.paths_full.$n.rpt"
}
delete_timing_netlist
project_close
