`timescale 1ns/1ps
module sram_model(input wire[16:0] a,inout wire[15:0] dq,
    input wire oe_n,we_n,ub_n,lb_n);
    reg [15:0] mem[0:131071];
    wire [15:0] read_data;
    assign #55 read_data=mem[a];
    assign dq=!oe_n&&we_n?read_data:16'hzzzz;
    realtime write_start;
    reg[16:0] last_addr;
    reg[15:0] last_data;
    always @(negedge we_n)begin
        if(!oe_n)$fatal(1,"SRAM write while output enabled");
        write_start=$realtime;
    end
    always @(a or dq)if(!we_n)begin last_addr=a;last_data=dq;end
    always @(posedge we_n)if($realtime>100)begin
        if($realtime-write_start<45)$fatal(1,"SRAM write pulse too short");
        if(!lb_n)mem[a][7:0]=dq[7:0];
        if(!ub_n)mem[a][15:8]=dq[15:8];
    end
endmodule
