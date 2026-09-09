`timescale 1ns/1ps
module io_tb;
    reg clk_bridge=0,clk_sys=0;
    always #6.734 clk_bridge=~clk_bridge;
    always #25 clk_sys=~clk_sys;
    reg [10:0] bridge_addr=0;reg bridge_wr=0;reg [31:0] bridge_data=0;wire [31:0] bridge_q;
    reg [12:0] cpu_addr=0;reg cpu_wr=0;reg [7:0] cpu_data=0;wire [7:0] cpu_q;
    pocket_save_ram ram(.*);
    reg reset=1,in_menu=0,power_press=0,sound_press=0;
    reg [31:0] keys=32'h10000000,joy=32'h80808080;
    wire[11:0] buttons;wire touching,cursor_visible;wire[3:0] touch_x,touch_y;
    pocket_input #(.REPEAT_CYCLES(8)) controls(.clk(clk_sys),.*);
    reg [15:0] pcm_unsigned=16'h9234;
    wire mclk,lrck,dac;
    pocket_audio sound(.*);
    task key(input[15:0] k);
        @(negedge clk_sys);keys={16'h1000,k};repeat(5)@(negedge clk_sys);
    endtask
    integer i,frames=0;
    reg [1:0] mdiv=0;reg sclk=0;
    // Recreate SCLK exactly as the receiving system FPGA does.
    always @(posedge mclk) begin mdiv<=mdiv+1'b1;sclk<=(mdiv+1'b1)>=2;end
    reg old_lrck=0;integer bit_index=0;reg[15:0] sample=0;
    always @(posedge sclk)begin
        if(lrck!=old_lrck)begin
            if(bit_index>=16 && frames>4 && sample!==16'h1234)
                $fatal(1,"I2S sample %h expected 1234",sample);
            old_lrck=lrck;bit_index=0;frames++;
        end else begin
            if(bit_index<16)sample={sample[14:0],dac};
            bit_index++;
        end
    end
    initial begin
        #500;reset=0;
        @(negedge clk_bridge);bridge_addr=2047;bridge_data=32'hfedcba98;bridge_wr=1;
        @(negedge clk_bridge);bridge_wr=0;
        for(i=0;i<4;i++)begin
            @(negedge clk_sys);cpu_addr=8188+i;
            repeat(2)@(negedge clk_sys);
            if(cpu_q!==((32'hfedcba98>>(i*8))&255))$fatal(1,"NVRAM lane %d got %h",i,cpu_q);
        end
        for(i=0;i<4;i++)begin
            @(negedge clk_sys);cpu_addr=8188+i;cpu_data=8'h10+i;cpu_wr=1;
            @(negedge clk_sys);cpu_wr=0;
        end
        repeat(3)@(negedge clk_bridge);
        if(bridge_q!==32'h13121110)$fatal(1,"NVRAM bridge read %h",bridge_q);
        key(16'h00f0);
        if(buttons[9:6]!==4'hf)$fatal(1,"Face button mapping");
        key(16'h0108);
        if(buttons[3:0]!=0||!cursor_visible)$fatal(1,"Touch movement leaked into game");
        repeat(120)@(negedge clk_sys);
        if(touch_x!=11)$fatal(1,"Touch X clamp %d",touch_x);
        key(16'h0110);
        if(!touching||buttons[6])$fatal(1,"L+A touch");
        key(16'h0200);if(!touching)$fatal(1,"R touch");
        in_menu=1;#1;if(touching)$fatal(1,"Menu input leaked");
        #300000;
        if(frames<20)$fatal(1,"I2S not running");
        $display("PASS IO: NVRAM byte lanes, touch controls, menu filtering, coherent signed I2S");$finish;
    end
endmodule
