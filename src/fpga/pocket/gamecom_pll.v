// SPDX-License-Identifier: GPL-2.0-or-later
module gamecom_pll(input refclk, output clk_sys, output clk_video,
                   output clk_video_90, output locked);
    altera_pll #(
        .fractional_vco_multiplier("true"),
        .reference_clock_frequency("74.25 MHz"),
        .operation_mode("normal"), .number_of_clocks(3),
        .output_clock_frequency0("20.0 MHz"), .phase_shift0("0 ps"),
        .output_clock_frequency1("30.0 MHz"), .phase_shift1("0 ps"),
        .output_clock_frequency2("30.0 MHz"), .phase_shift2("8333 ps"),
        .pll_type("General"), .pll_subtype("General")
    ) pll (.refclk(refclk), .rst(1'b0), .fbclk(1'b0), .fboutclk(),
           .outclk({clk_video_90, clk_video, clk_sys}), .locked(locked));
endmodule
