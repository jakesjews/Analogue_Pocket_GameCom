`timescale 1ns/1ps
module state_tb;
    reg clk_bridge=0,clk_sys=0;always #6.734 clk_bridge=~clk_bridge;always #25 clk_sys=~clk_sys;
    reg reset=1,start=0,load=0,bridge_wr=0,bridge_rd=0;
    reg [14:0] bridge_addr=0;reg [31:0] bridge_data=0;wire [31:0] bridge_q;
    wire start_ack,start_busy,start_ok,start_err,load_ack,load_busy,load_ok,load_err;
    wire pause_req,mem_active,mem_rd,mem_wr;reg pause_ready=0;
    wire [2:0] mem_type;wire[24:0] mem_addr;wire[7:0]mem_wdata;reg[7:0]mem_q;
    pocket_state dut(.*);
    reg [7:0] memory [0:26879];reg [31:0] blob[0:6727];
    integer phys,errors=0;
    always @* case(mem_type)
        0:phys=mem_addr;1:phys=8192+mem_addr;2:phys=8448+mem_addr;
        3:phys=16640+mem_addr;default:phys=24832+mem_addr;
    endcase
    always @(posedge clk_sys)begin
        pause_ready<=pause_req;
        mem_q<=memory[phys];
        if(mem_active&&mem_wr)memory[phys]<=mem_wdata;
    end
    task readword(input integer addr,output reg[31:0] value);
        @(negedge clk_bridge);bridge_rd=1;bridge_addr=addr;
        @(negedge clk_bridge);bridge_rd=0;
        repeat(3)@(negedge clk_bridge);value=bridge_q;
    endtask
    task writeword(input integer addr,input reg[31:0] value);
        @(negedge clk_bridge);bridge_wr=1;bridge_addr=addr;bridge_data=value;
        @(negedge clk_bridge);bridge_wr=0;
    endtask
    initial begin
        for(integer i=0;i<26880;i++)memory[i]=(i*17+(i>>8))&255;
        #500;reset=0;
        @(negedge clk_bridge);start=1;wait(start_ack);
        @(negedge clk_bridge);start=0;
        wait(start_ok);wait(!pause_req);
        for(integer i=0;i<6728;i++)readword(i*4,blob[i]);
        if(blob[0]!=32'h4b504347||blob[1]!=1||blob[2]!=26912)$fatal(1,"State header");
        for(integer i=0;i<26880;i++)begin
            if(((blob[8+i/4]>>((i%4)*8))&255)!=((i*17+(i>>8))&255))errors++;
            memory[i]=8'h55;
        end
        if(errors)$fatal(1,"Snapshot differs: %0d bytes",errors);
        for(integer i=0;i<6728;i++)writeword(i*4,blob[i]);
        @(negedge clk_bridge);load=1;wait(load_ack);
        @(negedge clk_bridge);load=0;
        wait(load_ok||load_err);if(load_err)$fatal(1,"Restore error");wait(!pause_req);
        for(integer i=0;i<26880;i++)if(memory[i]!==((i*17+(i>>8))&255))errors++;
        if(errors)$fatal(1,"Restore differs: %0d bytes",errors);
        // A corrupt header must be rejected before any machine memory changes.
        for(integer i=0;i<6728;i++)writeword(i*4,i==0?0:blob[i]);memory[0]=8'ha5;
        @(negedge clk_bridge);load=1;wait(load_ack);
        @(negedge clk_bridge);load=0;
        wait(load_err);wait(!pause_req);
        if(memory[0]!==8'ha5)$fatal(1,"Invalid restore modified machine");
        // A valid first word with an incomplete transfer must also fail.
        writeword(0,blob[0]);
        @(negedge clk_bridge);load=1;wait(load_ack);
        @(negedge clk_bridge);load=0;
        wait(load_err&&!load_busy);wait(!pause_req);
        if(memory[0]!==8'ha5)$fatal(1,"Truncated restore modified machine");
        $display("PASS Memories: 26880-byte capture/restore, APF words, header and length validation, pause release");$finish;
    end
    initial begin #100000000;$fatal(1,"State timeout");end
endmodule
