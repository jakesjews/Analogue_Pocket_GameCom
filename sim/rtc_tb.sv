// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps
module rtc_tb;
    reg clk = 0;
    always #25 clk = !clk;
    reg valid = 0;
    wire [64:0] leap, year_end, century, ordinary;
    // Four clocks started one or two seconds before a rollover of interest.
    pocket_rtc #(.TICKS_PER_SECOND(10)) a (.clk(clk), .host_valid(valid),
        .host_date(24'h280228), .host_time(24'h235959), .rtc(leap));
    pocket_rtc #(.TICKS_PER_SECOND(10)) b (.clk(clk), .host_valid(valid),
        .host_date(24'h271231), .host_time(24'h235959), .rtc(year_end));
    pocket_rtc #(.TICKS_PER_SECOND(10)) c (.clk(clk), .host_valid(valid),
        .host_date(24'h991231), .host_time(24'h235959), .rtc(century));
    pocket_rtc #(.TICKS_PER_SECOND(10)) d (.clk(clk), .host_valid(valid),
        .host_date(24'h270228), .host_time(24'h235958), .rtc(ordinary));
    task check_time(input [64:0] rtc, input [47:0] value, input string label);
        if (rtc !== {1'b1, 16'd0, value})
            $fatal(1, "%s: got %h expected %h", label, rtc[47:0], value);
    endtask
    initial begin
        repeat (5) @(negedge clk);
        if (leap[64]) $fatal(1, "Clock valid before the host time arrived");
        valid = 1;
        repeat (5) @(negedge clk);
        check_time(leap, 48'h280228_235959, "seed");
        repeat (10) @(negedge clk);
        check_time(leap, 48'h280229_000000, "leap day");
        check_time(year_end, 48'h280101_000000, "new year");
        check_time(century, 48'h000101_000000, "century");
        check_time(ordinary, 48'h270228_235959, "one second");
        repeat (10) @(negedge clk);
        check_time(ordinary, 48'h270301_000000, "non-leap February");
        $display("PASS RTC: seeding, seconds through years, leap day, century wrap");
        $finish;
    end
endmodule
