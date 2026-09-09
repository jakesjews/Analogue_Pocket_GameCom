project_open ap_core
create_timing_netlist
read_sdc
set_operating_conditions -model slow -temperature 85 -voltage 1100
update_timing_netlist
report_timing -setup -npaths 10 -detail full_path -file ../../build/dma-fix-first-fit/setup-paths.rpt
set_operating_conditions -model fast -temperature 0 -voltage 1100
update_timing_netlist
report_timing -hold -npaths 20 -detail full_path -file ../../build/dma-fix-first-fit/hold-paths.rpt
delete_timing_netlist
project_close
