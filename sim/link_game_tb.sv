`timescale 1ns/1ps
// Two complete Pockets running the same cartridge, joined by a link cable.
// A script of timed actions drives them, and every byte either UART sends or
// receives, every link change and every handshake change is printed.
//
// +BIOS=file +CART=file +SCRIPT=file. +STATE_IN=file resumes both Pockets
// from one checkpoint and +STATE_OUT=file saves Pocket A's at the end.
// +ONLY_A leaves B switched off, for making checkpoints. +POOR replaces the
// cable with one whose rising edges arrive 600 ns late and falling edges
// 150 ns late, and whose every edge rings for 40 ns.
//
// Script lines, in time order, in ms after both Pockets are running:
//   <ms> key <a|b> <hex Pocket buttons> <hold ms>
//   <ms> snap <a|b> <file.ppm>
//   <ms> unplug | <ms> plug | <ms> end
module link_game_tb;
    wire so_a,so_b;
    reg cable=1,poor=0,slow_a=1,slow_b=1,ring_a=0,ring_b=0;
    always @(so_b) slow_a <= #(so_b ? 600 : 150) so_b;
    always @(so_a) slow_b <= #(so_a ? 600 : 150) so_a;
    always @(slow_a) begin #30 ring_a=1; #40 ring_a=0; end
    always @(slow_b) begin #30 ring_b=1; #40 ring_b=0; end
    wire si_a = !cable ? 1'b1 : poor ? slow_a^ring_a : so_b;
    wire si_b = !cable ? 1'b1 : poor ? slow_b^ring_b : so_a;
    // Two Pockets never share an oscillator: B runs 60 ppm slow.
    pocket_node #(.NAME("A"),.TICK(8.333)) a(.so(so_a),.si(si_a));
    pocket_node #(.NAME("B"),.TICK(8.3335)) b(.so(so_b),.si(si_b));
    string bios,cart,state_in,state_out,script,cmd,who,arg;
    integer fh,ms,hold,code;reg [15:0] bits;
    realtime t0;
    initial begin
        if(!$value$plusargs("BIOS=%s",bios))$fatal(1,"Pass +BIOS=file");
        if(!$value$plusargs("CART=%s",cart))$fatal(1,"Pass +CART=file");
        if(!$value$plusargs("SCRIPT=%s",script))$fatal(1,"Pass +SCRIPT=file");
        if(!$value$plusargs("STATE_IN=%s",state_in))state_in="";
        if(!$value$plusargs("STATE_OUT=%s",state_out))state_out="";
        poor=$test$plusargs("POOR");
        fork
            a.boot(bios,cart,state_in);
            if(!$test$plusargs("ONLY_A"))b.boot(bios,cart,state_in);
        join
        t0=$realtime;
        $display("%0.3f ms: running",t0/1e6);$fflush();
        fh=$fopen(script,"r");if(!fh)$fatal(1,"Cannot read %s",script);
        while(!$feof(fh))begin
            code=$fscanf(fh,"%d %s",ms,cmd);
            if(code!=2)break;
            if(t0+ms*1e6>$realtime)#(t0+ms*1e6-$realtime);
            if(cmd=="key")begin
                code=$fscanf(fh,"%s %h %d",who,bits,hold);
                if(who=="a")fork a.press(bits,hold); join_none
                else fork b.press(bits,hold); join_none
                $display("%0.3f ms: %s presses %h",$realtime/1e6,who,bits);
            end else if(cmd=="snap")begin
                code=$fscanf(fh,"%s %s",who,arg);
                if(who=="a")a.capture_image(arg); else b.capture_image(arg);
            end else if(cmd=="unplug")begin cable=0;$display("%0.3f ms: cable out",$realtime/1e6);end
            else if(cmd=="plug")begin cable=1;$display("%0.3f ms: cable in",$realtime/1e6);end
            else if(cmd=="end")break;
            $fflush();
        end
        if(state_out!="")a.save_state(state_out);
        $display("%0.3f ms: done",$realtime/1e6);
        $finish;
    end
endmodule

// One Pocket: the wrapper with its SRAM and PSRAM, loaded over the bridge.
module pocket_node #(parameter string NAME="A",parameter real TICK=8.333)(output wire so,input wire si);
    reg clk_bridge=0,clk_sys=0,clk_video=0;
    always #6.734 clk_bridge=~clk_bridge;
    integer clock_tick=11;
    always #(TICK) begin
        clock_tick=(clock_tick+1)%12;
        clk_sys=(clock_tick%6)<3;
        clk_video=(clock_tick%4)<2;
    end
    reg pll_locked=0,reset_n=0,bridge_wr=0,bridge_rd=0;
    reg [31:0] bridge_addr=0,bridge_wr_data=0;
    wire [31:0] bridge_rd_data;
    reg slot_write=0,all_complete=0;
    reg [15:0] slot_id=0;reg [31:0] slot_size=0;
    wire slot_write_ok,setup_done;
    reg [31:0] keys=32'h10000000,joy=32'h80808080;
    wire [23:0] video_rgb;wire video_de,video_skip,video_hs,video_vs;
    wire audio_mclk,audio_lrck,audio_dac;
    wire [21:16] a;wire [15:0] dq;wire cclk,adv,cre,ce0,ce1,oe,we,ub,lb;
    wire [16:0] sram_a;wire [15:0] sram_dq;
    wire sram_oe_n,sram_we_n,sram_ub_n,sram_lb_n;
    sram_model bios_ram(sram_a,sram_dq,sram_oe_n,sram_we_n,sram_ub_n,sram_lb_n);
    reg state_start=0,state_load=0;
    wire state_start_ack,state_start_busy,state_start_ok,state_start_err;
    wire state_load_ack,state_load_busy,state_load_ok,state_load_err;
    pocket_gamecom dut(.*,.rtc_date(32'h20260909),.rtc_time(32'h03131500),
        .rtc_valid(1'b1),.in_menu(1'b0),.grayscale(1'b0),.cram_a(a),.cram_dq(dq),.cram_wait(1'b0),
        .cram_clk(cclk),.cram_adv_n(adv),.cram_cre(cre),.cram_ce0_n(ce0),
        .cram_ce1_n(ce1),.cram_oe_n(oe),.cram_we_n(we),.cram_ub_n(ub),.cram_lb_n(lb),
        .link_so(so),.link_si(si));
    psram_model ram(clk_bridge,a,dq,adv,ce0,ce1,oe,we,ub,lb);

    task load_file(input string filename,input [15:0] id,input [31:0] base);
        integer f,size,n;reg[7:0] bytes[0:2097151];
        f=$fopen(filename,"rb");if(!f)$fatal(1,"Cannot read %s",filename);
        size=$fread(bytes,f);$fclose(f);
        @(negedge clk_bridge);slot_id=id;slot_size=size;slot_write=1;
        @(negedge clk_bridge);if(!slot_write_ok)$fatal(1,"Rejected slot %d size %d",id,size);slot_write=0;
        for(n=0;n<size;n+=4)begin
            @(negedge clk_bridge);bridge_addr=base+n;
            bridge_wr_data={bytes[n+3],bytes[n+2],bytes[n+1],bytes[n]};bridge_wr=1;
            @(negedge clk_bridge);bridge_wr=0;
            repeat(38) @(negedge clk_bridge);
        end
    endtask
    task readword(input integer addr,output reg[31:0] value);
        @(negedge clk_bridge);bridge_rd=1;bridge_addr=addr;
        @(negedge clk_bridge);bridge_rd=0;
        repeat(3)@(negedge clk_bridge);value=bridge_rd_data;
    endtask
    task writeword(input integer addr,input reg[31:0] value);
        @(negedge clk_bridge);bridge_wr=1;bridge_addr=addr;bridge_wr_data=value;
        @(negedge clk_bridge);bridge_wr=0;
    endtask
    task boot(input string bios,input string cart,input string state_in);
        integer fh,size;reg [7:0] bytes[0:26912];
        #1000;pll_locked=1;wait(setup_done);
        load_file(bios,1,32'h10000000);
        load_file(cart,0,0);
        @(negedge clk_bridge);all_complete=1;
        @(negedge clk_bridge);all_complete=0;reset_n=1;
        wait(!dut.core_reset);
        if(state_in!="")begin
            // Restore after the 100 ms Power press that follows reset, or
            // the BIOS sees it.
            #150000000;
            fh=$fopen(state_in,"rb");if(!fh)$fatal(1,"Missing state %s",state_in);
            size=$fread(bytes,fh);$fclose(fh);
            if(size!=26912)$fatal(1,"Bad state size %0d",size);
            for(integer i=0;i<26912;i+=4)writeword(32'h50000000+i,{bytes[i+3],bytes[i+2],bytes[i+1],bytes[i]});
            @(negedge clk_bridge);state_load=1;wait(state_load_ack);
            @(negedge clk_bridge);state_load=0;wait(state_load_ok||state_load_err);
            if(state_load_err)$fatal(1,"State resume failed");wait(!dut.state_pause);
        end
        $display("%s running at PC %h",NAME,dut.machine.u_cpu.pc_q);$fflush();
    endtask
    task save_state(input string filename);
        integer fh;reg [31:0] word;
        @(negedge clk_bridge);state_start=1;wait(state_start_ack);
        @(negedge clk_bridge);state_start=0;wait(state_start_ok||state_start_err);
        if(state_start_err)$fatal(1,"Snapshot export failed");
        fh=$fopen(filename,"wb");
        for(integer i=0;i<6728;i++)begin
            readword(32'h50000000+i*4,word);
            for(integer b=0;b<4;b++)$fwrite(fh,"%c",word[b*8+:8]);
        end
        $fclose(fh);
        $display("%s saved %s at PC %h",NAME,filename,dut.machine.u_cpu.pc_q);
    endtask
    task press(input [15:0] bits,input integer ms);
        keys=32'h10000000|bits;#(ms*1000000.0);keys=32'h10000000;
    endtask

    reg [23:0] framebuffer[0:31999];integer pixels=0,frame=0;
    always @(negedge clk_video) if(pll_locked)begin
        if(video_vs)begin pixels=0;frame++;end
        if(video_de&&!video_skip)begin
            if(pixels<32000)framebuffer[pixels]=video_rgb;
            pixels++;
        end
    end
    task capture_image(input string filename);
        integer fh;
        fh=$fopen(filename,"w");$fwrite(fh,"P3\n200 160\n255\n");
        for(integer i=0;i<32000;i++)$fwrite(fh,"%0d %0d %0d\n",framebuffer[i][23:16],framebuffer[i][15:8],framebuffer[i][7:0]);
        $fclose(fh);
    endtask

    // Serial-port trace.
    wire [7:0] urts=dut.machine.u_cpu.urts_q,urtc=dut.machine.u_cpu.urtc_q;
    reg tx_q=0,rx_q=0,linked_q=0,rts_q=1,dtr_q=1,cts_q=1,dsr_q=1;reg [7:0] urtc_q=0;
    always @(posedge clk_sys)begin
        tx_q<=dut.machine.u_cpu.uart_tx_active_q;
        if(dut.machine.u_cpu.uart_tx_active_q&&!tx_q)$display("%0.3f ms %s sends %h",$realtime/1e6,NAME,dut.machine.u_cpu.urtt_q);
        rx_q<=urts[0];
        if(urts[0]&&!rx_q)$display("%0.3f ms %s receives %h status %b",$realtime/1e6,NAME,dut.machine.u_cpu.urtr_q,urts);
        urtc_q<=urtc;
        if(urtc!=urtc_q)$display("%0.3f ms %s URTC %h",$realtime/1e6,NAME,urtc);
        linked_q<=dut.linked;
        if(dut.linked!=linked_q)$display("%0.3f ms %s link %s",$realtime/1e6,NAME,dut.linked?"up":"down");
        rts_q<=dut.rts;dtr_q<=dut.dtr;cts_q<=dut.cts;dsr_q<=dut.dsr;
        if({dut.rts,dut.dtr,dut.cts,dut.dsr}!={rts_q,dtr_q,cts_q,dsr_q})
            $display("%0.3f ms %s RTS=%b DTR=%b CTS=%b DSR=%b",$realtime/1e6,NAME,dut.rts,dut.dtr,dut.cts,dut.dsr);
    end
    always @(posedge video_vs) if(frame%76==0)begin
        $display("%0.3f ms %s frame %0d",$realtime/1e6,NAME,frame);$fflush();
    end
endmodule
