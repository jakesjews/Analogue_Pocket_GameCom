// SPDX-License-Identifier: GPL-2.0-or-later
// Keep APF's boot-time date and time running. The CPU initializes its
// organizer clock from this value after every reset, so a cold reset or a
// cartridge eject picks up the current time rather than the launch time.
// Output layout matches the MiSTer RTC word the CPU expects:
// {valid, 16'd0, YY, MM, DD, hh, mm, ss}, all BCD, 24-hour clock.
module pocket_rtc #(parameter TICKS_PER_SECOND = 20000000) (
    input wire clk,
    // Bridge-clock values from host command 0090; APF sends it once at boot.
    input wire host_valid, input wire [23:0] host_date, input wire [23:0] host_time,
    output wire [64:0] rtc
);
    (* async_reg = "true" *) reg [2:0] valid_sync = 0;
    reg seeded = 0;
    reg [7:0] year = 0, month = 8'h01, day = 8'h01, hour = 0, minute = 0, second = 0;
    reg [24:0] tick = 0;
    assign rtc = {seeded, 16'd0, year, month, day, hour, minute, second};

    function [7:0] bcd_inc(input [7:0] value);
        bcd_inc = value[3:0] == 4'd9 ? {value[7:4] + 4'd1, 4'd0} : value + 8'd1;
    endfunction
    // Two-digit years are 2000-2099, where every fourth year is a leap year.
    function leap_year(input [7:0] y);
        leap_year = y[4] ? (y[3:0] == 4'h2 || y[3:0] == 4'h6)
                         : (y[3:0] == 4'h0 || y[3:0] == 4'h4 || y[3:0] == 4'h8);
    endfunction
    function [7:0] last_day(input [7:0] m, input [7:0] y);
        case (m)
            8'h02: last_day = leap_year(y) ? 8'h29 : 8'h28;
            8'h04, 8'h06, 8'h09, 8'h11: last_day = 8'h30;
            default: last_day = 8'h31;
        endcase
    endfunction

    always @(posedge clk) begin
        valid_sync <= {valid_sync[1:0], host_valid};
        // The host sets date, time and valid together; by the time valid has
        // passed the synchronizer the date and time have long been stable.
        if (!seeded && valid_sync[2]) begin
            seeded <= 1;
            tick <= 0;
            year <= host_date[23:16]; month <= host_date[15:8]; day <= host_date[7:0];
            hour <= host_time[23:16]; minute <= host_time[15:8]; second <= host_time[7:0];
        end else if (tick == TICKS_PER_SECOND - 1) begin
            tick <= 0;
            // A field at or beyond its limit rolls over, so an out-of-range
            // host value cannot count past it.
            if (second < 8'h59) second <= bcd_inc(second);
            else begin
                second <= 0;
                if (minute < 8'h59) minute <= bcd_inc(minute);
                else begin
                    minute <= 0;
                    if (hour < 8'h23) hour <= bcd_inc(hour);
                    else begin
                        hour <= 0;
                        if (day < last_day(month, year)) day <= bcd_inc(day);
                        else begin
                            day <= 8'h01;
                            if (month < 8'h12) month <= bcd_inc(month);
                            else begin
                                month <= 8'h01;
                                year <= year >= 8'h99 ? 8'h00 : bcd_inc(year);
                            end
                        end
                    end
                end
            end
        end else tick <= tick + 1'b1;
    end
endmodule
