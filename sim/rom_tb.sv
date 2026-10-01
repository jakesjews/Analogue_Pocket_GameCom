`timescale 1ns/1ps
module rom_tb;
    reg clk_bridge=0, clk_sys=0;
    always #6.734 clk_bridge=~clk_bridge;
    always #25 clk_sys=~clk_sys;
    reg reset=1, load_wr=0, invalidate=1, cpu_rd=0;
    reg [22:0] load_addr=0, cpu_addr=0;
    reg [31:0] load_data=0;
    wire load_idle, overflow, cpu_ready;
    wire [7:0] cpu_data;
    wire [21:16] a; wire [15:0] dq;
    wire cclk, adv, cre, ce0,ce1,oe,we,ub,lb;
    pocket_rom dut(.*,.cram_a(a),.cram_dq(dq),.cram_wait(1'b0),
       .cram_clk(cclk),.cram_adv_n(adv),.cram_cre(cre),.cram_ce0_n(ce0),
       .cram_ce1_n(ce1),.cram_oe_n(oe),.cram_we_n(we),.cram_ub_n(ub),.cram_lb_n(lb));
    psram_model ram(clk_bridge,a,dq,adv,ce0,ce1,oe,we,ub,lb);
    task write_word(input [22:0] addr,input [31:0] data);
        @(negedge clk_bridge); load_addr=addr; load_data=data; load_wr=1;
        @(negedge clk_bridge); load_wr=0;
    endtask
    integer read_count=0,wait_cycles=0;
    task read_byte(input [22:0] addr,input [7:0] expected);
        integer timeout;
        @(negedge clk_sys); cpu_addr=addr;cpu_rd=1;
        #1;timeout=0;
        while (!cpu_ready && timeout<100) begin @(negedge clk_sys);#1;timeout++; end
        if(!cpu_ready || cpu_data!==expected)
            $fatal(1,"ROM addr=%h expected=%h got=%h ready=%b",addr,expected,cpu_data,cpu_ready);
        read_count++;wait_cycles+=timeout;
        @(negedge clk_sys);cpu_rd=0;
    endtask
    function [7:0] pattern_byte(input integer addr);
        pattern_byte=((32'h80402000+addr/4)>>((addr%4)*8))&255;
    endfunction
    // Byte reads in CPU bus rhythm: one read per 200 ns bus cycle.
    task stream(input integer first,input integer count,input integer gap);
        for(integer a=first;a<first+count;a++)begin
            read_byte(a,pattern_byte(a));repeat(gap)@(negedge clk_sys);
        end
    endtask
    reg [15:0] lfsr=16'hace1;
    initial begin
        #300;reset=0;
        // Burst deliberately exceeds the service rate to exercise FIFO wrap/drain.
        for(integer n=0;n<900;n++) write_word(n*4,32'h80402000+n);
        wait(load_idle);#100;
        if(overflow)$fatal(1,"loader overflow");
        invalidate=0;
        for(integer n=0;n<900;n++) begin
            read_byte(n*4,(32'h80402000+n)&255);
            read_byte(n*4+1,((32'h80402000+n)>>8)&255);
            read_byte(n*4+2,8'h40);read_byte(n*4+3,8'h80);
        end
        // Prefetch coverage: random addresses and gaps (jumps away from the
        // prefetched halfword, including while a prefetch is in flight), then
        // straight-line streams at and below CPU bus speed.
        for(integer n=0;n<3000;n++)begin
            lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            read_byte(lfsr%3600,pattern_byte(lfsr%3600));
            repeat(lfsr[3:0]%10)@(negedge clk_sys);
        end
        read_count=0;wait_cycles=0;
        stream(1001,600,2);
        $display("Sequential stream: %0d reads, %0d wait cycles",read_count,wait_cycles);
        if(wait_cycles>read_count/8)$fatal(1,"Prefetch is not keeping up with sequential reads");
        stream(2003,300,0);
        invalidate=1;
        // This second burst crosses the 1024-entry circular pointer boundary.
        for(integer n=900;n<1200;n++) write_word(n*4,32'h80402000+n);
        wait(load_idle);#100;invalidate=0;
        for(integer n=900;n<1200;n++)begin
            read_byte(n*4,(32'h80402000+n)&255);
            read_byte(n*4+3,8'h80);
        end
        invalidate=1;
        write_word(23'h200000,32'haabbccdd);
        write_word(0,32'h01020304);
        wait(load_idle);#300;invalidate=0;
        read_byte(0,8'h04);read_byte(1,8'h03);
        read_byte(23'h200000,8'hdd);read_byte(23'h200003,8'haa);
        $display("PASS ROM: burst FIFO, byte order, both slots, cache invalidation, prefetch");$finish;
    end
    initial begin #10000000;$fatal(1,"ROM test timeout");end
endmodule
