project_open ap_core
create_timing_netlist
set f [open ../../build/register-array-audit.txt w]
foreach pattern {
    *|u_cpu|iram_lo_shadow_q*
    *|u_cpu|sg0w_q*
    *|u_cpu|sg1w_q*
    *|u_gp_store|shadow_q*
    *|u_cpu|gp_shadow_q*
    *|u_cpu|reg_bank_q*
    *|u_cpu|sfr_shadow_q*
    *|u_cpu|lowmem_q*
    *|u_cheat_engine|*
} {
    puts $f "$pattern [get_collection_size [get_registers -nowarn $pattern]]"
}
close $f
delete_timing_netlist
project_close
