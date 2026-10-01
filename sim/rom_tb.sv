`timescale 1ns/1ps
module rom_tb;
    reg clk_bridge=0, clk_sys=0;
    always #6.734 clk_bridge=~clk_bridge;
    always #25 clk_sys=~clk_sys;
    // As in the Pocket wrapper: a machine reset raises invalidate and flush,
    // a Memories pause raises invalidate alone.
    reg reset=1, load_wr=0, invalidate=1, flush=1, cpu_rd=0;
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
    // The CPU launches an address two clocks before it samples the data, so
    // the address is presented for one clock before readiness is checked.
    // wait_cycles counts only clocks beyond that.
    integer read_count=0,wait_cycles=0;
    task read_byte(input [22:0] addr,input [7:0] expected);
        integer timeout;
        @(negedge clk_sys); cpu_addr=addr;cpu_rd=1;
        @(negedge clk_sys); #1;timeout=0;
        while (!cpu_ready && timeout<100) begin @(negedge clk_sys);#1;timeout++; end
        if(!cpu_ready || cpu_data!==expected)
            $fatal(1,"ROM addr=%h expected=%h got=%h ready=%b",addr,expected,cpu_data,cpu_ready);
        read_count++;wait_cycles+=timeout;
        @(negedge clk_sys);cpu_rd=0;
    endtask
    function [7:0] pattern_byte(input integer addr);
        pattern_byte=((32'h80402000+addr/4)>>((addr%4)*8))&255;
    endfunction
    // A read takes three clocks here; gap=1 gives the CPU's four-clock bus cycle.
    task stream(input integer first,input integer count,input integer gap);
        for(integer a=first;a<first+count;a++)begin
            read_byte(a,pattern_byte(a));repeat(gap)@(negedge clk_sys);
        end
    endtask
    reg [15:0] lfsr=16'hace1;
    task random_reads(input integer count,input integer span);
        for(integer n=0;n<count;n++)begin
            lfsr={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            read_byte(lfsr%span,pattern_byte(lfsr%span));
            repeat(lfsr[3:0]%10)@(negedge clk_sys);
        end
    endtask
    task restart_counts; read_count=0;wait_cycles=0; endtask
    initial begin
        #300;reset=0;
        // Burst deliberately exceeds the service rate to exercise FIFO wrap/drain.
        for(integer n=0;n<900;n++) write_word(n*4,32'h80402000+n);
        wait(load_idle);#100;
        if(overflow)$fatal(1,"loader overflow");
        invalidate=0;flush=0;
        // Reads while the cache is still being emptied come from PSRAM:
        // random jumps (some while a prefetch is in flight), then a stream.
        if(!dut.sweeping)$fatal(1,"Cache sweep did not start");
        random_reads(300,3600);
        stream(1001,200,1);
        if(!dut.sweeping)$fatal(1,"Sweep ended before the uncached reads");
        wait(!dut.sweeping);
        // First touch of every byte fills the cache.
        for(integer n=0;n<900;n++) begin
            read_byte(n*4,(32'h80402000+n)&255);
            read_byte(n*4+1,((32'h80402000+n)>>8)&255);
            read_byte(n*4+2,8'h40);read_byte(n*4+3,8'h80);
        end
        // Everything is cached now: jumps and table reads must not wait.
        restart_counts();random_reads(3000,3600);
        $display("Cached random reads: %0d reads, %0d wait cycles",read_count,wait_cycles);
        if(wait_cycles!=0)$fatal(1,"Cached reads waited");
        // A Memories pause drops the two registers but keeps the cache.
        invalidate=1;repeat(4)@(negedge clk_sys);invalidate=0;
        restart_counts();random_reads(500,3600);stream(2003,300,0);
        if(wait_cycles!=0)$fatal(1,"Reads after a pause waited: %0d",wait_cycles);
        // Reset and load more data. This second burst crosses the
        // 1024-entry circular pointer boundary.
        invalidate=1;flush=1;
        for(integer n=900;n<1200;n++) write_word(n*4,32'h80402000+n);
        wait(load_idle);#100;invalidate=0;flush=0;
        wait(!dut.sweeping);
        // First touch of straight-line code at CPU bus speed: the prefetcher
        // must keep ahead of the reads.
        restart_counts();stream(3600,1200,1);
        $display("Uncached sequential stream: %0d reads, %0d wait cycles",read_count,wait_cycles);
        if(wait_cycles>read_count/8)$fatal(1,"Prefetch is not keeping up with sequential reads");
        for(integer n=900;n<1200;n++)begin
            read_byte(n*4,(32'h80402000+n)&255);
            read_byte(n*4+3,8'h80);
        end
        // Reload different data over cached addresses. Neither during the
        // sweep nor after it may the old contents be returned.
        read_byte(0,8'h00);read_byte(23'h200000,8'h00);
        invalidate=1;flush=1;
        write_word(23'h200000,32'haabbccdd);
        write_word(0,32'h01020304);
        wait(load_idle);#300;invalidate=0;flush=0;
        if(!dut.sweeping)$fatal(1,"Flush did not restart the sweep");
        read_byte(0,8'h04);read_byte(1,8'h03);
        read_byte(23'h200000,8'hdd);read_byte(23'h200003,8'haa);
        wait(!dut.sweeping);
        read_byte(0,8'h04);read_byte(3,8'h01);
        read_byte(23'h200000,8'hdd);read_byte(23'h200002,8'hbb);
        read_byte(4,pattern_byte(4));
        $display("PASS ROM: burst FIFO, byte order, both slots, cache hits, flush on reload, prefetch");$finish;
    end
    initial begin #40000000;$fatal(1,"ROM test timeout");end
endmodule
