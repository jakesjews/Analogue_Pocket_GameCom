# APF loads this file after derive_pll_clocks. Bridge data uses explicit
# bundled-data mailboxes; the 20/30 MHz outputs retain their PLL relationship.
set_clock_groups -asynchronous \
    -group [get_clocks bridge_spiclk] \
    -group [get_clocks clk_74b] \
    -group [get_clocks clk_74a] \
    -group [get_clocks {ic|clocks|pll|*}]
derive_clock_uncertainty

# BIOS SRAM: CPU addresses launch on phi1 and are sampled on the next phi0,
# 100 ns later. Bound the FPGA portions to 20 + 20 ns, leaving 60 ns for the
# documented 55 ns SRAM access and board flight time.
set_max_delay 20.0 -from [get_registers {*|u_cpu|a_q*}] -to [get_ports {sram_a[*]}]
set_max_delay 20.0 -from [get_ports {sram_dq[*]}] -to [get_registers {*|u_cpu|*}]

# PSRAM read sampling is nine 74.25 MHz clocks after the start of an access.
# 12 ns outbound + 8 ns inbound + 70 ns PSRAM + 13.468 ns ADV latch
# allowance = 103.468 ns, within the 121.212 ns controller read interval.
set_max_delay 12.0 -from [get_registers {*|rom|memory|*}] -to [get_ports {cram0_a[*] cram0_dq[*] cram0_adv_n cram0_oe_n cram0_we_n cram0_ce0_n cram0_ub_n cram0_lb_n}]
set_max_delay 8.0 -from [get_ports {cram0_dq[*]}] -to [get_registers {*|rom|memory|data_out*}]

# The CPU GP-store registers feed M10K inputs directly, and the RAM clock
# arrives about 0.4 ns after the register clock, so these paths have the
# smallest hold margin in the design. Ask the Fitter for 300 ps more than the
# hold requirement on every register-to-RAM input of the GP store. The guard
# band applies in the Fitter only: sign-off timing analysis checks the real
# hold requirement. As an SDC requirement it only passed when the router
# happened to overshoot (it failed first fits of 0.1.3, 0.2.0 and 0.2.1).
if {$::quartus(nameofexecutable) eq "quartus_fit"} {
    set_min_delay 0.300 -from [get_registers {*|u_gp_store|wdata_a_q* *|u_gp_store|wdata_b_q* *|u_gp_store|wren_a_q* *|u_gp_store|wren_b_q* *|u_gp_store|addr_a_q* *|u_gp_store|addr_b_q*}]
}

# Bundled-data mailboxes across the asynchronous groups above. Each data bus
# is held stable while its toggle passes a two-flop synchronizer, which adds
# at least one destination clock. The clock groups cut path analysis for these
# buses, including set_max_skew, so bound the routing of every net leaving the
# data registers instead; set_net_delay is checked regardless of clock groups.
# The limits leave most of the destination clock for the receiving
# multiplexer and setup time.
# ROM request address, clk_sys to clk_74a (13.468 ns).
set_net_delay -max 5.0 -from [get_registers {*|game|rom|request_addr[*]}]
# ROM read data, clk_74a to clk_sys (50 ns).
set_net_delay -max 20.0 -from [get_registers {*|game|rom|response[*]}]
# Audio sample, clk_sys to clk_74a.
set_net_delay -max 5.0 -from [get_registers {*|game|sound|held[*]}]
# Boot-time date and time, clk_74a to clk_sys; seeded after valid is synchronized.
set_net_delay -max 20.0 -from [get_registers {*|icb|rtc_date_bcd[*] *|icb|rtc_time_bcd[*]}]
