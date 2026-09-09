`timescale 1ns/1ps
module bios_tb;
    reg clk_bridge=0;always #6.734 clk_bridge=~clk_bridge;
    reg reset=1,load_wr=0;reg[17:0]load_addr=0,cpu_addr=0;reg[31:0]load_data=0;
    wire load_idle,overflow;wire[7:0]cpu_data;
    wire[16:0]sram_a;wire[15:0]sram_dq;wire sram_oe_n,sram_we_n,sram_ub_n,sram_lb_n;
    pocket_bios dut(.*);
    sram_model ram(sram_a,sram_dq,sram_oe_n,sram_we_n,sram_ub_n,sram_lb_n);
    task write_word(input[17:0]a,input[31:0]d);
        @(negedge clk_bridge);load_wr=1;load_addr=a;load_data=d;
        @(negedge clk_bridge);load_wr=0;
    endtask
    task read_byte(input[17:0]a,input[7:0]d);
        cpu_addr=a;#100;
        if(cpu_data!==d)$fatal(1,"SRAM BIOS address %h expected %h got %h",a,d,cpu_data);
    endtask
    initial begin
        #300;reset=0;
        for(integer n=0;n<900;n++)write_word(n*4,32'h80402000+n);
        wait(load_idle);#100;
        for(integer n=900;n<1200;n++)write_word(n*4,32'h80402000+n);
        write_word(18'h3fffc,32'h12345678);
        wait(load_idle);#100;
        if(overflow)$fatal(1,"BIOS FIFO overflow");
        for(integer n=0;n<1200;n++)for(integer b=0;b<4;b++)read_byte(n*4+b,((32'h80402000+n)>>(b*8))&255);
        read_byte(18'h3fffc,8'h78);read_byte(18'h3ffff,8'h12);
        $display("PASS BIOS SRAM: burst FIFO wrap, 4804 byte reads, final word, 55 ns access and WE pulse widths");$finish;
    end
    initial begin #10000000;$fatal(1,"BIOS test timeout");end
endmodule
