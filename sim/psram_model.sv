`timescale 1ns/1ps
// Pin-level asynchronous CellularRAM model. Address is latched by ADV#;
// DQ turnaround, byte enables and the 70 ns access time are exercised.
module psram_model(input clk, input [21:16] a, inout [15:0] dq,
    input adv_n, input ce0_n, input ce1_n, input oe_n, input we_n,
    input ub_n, input lb_n);
    reg [15:0] mem [0:4194303];
    reg [21:0] address;
    reg [15:0] write_data;
    reg write_low, write_high;
    wire [15:0] read_data;
    assign #70 read_data = mem[address];
    assign dq = !ce0_n && !oe_n && we_n && adv_n ? read_data : 16'hzzzz;
    always @(posedge adv_n) if (!ce0_n) address = {a, dq};
    always @(negedge clk) begin
        if (!ce0_n && !ce1_n) $fatal(1, "Both PSRAM dies selected");
        if (!ce0_n && !we_n && adv_n) begin
            write_data = dq; write_low = !lb_n; write_high = !ub_n;
        end
    end
    always @(posedge we_n) begin
        if (write_low) mem[address][7:0] = write_data[7:0];
        if (write_high) mem[address][15:8] = write_data[15:8];
        write_low = 0; write_high = 0;
    end
endmodule
