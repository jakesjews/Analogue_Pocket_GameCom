`timescale 1ns/1ps
// Exercise the real GameCom DMA and VRAM, seeding registers through Memories.
// The ROM bus deliberately presents stale data until its variable delay expires.
module dma_tb;
    reg clk=0; always #25 clk=~clk;
    reg [1:0] phase=0; always @(posedge clk) phase<=phase+1'b1;
    reg reset=1,run_cpu=0;
    wire phi0=run_cpu && phase==0,phi1=run_cpu && phase==2;
    reg ss_active=0,ss_wr=0;
    reg [2:0] ss_type=4;reg [24:0] ss_addr=0;reg [7:0] ss_data=0;
    wire [20:0] cart_addr;wire cart_rd;wire [12:0] save_addr;
    wire [7:0] save_data;wire save_wr;
    reg [7:0] save_mem[0:8191];
    reg [20:0] pending_addr=0;reg pending=0;
    integer delay_ticks=0,remaining=0;
    function automatic [7:0] pattern(input integer addr);
        pattern=((addr*73)^(addr>>3)^8'h39)&255;
    endfunction
    wire rom_ready=delay_ticks==0 || (pending && pending_addr==cart_addr && remaining==0);
    wire [7:0] rom_data=rom_ready ? pattern(cart_addr) : 8'hde;
    always @(posedge clk) begin
        if(reset || !cart_rd) begin pending<=0;remaining<=0;end
        else if(!pending || pending_addr!=cart_addr)begin
            pending<=1;pending_addr<=cart_addr;remaining<=delay_ticks;
        end else if(remaining>0)remaining<=remaining-1;
        if(save_wr)save_mem[save_addr]<=save_data;
    end
    GameCom #(.DMA_ROM_WAIT(1'b1), .ENABLE_CHEATS(1'b0)) dut(
        .clk_sys(clk),.clk_vid(clk),.phi0(phi0),.phi1(phi1),.reset(reset),
        .stop_disable_i(1'b0),.warm_boot_i(1'b0),.video_reset_i(reset),
        .cart_din_i(rom_data),.rom_read_ready_i(rom_ready),
        .uart_rxd_i(1'b1),.uart_cts_i(1'b1),.uart_dsr_i(1'b1),
        .buttons_i(12'b0),.touch_active_i(1'b0),.touch_x_i(4'b0),.touch_y_i(4'b0),
        .video_60hz_i(1'b1),.palette_four_color_i(1'b1),.cursor_enable_i(1'b0),
        .cursor_x_i(4'b0),.cursor_y_i(4'b0),.save_din_i(save_mem[save_addr]),.rtc_i(65'b0),
        .savestate_pause_req_i(1'b0),.savestate_mem_active_i(ss_active),
        .savestate_mem_type_i(ss_type),.savestate_mem_addr_i(ss_addr),
        .savestate_mem_rd_i(1'b0),.savestate_mem_wr_i(ss_wr),.savestate_mem_wdata_i(ss_data),
        .cheat_clear_i(1'b0),.cheat_code_i(129'b0),
        .cart_addr_o(cart_addr),.cart_rd_o(cart_rd),.save_addr_o(save_addr),
        .save_dout_o(save_data),.save_wren_o(save_wr));
    task put(input integer kind,input integer addr,input [7:0] value);
        @(negedge clk);ss_active=1;ss_type=kind;ss_addr=addr;ss_data=value;ss_wr=1;
        @(negedge clk);ss_wr=0;
    endtask
    reg [7:0] expected[0:8191];
    integer cases=0,read_waits=0,window_waits=0,prefetch_waits=0;
    always @(posedge clk)if(phi0 && dut.u_cpu.dma_active_q && !rom_ready)begin
        case(dut.u_cpu.state_q)
            38:read_waits++;
            51:window_waits++;
            42:if(cart_rd)prefetch_waits++;
        endcase
    end
    task blit(input integer mode,input integer sx,input integer dx,input integer width,
              input integer height,input integer latency,input bit reverse_x);
        integer src_stride,dst_stride,src_pixel,dst_pixel,sa,da,shift_src,shift_dst;
        reg [7:0] source_byte,actual;reg[1:0] pixel;
        @(negedge clk);reset=1;run_cpu=0;ss_active=0;delay_ticks=latency;
        repeat(300)@(negedge clk);reset=0;
        // Source on page A, destination on page B, or external RAM for mode 3.
        for(integer i=0;i<8192;i++)begin
            put(2,i,pattern(i));put(3,i,8'ha5);
            save_mem[i]=(mode==3)?8'ha5:pattern(i);expected[i]=8'ha5;
        end
        put(4,31,0);put(4,32,8'h20); // fastest DMA, 200-pixel VRAM rows
        put(4,34,8'h81|(mode<<1)|(reverse_x?8'h08:0));
        put(4,35,sx);put(4,36,2);put(4,37,width-1);put(4,38,height-1);
        put(4,39,dx);put(4,40,4);put(4,41,8'he4);put(4,42,8'h10);put(4,43,2);
        put(4,11,8'h10);put(4,103,1); // HALTed at FETCH_SETUP, DMA armed
        put(4,106,0);put(4,107,0);put(4,108,0);
        src_stride=(mode==1||mode==2)?64:50;dst_stride=(mode==3)?64:50;
        for(integer y=0;y<height;y++)for(integer x=0;x<width;x++)begin
            src_pixel=sx+(reverse_x?-x:x);dst_pixel=dx+x;
            sa=(2+y)*src_stride+src_pixel/4;da=(4+y)*dst_stride+dst_pixel/4;
            source_byte=pattern(sa+((mode==1)?'h40000:0));
            shift_src=6-2*(src_pixel%4);shift_dst=6-2*(dst_pixel%4);
            pixel=(source_byte>>shift_src)&3;
            expected[da]=(expected[da]&~(3<<shift_dst))|(pixel<<shift_dst);
        end
        @(negedge clk);ss_active=0;run_cpu=1;
        wait(dut.u_cpu.dma_active_q);wait(!dut.u_cpu.dma_active_q);
        @(negedge clk);run_cpu=0;
        for(integer i=0;i<8192;i++)begin
            actual=(mode==3)?save_mem[i]:dut.u_vram1.mem_q[i];
            if(actual!==expected[i])$fatal(1,"DMA mode=%0d sx=%0d dx=%0d size=%0dx%0d delay=%0d reverse=%0d byte=%h got=%h expected=%h",
                mode,sx,dx,width,height,latency,reverse_x,i,actual,expected[i]);
        end
        cases++;$display("PASS DMA mode=%0d sx=%0d dx=%0d size=%0dx%0d delay=%0d reverse=%0d",mode,sx,dx,width,height,latency,reverse_x);$fflush();
    endtask
    initial begin
        blit(1,0,0,32,2,0,0);  // original fast-ROM contract
        blit(1,0,0,32,2,20,0); // initial read and overlapped prefetch
        for(integer phase_x=1;phase_x<4;phase_x++)begin
            blit(1,phase_x,0,19,3,7+phase_x*9,0); // next-byte window
            blit(1,0,phase_x,17,2,20,0); // partial destination read/merge
        end
        blit(1,31,0,24,2,20,1); // reversed source
        blit(1,0,0,1,1,40,0); // one partial pixel
        blit(0,1,2,19,2,100000,0); // VRAM ignores ROM ready
        blit(2,0,0,32,2,100000,0); // RAM prefetch ignores ROM ready
        blit(3,1,2,19,2,100000,0); // VRAM to RAM
        if(read_waits==0||window_waits==0||prefetch_waits==0)$fatal(1,"Missing wait-path coverage");
        $display("PASS %0d DMA cases; wait beats read=%0d window=%0d prefetch=%0d",cases,read_waits,window_waits,prefetch_waits);$finish;
    end
    initial begin #200000000;$fatal(1,"DMA watchdog state=%0d active=%b",dut.u_cpu.state_q,dut.u_cpu.dma_active_q);end
endmodule
