# Run from src/fpga with quartus_sta -t ../../scripts/report_timing.tcl.
project_open ap_core
create_timing_netlist
read_sdc
update_timing_netlist
report_timing -setup -npaths 20 -detail full_path -file ../../build/worst-setup-paths.rpt
report_timing -hold -npaths 10 -detail full_path -file ../../build/worst-hold-paths.rpt
report_ucp -file ../../build/unconstrained-paths.rpt
delete_timing_netlist
project_close
