`timescale 1ns/1ps
module boot_tb;
    reg clk_bridge=0,clk_sys=0,clk_video=0;
    always #6.734 clk_bridge=~clk_bridge;
    // Keep the PLL outputs phase-related; independently rounded periods
    // drift in simulation and eventually mis-sample the pixel handoff.
    integer clock_tick=11;
    always #8.333 begin
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
        .cram_ce1_n(ce1),.cram_oe_n(oe),.cram_we_n(we),.cram_ub_n(ub),.cram_lb_n(lb));
    psram_model ram(clk_bridge,a,dq,adv,ce0,ce1,oe,we,ub,lb);
    task load_file(input string filename,input [15:0] id,input [31:0] base);
        integer f,size,n,r;reg[7:0] bytes[0:2097151];
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
        $display("Loaded %s (%0d bytes)",filename,size);$fflush();
    endtask
    integer frame=0,pixels=0,lines=0,line_pixels=0,last_vs_clocks=100;
    reg prev_de=0;reg [23:0] framebuffer[0:31999];
    integer f,n,rom_reads=0,cart_reads=0,save_writes=0,nonuniform=0;
    // Cartridge-speed counters, restarted after a checkpoint resumes: CPU
    // cycles, cycles spent halted, cartridge accesses and cycles in which a
    // cartridge read is waiting for PSRAM data.
    longint active_cycles=0,halted_cycles=0,cart_accesses=0,cart_wait_cycles=0;
    reg prev_cart_rd=0;
    task bench_restart;
        active_cycles=0;halted_cycles=0;cart_accesses=0;cart_wait_cycles=0;
    endtask
    function string bench_summary;
        bench_summary=$sformatf("cycles=%0d halted=%0d cart_accesses=%0d cart_wait_cycles=%0d wait_share=%0.2f%%",
            active_cycles,halted_cycles,cart_accesses,cart_wait_cycles,
            100.0*cart_wait_cycles/(active_cycles-halted_cycles+1));
    endfunction
    always @(posedge clk_sys) if(!dut.core_reset && !dut.state_pause) begin
        active_cycles++;
        if(dut.machine.u_cpu.halted_q||dut.machine.cpu_stopped_w)halted_cycles++;
        prev_cart_rd<=dut.cart_rd&&!dut.bios_sel;
        if(dut.cart_rd&&!dut.bios_sel&&!prev_cart_rd)cart_accesses++;
        if(dut.cart_rd&&!dut.bios_sel&&dut.present&&!dut.rom_ready)cart_wait_cycles++;
    end
    always @(posedge clk_sys) begin
        if(!dut.core_reset && dut.cart_rd && dut.phi0)begin
            rom_reads++;if(!dut.bios_sel)cart_reads++;
            if(rom_reads<30)begin
              $display("ROM pc=%h a=%h phys=%h ready=%b data=%h request=%b ack=%b current=%b next=%b",dut.machine.u_cpu.pc_q,dut.cart_addr,dut.physical_addr,dut.rom_ready,dut.rom_data,dut.rom.request,dut.rom.ack,dut.rom.current_valid,dut.rom.next_valid);$fflush();
            end
        end
        if(!dut.core_reset && dut.save_wr)save_writes++;
    end
    always @(negedge clk_video) if(pll_locked)begin
        last_vs_clocks++;
        if(video_vs)begin
            last_vs_clocks=0;
            if(frame>1 && (pixels!=32000||lines!=160))
                $fatal(1,"Invalid frame %d: pixels=%d lines=%d",frame,pixels,lines);
            frame++;pixels=0;lines=0;
            if(frame%60==0&&frame_prefix!="")capture_image($sformatf("%s-%0d.ppm",frame_prefix,frame/60));
            if(frame%30==0)begin $display("frame=%d pc=%h stopped=%b reads=%d saves=%d",frame,dut.machine.u_cpu.pc_q,dut.machine.cpu_stopped_w,rom_reads,save_writes);$fflush();end
        end
        if(video_hs && last_vs_clocks<3)$fatal(1,"HS too close to VS");
        if(video_skip&&!video_de)$fatal(1,"SKIP outside DE");
        if(!video_de&&video_rgb!=0)$fatal(1,"Nonzero blanking RGB");
        if(video_de&&!video_skip)begin
            if(pixels<32000)framebuffer[pixels]=video_rgb;
            pixels++;line_pixels++;
        end
        if(prev_de&&!video_de)begin
            if(line_pixels!=200)$fatal(1,"Line width %d",line_pixels);
            lines++;line_pixels=0;
        end
        prev_de=video_de;
    end
    task readword(input integer addr,output reg[31:0] value);
        @(negedge clk_bridge);bridge_rd=1;bridge_addr=addr;
        @(negedge clk_bridge);bridge_rd=0;
        repeat(3)@(negedge clk_bridge);value=bridge_rd_data;
    endtask
    task writeword(input integer addr,input reg[31:0] value);
        @(negedge clk_bridge);bridge_wr=1;bridge_addr=addr;bridge_wr_data=value;
        @(negedge clk_bridge);bridge_wr=0;
    endtask
    reg [31:0] snapshot[0:6727];
    task state_roundtrip;
        integer errors;
        @(negedge clk_bridge);state_start=1;wait(state_start_ack);
        @(negedge clk_bridge);state_start=0;wait(state_start_ok||state_start_err);
        if(state_start_err)$fatal(1,"Live CPU snapshot failed");
        for(integer i=0;i<6728;i++)readword(32'h50000000+i*4,snapshot[i]);
        #1000000;
        for(integer i=0;i<6728;i++)writeword(32'h50000000+i*4,snapshot[i]);
        @(negedge clk_bridge);state_load=1;wait(state_load_ack);
        @(negedge clk_bridge);state_load=0;
        // Compare at the end of the restore (RELEASE), while the machine is
        // still paused; APF's ok arrives a few bridge clocks later.
        wait(dut.memories.state==7);#1;
        if(dut.memories.status!=8'h40)$fatal(1,"Live CPU restore failed");
        if(!dut.state_pause)$fatal(1,"CPU resumed before restore completed");
        if(dut.machine.u_cpu.pc_q!==snapshot[6216][15:0])
            $fatal(1,"Restored PC %h expected %h",dut.machine.u_cpu.pc_q,snapshot[6216][15:0]);
        errors=0;
        for(integer i=0;i<8192;i++)begin
            if(dut.machine.u_vram0.mem_q[i]!==((snapshot[2120+i/4]>>((i%4)*8))&255))errors++;
            if(dut.machine.u_vram1.mem_q[i]!==((snapshot[4168+i/4]>>((i%4)*8))&255))errors++;
        end
        for(integer i=0;i<2048;i++)begin
            if({dut.nvram.lanes[3].mem[i],dut.nvram.lanes[2].mem[i],dut.nvram.lanes[1].mem[i],dut.nvram.lanes[0].mem[i]}!==snapshot[8+i])errors++;
        end
        if(errors)$fatal(1,"Live CPU restore memory mismatches: %0d",errors);
        wait(state_load_ok||state_load_err);
        if(state_load_err)$fatal(1,"Live CPU restore reported an error");
        $display("PASS live Memories: restored PC=%h, 16 KB VRAM and 8 KB NVRAM",dut.machine.u_cpu.pc_q);$fflush();
        wait(!dut.state_pause);
    endtask
    task capture_image(input string filename);
        integer file_handle;
        file_handle=$fopen(filename,"w");$fwrite(file_handle,"P3\n200 160\n255\n");
        for(integer i=0;i<32000;i++)$fwrite(file_handle,"%d %d %d\n",framebuffer[i][23:16],framebuffer[i][15:8],framebuffer[i][7:0]);
        $fclose(file_handle);
    endtask
    task restore_file(input string filename);
        integer file_handle,size;
        reg [7:0] bytes[0:26912];
        file_handle=$fopen(filename,"rb");if(!file_handle)$fatal(1,"Missing state %s",filename);
        size=$fread(bytes,file_handle);$fclose(file_handle);
        if(size!=26912)$fatal(1,"Bad state size %0d",size);
        for(integer i=0;i<26912;i+=4)writeword(32'h50000000+i,{bytes[i+3],bytes[i+2],bytes[i+1],bytes[i]});
        @(negedge clk_bridge);state_load=1;wait(state_load_ack);
        @(negedge clk_bridge);state_load=0;wait(state_load_ok||state_load_err);
        if(state_load_err)$fatal(1,"State resume failed");wait(!dut.state_pause);
        bench_restart();
        $display("Resumed %s at PC %h",filename,dut.machine.u_cpu.pc_q);$fflush();
    endtask
    task press(input[15:0] bits,input integer ms);
        keys=32'h10000000|bits;#(ms*1000000.0);keys=32'h10000000;#50000000;
    endtask
    task launch_cartridge;
        // Initial Pocket cursor is (5,4). Cartridge icon center is (2,2).
        press(16'h0101,50);press(16'h0101,50);
        press(16'h0104,50);press(16'h0104,50);press(16'h0104,50);
        press(16'h0200,150);
    endtask
    string bios,cart,save,out,frame_prefix,state_out,state_in;
    reg previous_stopped=0;
    always @(posedge clk_sys)if(!dut.core_reset)begin
        previous_stopped<=dut.machine.cpu_stopped_w;
        if(dut.machine.cpu_stopped_w&&!previous_stopped)begin
            $display("CPU STOP pc=%h at %0t",dut.machine.u_cpu.pc_q,$time);$fflush();
        end
    end
    integer run_ms=2000,press_key=0;
    initial begin
        if(!$value$plusargs("BIOS=%s",bios))$fatal(1,"Pass +BIOS=file");
        if(!$value$plusargs("CART=%s",cart))cart="";
        if(!$value$plusargs("SAVE=%s",save))save="";
        if(!$value$plusargs("OUT=%s",out))out="/tmp/gamecom-frame.ppm";
        if(!$value$plusargs("RUN_MS=%d",run_ms))run_ms=2000;
        if(!$value$plusargs("FRAME_PREFIX=%s",frame_prefix))frame_prefix="";
        if(!$value$plusargs("STATE_OUT=%s",state_out))state_out="";
        if(!$value$plusargs("STATE_IN=%s",state_in))state_in="";
        #1000;pll_locked=1;wait(setup_done);
        load_file(bios,1,32'h10000000);
        if(cart!="")load_file(cart,0,0);
        if(save!="")load_file(save,3,32'h30000000);
        @(negedge clk_bridge);all_complete=1;
        @(negedge clk_bridge);all_complete=0;reset_n=1;
        wait(!dut.core_reset);
        $display("SRAM BIOS word0=%h word1000=%h word1001=%h",bios_ram.mem[0],bios_ram.mem['h1000],bios_ram.mem['h1001]);$fflush();
        if(state_in!="")restore_file(state_in);
        if($value$plusargs("PRESS_KEY=%h",press_key))begin
            #100000000;press(press_key[15:0],100);
        end
        if($test$plusargs("LAUNCH_CART"))begin
            #100000000;launch_cartridge();
        end
        if($test$plusargs("MEMORIES"))begin
            #200000000;state_roundtrip();
            #((run_ms-200)*1000000.0);
        end else #(run_ms*1000000.0);
        if(dut.core_reset||dut.rom_overflow||rom_reads<1000)$fatal(1,"Core failed to execute");
        @(posedge video_vs);
        f=$fopen(out,"w");$fwrite(f,"P3\n200 160\n255\n");
        for(n=0;n<32000;n++)begin
            $fwrite(f,"%d %d %d\n",framebuffer[n][23:16],framebuffer[n][15:8],framebuffer[n][7:0]);
            if(framebuffer[n]!=framebuffer[0])nonuniform++;
        end
        $fclose(f);
        if(nonuniform<100)$fatal(1,"Frame is blank/uniform");
        $display("PASS BIOS boot: frames=%d reads=%d cartridge_reads=%d save_writes=%d nonuniform=%d pc=%h output=%s",frame,rom_reads,cart_reads,save_writes,nonuniform,dut.machine.u_cpu.pc_q,out);
        $display("Cartridge speed: %s",bench_summary());
        if(state_out!="")begin
            @(negedge clk_bridge);state_start=1;wait(state_start_ack);
            @(negedge clk_bridge);state_start=0;wait(state_start_ok||state_start_err);
            if(state_start_err)$fatal(1,"Snapshot export failed");
            f=$fopen(state_out,"wb");
            for(integer i=0;i<6728;i++)begin
                readword(32'h50000000+i*4,snapshot[i]);
                for(integer b=0;b<4;b++)$fwrite(f,"%c",snapshot[i][b*8+:8]);
            end
            $fclose(f);
        end
        // Keep the checkpoint even if a cartridge launch needs further input.
        if($test$plusargs("LAUNCH_CART")&&cart_reads<10000)$fatal(1,"Cartridge did not execute: %0d read beats",cart_reads);
        if($test$plusargs("LAUNCH_CART"))$display("PASS cartridge execution: %0d cartridge read beats",cart_reads);
        $finish;
    end
    initial begin #20000000000;$fatal(1,"Boot timeout");end
endmodule
