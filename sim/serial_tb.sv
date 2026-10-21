`timescale 1ns/1ps
// Two Game.coms on two Pockets joined by a link cable. Each runs a small
// SM8521 program through the real CPU, board and UART: A asserts DTR, waits
// for CTS, then sends 256 bytes at 11161 baud, reading back each echo; B
// waits for CTS, asserts DTR, echoes every byte, and halts when A lowers RTS.
// +MKT_ROM=file instead executes the cartridge's character-select handshake
// at 714Eh on both CPUs. This checks the real game's P3.0 -> peer P3.2 wiring.
module serial_tb;
    reg clk_a=0,clk_b=0;
    always #25 clk_a=~clk_a;
    always #24.995 clk_b=~clk_b;
    reg reset=1,run=0;
    wire so_a,so_b;
    gamecom_node #(.ROLE(0)) a(.clk(clk_a),.reset(reset),.run(run),.so(so_a),.si(so_b));
    gamecom_node #(.ROLE(1)) b(.clk(clk_b),.reset(reset),.run(run),.so(so_b),.si(so_a));
    integer got_a=0,got_b=0;
    reg ready_a=0,ready_b=0;
    always @(posedge clk_a) if(run) begin
        ready_a<=a.machine.u_cpu.urts_q[0];
        if(a.machine.u_cpu.urts_q[0]&&!ready_a)begin
            if(a.machine.u_cpu.urtr_q!==got_a[7:0])$fatal(1,"A echo %0d was %h",got_a,a.machine.u_cpu.urtr_q);
            got_a++;
        end
        if(a.machine.u_cpu.urts_q[4:2]!=0)$fatal(1,"A UART error status %b",a.machine.u_cpu.urts_q);
    end
    always @(posedge clk_b) if(run) begin
        ready_b<=b.machine.u_cpu.urts_q[0];
        if(b.machine.u_cpu.urts_q[0]&&!ready_b)begin
            if(b.machine.u_cpu.urtr_q!==got_b[7:0])$fatal(1,"B byte %0d was %h",got_b,b.machine.u_cpu.urtr_q);
            got_b++;
        end
        if(b.machine.u_cpu.urts_q[4:2]!=0)$fatal(1,"B UART error status %b",b.machine.u_cpu.urts_q);
    end
    // +TRACE prints every fetch, transmit and receive of both consoles.
    integer fetches_a=0,fetches_b=0;reg tx_a=0,tx_b=0,rxa_a=0,rxa_b=0;
    always @(posedge clk_a) if(run&&$test$plusargs("TRACE"))begin
        if(a.machine.u_cpu.phi0_ce_i&&a.machine.u_cpu.state_q==1&&fetches_a<120)begin
            fetches_a++;$display("%0t A fetch pc=%h op=%h R0=%h urts=%h",$time,a.machine.u_cpu.pc_q,a.cart_din,a.machine.u_cpu.gp_read(4'd0),a.machine.u_cpu.urts_q);end
        tx_a<=a.machine.u_cpu.uart_tx_active_q;
        if(a.machine.u_cpu.uart_tx_active_q&&!tx_a)$display("%0t A sends %h",$time,a.machine.u_cpu.urtt_q);
        rxa_a<=a.machine.u_cpu.urts_q[0];
        if(a.machine.u_cpu.urts_q[0]&&!rxa_a)$display("%0t A receives %h",$time,a.machine.u_cpu.urtr_q);
    end
    always @(posedge clk_b) if(run&&$test$plusargs("TRACE"))begin
        if(b.machine.u_cpu.phi0_ce_i&&b.machine.u_cpu.state_q==1&&fetches_b<120)begin
            fetches_b++;$display("%0t B fetch pc=%h op=%h R0=%h urts=%h",$time,b.machine.u_cpu.pc_q,b.cart_din,b.machine.u_cpu.gp_read(4'd0),b.machine.u_cpu.urts_q);end
        tx_b<=b.machine.u_cpu.uart_tx_active_q;
        if(b.machine.u_cpu.uart_tx_active_q&&!tx_b)$display("%0t B sends %h",$time,b.machine.u_cpu.urtt_q);
        rxa_b<=b.machine.u_cpu.urts_q[0];
        if(b.machine.u_cpu.urts_q[0]&&!rxa_b)$display("%0t B receives %h",$time,b.machine.u_cpu.urtr_q);
    end
    initial begin
        repeat(300)@(negedge clk_a);reset=0;
        wait(a.seeded&&b.seeded);
        if(a.mkt)begin
            // Do not mistake the disconnected port's high inputs for a peer.
            wait(a.linked&&b.linked);repeat(1000)@(negedge clk_a);
        end
        @(negedge clk_a);run=1;
        if(a.mkt)begin
            fork
                begin
                    wait(a.finished&&b.finished);
                    $display("PASS MKT ROM: both CPUs passed the character-select handshake at 714E..7174, at %0.1f us",$realtime/1000);
                    $finish;
                end
                begin
                    #2000000;
                    $fatal(1,"MKT handshake blocked: A pc=%h P3=%h, B pc=%h P3=%h",
                        a.machine.u_cpu.pc_q,a.machine.u_cpu.read_sfr(8'h17),
                        b.machine.u_cpu.pc_q,b.machine.u_cpu.read_sfr(8'h17));
                end
            join
        end
        wait(a.machine.u_cpu.halted_q&&b.machine.u_cpu.halted_q);
        if(got_a!=256||got_b!=256)$fatal(1,"A received %0d echoes, B received %0d bytes",got_a,got_b);
        if(!a.linked||!b.linked)$fatal(1,"Link dropped");
        $display("PASS serial: two Game.coms exchanged 256 bytes each way at 11161 baud with P3.0/P3.2 and P3.1/P3.3 handshakes, at %0.1f ms",$realtime/1e6);
        $finish;
    end
    initial begin #1500000000;$fatal(1,"Serial bench timeout: A pc=%h got=%0d, B pc=%h got=%0d linked=%b%b",
        a.machine.u_cpu.pc_q,got_a,b.machine.u_cpu.pc_q,got_b,a.linked,b.linked);end
endmodule

// One Pocket: a Game.com with its link transport, running a program from
// address 2000h, which the MMU maps to physical 0 with its reset values.
module gamecom_node #(parameter ROLE=0)(input clk,input reset,input run,output so,input si);
    reg [1:0] phase=0; always @(posedge clk) phase<=phase+1'b1;
    reg mkt=0,finished=0;
    wire phi0=run&&!finished&&phase==0,phi1=run&&!finished&&phase==2;
    reg ss_active=0,ss_wr=0;reg [24:0] ss_addr=0;reg [7:0] ss_data=0;
    wire [20:0] cart_addr;
    reg [7:0] rom[0:2097151];
    integer rom_size=64;
    wire [7:0] cart_din=cart_addr<rom_size?rom[cart_addr]:8'hF1;
    wire txd,rts,dtr,rxd,cts,dsr,linked;
    GameCom #(.DMA_ROM_WAIT(1'b1),.ENABLE_CHEATS(1'b0)) machine(
        .clk_sys(clk),.clk_vid(clk),.phi0(phi0),.phi1(phi1),.reset(reset),
        .stop_disable_i(1'b0),.warm_boot_i(1'b0),.video_reset_i(reset),
        .cart_din_i(cart_din),.rom_read_ready_i(1'b1),
        .uart_rxd_i(rxd),.uart_cts_i(cts),.uart_dsr_i(dsr),
        .buttons_i(12'b0),.touch_active_i(1'b0),.touch_x_i(4'b0),.touch_y_i(4'b0),
        .video_60hz_i(1'b1),.palette_four_color_i(1'b1),.cursor_enable_i(1'b0),
        .cursor_x_i(4'b0),.cursor_y_i(4'b0),.save_din_i(8'hff),.rtc_i(65'b0),
        .savestate_pause_req_i(1'b0),.savestate_mem_active_i(ss_active),
        .savestate_mem_type_i(3'd4),.savestate_mem_addr_i(ss_addr),
        .savestate_mem_rd_i(1'b0),.savestate_mem_wr_i(ss_wr),.savestate_mem_wdata_i(ss_data),
        .cheat_clear_i(1'b0),.cheat_code_i(129'b0),
        .cart_addr_o(cart_addr),.cart_rd_o(),.save_addr_o(),.save_dout_o(),.save_wren_o(),
        .cpu_txdb_o(txd),.uart_rts_o(rts),.uart_dtr_o(dtr));
    pocket_link link(.clk(clk),.reset(reset),.txd(txd),.rts(rts),.dtr(dtr),
        .rxd(rxd),.cts(cts),.dsr(dsr),.linked(linked),.so(so),.si(si));
    always @(posedge clk) if(mkt&&run&&machine.u_cpu.state_q==1&&machine.u_cpu.pc_q==16'h7174)
        finished<=1;
    task put(input integer addr,input [7:0] value);
        @(negedge clk);ss_active=1;ss_addr=addr;ss_data=value;ss_wr=1;
        @(negedge clk);ss_wr=0;
    endtask
    reg seeded=0;
    integer n;
    // Shared setup: TM0 reload 7 at tap 0, the BIOS's fastest link setting,
    // gives 11161 baud; URTC enables TX and RX with no parity and one stop
    // bit; P3.0 (DTR) and P3.1 (RTS) become outputs, idle high.
    localparam [7:0] SETUP [0:13] = '{8'h58,8'h07,8'h51, 8'h58,8'h80,8'h50, 8'h58,8'h1C,8'h2E,
                                     8'hCF,8'hFF, 8'h58,8'h02,8'h23};
    // A: P3.0 low; wait P3.2 low; R0=0, R1=0; loop: wait TX ready, URTT=R0,
    // wait RX ready, R2=URTR, R0++, DBNZ R1; P3.1 low; HALT.
    localparam [7:0] SENDER [0:26] = '{8'hA0,8'h17, 8'h8A,8'h17,8'hFD, 8'hC0,8'h00, 8'hC1,8'h00,
                                      8'h81,8'h2D,8'hFD, 8'hB8,8'h2B, 8'h80,8'h2D,8'hFD, 8'hB2,8'h2C,
                                      8'h51,8'h01,8'h00, 8'h71,8'hF1, 8'hA1,8'h17, 8'hF1};
    // B: wait P3.2 low; P3.0 low; loop: P3.3 low -> HALT; wait RX ready;
    // R0=URTR; wait TX ready; URTT=R0; loop.
    localparam [7:0] ECHO [0:20] = '{8'h8A,8'h17,8'hFD, 8'hA0,8'h17, 8'h83,8'h17,8'h0C, 8'h80,8'h2D,8'hFA,
                                    8'hB0,8'h2C, 8'h81,8'h2D,8'hFD, 8'hB8,8'h2B, 8'hD8,8'hF1, 8'hF1};
    initial begin
        string cartridge;integer fh;
        for(n=0;n<64;n++)rom[n]=8'hF1;
        for(n=0;n<14;n++)rom[n]=SETUP[n];
        if(ROLE==0) for(n=0;n<27;n++)rom[14+n]=SENDER[n];
        else for(n=0;n<21;n++)rom[14+n]=ECHO[n];
        if($value$plusargs("MKT_ROM=%s",cartridge))begin
            mkt=1;fh=$fopen(cartridge,"rb");if(!fh)$fatal(1,"Cannot read %s",cartridge);
            rom_size=$fread(rom,fh);$fclose(fh);
            if(rom_size!=2097152||{rom['h4714e],rom['h4714f],rom['h47150],rom['h47151]}!=32'hb017a800)
                $fatal(1,"Expected Mortal Kombat Trilogy (USA) cartridge");
        end
        @(negedge reset);repeat(4)@(negedge clk);
        if(mkt)begin
            put(0,8'h4e);put(1,8'h71);      // game's post-search handshake
            put(12,8'h40);put(2,8'hf0);put(3,8'h03); // 16-bit stack at 03f0
            put(17,8'hfc);put(21,8'h02);   // P3.0 and P3.1 driven low
            put(25,8'h23);put(29,8'h23);   // bank 23 at CPU 6000h
            // Valid two-player roles, with selection markers already drawn:
            // the wrong handshake input must not enter unrelated UI drawing.
            put(288+'hfc,ROLE==0?8'h40:8'hc0);
            put(288+'hcb,8'h1b);put(288+'hdd,8'h1b);
        end else begin put(0,8'h00);put(1,8'h20);end
        put(106,0);put(107,0);put(108,0);   // no reset warm-up
        put(103,1);                         // fetch the first opcode
        @(negedge clk);ss_active=0;seeded=1;
    end
endmodule
