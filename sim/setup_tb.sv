// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps
module setup_tb;
    reg clk = 0;
    always #6.734 clk = !clk;
    reg [31:0] addr = 0, wr_data = 0;
    reg wr = 0, rd = 0;
    wire [31:0] rd_data;
    wire little;
    core_top dut (
        .clk_74a(clk), .clk_74b(clk),
        .bridge_addr(addr), .bridge_wr(wr), .bridge_rd(rd),
        .bridge_wr_data(wr_data), .bridge_rd_data(rd_data),
        .bridge_endian_little(little),
        .cont1_key(0), .cont2_key(0), .cont3_key(0), .cont4_key(0),
        .cont1_joy(32'h80808080), .cont2_joy(0), .cont3_joy(0), .cont4_joy(0),
        .cont1_trig(0), .cont2_trig(0), .cont3_trig(0), .cont4_trig(0),
        .cram0_wait(1'b1), .cram1_wait(1'b1), .port_ir_rx(1'b0),
        .vblank(1'b0), .dbg_rx(1'b1), .user2(1'b0), .audio_adc(1'b0)
    );
    function automatic [31:0] swap(input [31:0] value);
        swap = {value[7:0], value[15:8], value[23:16], value[31:24]};
    endfunction
    // APF commands are big endian structures on the little endian bridge.
    task automatic host_write(input [31:0] address, input [31:0] value);
        @(negedge clk); addr = address; wr_data = swap(value); wr = 1;
        @(negedge clk); wr = 0;
        repeat (4) @(negedge clk);
    endtask
    task automatic host_read(input [31:0] address, output [31:0] value);
        @(negedge clk); addr = address; rd = 1;
        repeat (4) @(negedge clk);
        value = swap(rd_data); rd = 0;
    endtask
    task automatic command(input [15:0] cmd, input [15:0] expected);
        reg [31:0] result;
        host_write(32'hf8000000, {16'h434d, cmd});
        for (int poll = 0; poll < 100; poll++) begin
            host_read(32'hf8000000, result);
            if (result[31:16] == 16'h4f4b) begin
                if (result[15:0] != expected)
                    $fatal(1, "APF command %04x returned %04x, expected %04x", cmd, result[15:0], expected);
                return;
            end
        end
        $fatal(1, "APF command %04x timed out", cmd);
    endtask
    task automatic slot(input [15:0] id, input [31:0] size, input [15:0] expected);
        host_write(32'hf8000020, {16'd0, id});
        host_write(32'hf8000024, size);
        command(16'h0082, expected);
        $display("Slot %0d, %0d bytes: result %0d", id, size, expected);
    endtask
    initial begin
        reg [31:0] result;
        #1100000;
        if (!little) $fatal(1, "Unexpected bridge endianness");
        command(16'h0000, 3);
        command(16'h0010, 0);
        // First valid request must not be rejected using power-up slot values.
        slot(0, 2097152, 0);
        slot(1, 262144, 0);
        slot(3, 8192, 0);
        // Memories requests while the machine is in reset must be answered
        // (with an error), or every later host command would stall.
        host_write(32'hf8000020, 32'h1);
        command(16'h00a0, 3);
        command(16'h00a4, 3);
        command(16'h008f, 0);
        host_read(32'hf8001000, result);
        if (result != 32'h636d0140) $fatal(1, "Missing ready-to-run command: %08x", result);
        host_write(32'hf8001000, 32'h6f6b0000);
        command(16'h0011, 0);
        if (!dut.reset_n) $fatal(1, "Host reset exit was not applied");
        // Grayscale LCD display modes need the 444D reply and gray output.
        host_write(32'hf8000020, 32'h2001);
        command(16'h00b8, 0);
        host_read(32'hf8000040, result);
        if (result[15:0] != 16'h444d) $fatal(1, "Grayscale display mode reply %08x", result);
        repeat (4) @(negedge clk);
        if (dut.game.display_palette != 2) $fatal(1, "Grayscale mode did not select gray output");
        host_write(32'hf8000020, 32'h3000);
        command(16'h00b8, 0);
        repeat (4) @(negedge clk);
        if (dut.game.display_palette != 0) $fatal(1, "Color display mode kept gray output");
        // Core Settings values. host_write sends numbers as the Pocket does on
        // the little-endian bridge, byte-swapped, so the value 1 is the raw
        // word 01000000. Each option must act on the number, not on raw bit 0.
        host_write(32'h40000000, 32'h2);
        if (dut.game.palette != 2) $fatal(1, "LCD Palette was not set");
        host_read(32'h40000000, result);
        if (result != 32'h2) $fatal(1, "LCD Palette read back as %08x", result);
        host_write(32'h40000000, 32'h0);
        if (dut.game.palette != 0) $fatal(1, "LCD Palette was not restored");
        host_write(32'h40000004, 32'h1);
        #2000;
        if (!dut.game.config_sync[45] || !dut.game.buttons[11]) $fatal(1, "Power action did not reach the Game.com");
        host_write(32'h40000008, 32'h1);
        #2000;
        if (!dut.game.config_sync[44] || !dut.game.buttons[5]) $fatal(1, "Sound action did not reach the Game.com");
        // A number without bit 0 set must not trigger an action, even though
        // its raw word has bit 0 set.
        host_write(32'h4000000c, 32'h01000000);
        if (dut.game.reset_hold != 0) $fatal(1, "Cold Reset fired on a value of 0x01000000");
        host_write(32'h4000000c, 32'h1);
        if (dut.game.reset_hold == 0) $fatal(1, "Cold Reset did not start");
        wait (dut.game.core_reset);
        wait (!dut.game.core_reset);
        // Reject the CURRENT invalid request, then accept a following valid one.
        slot(99, 8192, 2);
        slot(2, 32768, 0);
        slot(1, 8192, 2);
        slot(1, 262144, 0);
        slot(0, 49152, 2);
        slot(0, 1048576, 0);
        slot(3, 0, 2);
        slot(3, 8192, 0);
        if (!dut.game.cart_loaded[1]) $fatal(1, "Cartridge 2 was not marked loaded");
        host_write(32'h40000010, 32'h1);
        if (dut.game.cart_loaded[1]) $fatal(1, "Eject Cartridge 2 did not eject");
        command(16'h008f, 0);
        command(16'h0010, 0);
        if (dut.reset_n) $fatal(1, "Host reset enter was not applied");
        $display("PASS: actual core_top APF setup, slot acceptance/rejection, ready notification, reset commands, Memories in reset, display modes, Core Settings options");
        $finish;
    end
    initial begin #10000000; $fatal(1, "Setup test timed out"); end
endmodule

// Simulation-only replacements for the PLL and Intel data-table RAM primitives.
// All APF command handling, acknowledgement wiring and validation are real RTL.
module gamecom_pll(input refclk, output reg clk_sys = 0,
    output reg clk_video = 0, output reg clk_video_90 = 0, output reg locked = 0);
    always #25 clk_sys = !clk_sys;
    always #16.667 clk_video = !clk_video;
    initial begin #8.333; forever #16.667 clk_video_90 = !clk_video_90; end
    initial begin #100; locked = 1; end
endmodule

module mf_datatable(input [7:0] address_a, address_b,
    input clock_a, clock_b, input [31:0] data_a, data_b,
    input wren_a, wren_b, output reg [31:0] q_a, q_b);
    reg [31:0] mem [0:255];
    initial for (int i = 0; i < 256; i++) mem[i] = 0;
    always @(posedge clock_a) begin
        if (wren_a) mem[address_a] <= data_a;
        q_a <= wren_a ? data_a : mem[address_a];
    end
    always @(posedge clock_b) begin
        if (wren_b) mem[address_b] <= data_b;
        q_b <= wren_b ? data_b : mem[address_b];
    end
endmodule
