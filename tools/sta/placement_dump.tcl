# Placement of every cell of a fitted database, for tools/floorplan.py.
#   quartus_sta -t tools/sta/placement_dump.tcl PSX <revision>
# Writes output_files/placement.tsv: location, WYSIWYG type and full
# hierarchical name of each cell, one per line, tab separated. Read-only on
# the database; no fit, no timing analysis.
set project  [lindex $quartus(args) 0]
set revision [lindex $quartus(args) 1]

project_open $project -revision $revision
create_timing_netlist

set out [open output_files/placement.tsv w]
set n 0
set bad 0
foreach_in_collection c [get_cells -hierarchical *] {
  if {[catch {set loc [get_cell_info -location $c]}]} {
    set loc ?
    incr bad
  }
  puts $out "$loc\t[get_cell_info -wysiwyg_type $c]\t[get_cell_info -name $c]"
  incr n
}
close $out
post_message "placement_dump: $n cells, $bad without a location"

delete_timing_netlist
project_close
