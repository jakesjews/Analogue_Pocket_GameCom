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

# Reserve 250 ps beyond the normal same-clock hold relationship on the
# CPU GP-store write-data registers. This steers routing away from the
# short register-to-M10K paths that failed the fast-corner hold check.
set_min_delay 0.250 -from [get_registers {*|u_gp_store|wdata_b_q*}]
