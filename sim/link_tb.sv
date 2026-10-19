`timescale 1ns/1ps
// Two link transports back to back on independent clocks, as two Pockets
// joined by a Game Boy link cable. Checks the open-port defaults, link-up and
// link-down timing, handshake transport, a full-duplex UART stream at the
// Game.com's fastest rate, and rejection of noise and foreign traffic.
module link_tb;
    // 20 MHz and 20 MHz + 200 ppm: two Pockets never share an oscillator.
    reg clk_a=0,clk_b=0;
    always #25 clk_a=~clk_a;
    always #24.995 clk_b=~clk_b;
    reg reset=1;
    reg txd_a=1,rts_a=1,dtr_a=1,txd_b=1,rts_b=1,dtr_b=1;
    wire rxd_a,cts_a,dsr_a,rxd_b,cts_b,dsr_b,linked_a,linked_b,so_a,so_b;
    // The cable: 0 = crossed normally, 1 = unplugged, 2 = noise into B,
    // 3 = a Game Boy style 512 kHz stream into B.
    integer cable=1;
    reg noise=1,gameboy=1;
    wire si_a = cable==0 ? so_b : 1'b1;
    wire si_b = cable==0 ? so_a : cable==2 ? noise : cable==3 ? gameboy : 1'b1;
    pocket_link a(.clk(clk_a),.reset(reset),.txd(txd_a),.rts(rts_a),.dtr(dtr_a),
        .rxd(rxd_a),.cts(cts_a),.dsr(dsr_a),.linked(linked_a),.so(so_a),.si(si_a));
    pocket_link b(.clk(clk_b),.reset(reset),.txd(txd_b),.rts(rts_b),.dtr(dtr_b),
        .rxd(rxd_b),.cts(cts_b),.dsr(dsr_b),.linked(linked_b),.so(so_b),.si(si_b));
    // Random noise with 50 ns to 2 us between edges.
    always begin #($urandom_range(50,2000)); noise=$urandom_range(0,1)!=0; end
    // Game Boy Color fast serial: alternating bits at 512 kHz.
    always #976.5 gameboy=~gameboy;

    // Edge latency from A's TXD to B's RXD, and the reverse.
    realtime txd_a_change=0,txd_b_change=0;
    realtime min_delay=1e9,max_delay=0;
    integer edges=0;
    always @(posedge txd_a,negedge txd_a) txd_a_change=$realtime;
    always @(posedge txd_b,negedge txd_b) txd_b_change=$realtime;
    always @(rxd_b) if(linked_b && rxd_b==txd_a) begin
        if($realtime-txd_a_change<min_delay) min_delay=$realtime-txd_a_change;
        if($realtime-txd_a_change>max_delay) max_delay=$realtime-txd_a_change;
        edges++;
    end
    always @(rxd_a) if(linked_a && rxd_a==txd_b) begin
        if($realtime-txd_b_change<min_delay) min_delay=$realtime-txd_b_change;
        if($realtime-txd_b_change>max_delay) max_delay=$realtime-txd_b_change;
        edges++;
    end

    // 78125 baud, the fastest Game.com setting: 12.8 us bits, 8N1.
    localparam real BIT=12800;
    task automatic send(input which,input [7:0] value);
        if(which) txd_b=0; else txd_a=0;
        #BIT;
        for(integer i=0;i<8;i++)begin if(which) txd_b=value[i]; else txd_a=value[i];#BIT;end
        if(which) txd_b=1; else txd_a=1;
        #BIT;
    endtask
    // Receive like the SM8521: half a bit after the start edge, then mid-bit.
    task automatic receive(input which,output [7:0] value);
        if(which) @(negedge rxd_b); else @(negedge rxd_a);
        #(BIT/2);
        if(which ? rxd_b : rxd_a) $fatal(1,"Start bit vanished");
        for(integer i=0;i<8;i++)begin #BIT;value[i]=which?rxd_b:rxd_a;end
        #BIT;if(!(which?rxd_b:rxd_a))$fatal(1,"Stop bit missing");
    endtask
    reg [7:0] sent_a[0:63],sent_b[0:63],got_a[0:63],got_b[0:63];
    integer received_a=0,received_b=0;
    task check_open(input string when);
        if(linked_a||linked_b)$fatal(1,"%s: linked",when);
        if(!(rxd_a&&cts_a&&dsr_a&&rxd_b&&cts_b&&dsr_b))$fatal(1,"%s: inputs not idle high",when);
    endtask
    realtime t0;
    initial begin
        #200 reset=0;
        // Unplugged: an open port.
        #300000;check_open("Unplugged");
        // Plug in: both sides link within 60 us.
        cable=0;t0=$realtime;wait(linked_a&&linked_b);
        if($realtime-t0>60000)$fatal(1,"Link-up took %0.1f us",($realtime-t0)/1000);
        $display("Linked after %0.1f us",($realtime-t0)/1000);
        #10000;if(!(rxd_a&&cts_a&&dsr_a&&rxd_b&&cts_b&&dsr_b))$fatal(1,"Idle lines not high after link-up");
        // Handshake lines cross like a null modem.
        rts_a=0;#8000;if(cts_b||!cts_a)$fatal(1,"RTS A -> CTS B");
        dtr_b=0;#8000;if(dsr_a||!dsr_b)$fatal(1,"DTR B -> DSR A");
        rts_a=1;dtr_b=1;#8000;if(!(cts_b&&dsr_a))$fatal(1,"Handshake release");
        // Full duplex: both sides stream 64 random bytes at once.
        for(integer i=0;i<64;i++)begin sent_a[i]=8'($urandom);sent_b[i]=8'($urandom);end
        fork
            for(integer i=0;i<64;i++)begin send(0,sent_a[i]);#($urandom_range(0,20000));end
            for(integer i=0;i<64;i++)begin send(1,sent_b[i]);#($urandom_range(0,20000));end
            for(integer i=0;i<64;i++)begin receive(1,got_b[i]);received_b++;end
            for(integer i=0;i<64;i++)begin receive(0,got_a[i]);received_a++;end
        join
        for(integer i=0;i<64;i++)begin
            if(got_b[i]!==sent_a[i])$fatal(1,"B received %h, A sent %h (byte %0d)",got_b[i],sent_a[i],i);
            if(got_a[i]!==sent_b[i])$fatal(1,"A received %h, B sent %h (byte %0d)",got_a[i],sent_b[i],i);
        end
        if(edges<400)$fatal(1,"Only %0d edges measured",edges);
        if(min_delay<2000||max_delay>7500||max_delay-min_delay>4200)
            $fatal(1,"Edge latency %0.2f..%0.2f us",min_delay/1000,max_delay/1000);
        $display("PASS serial: 128 bytes both ways at 78125 baud, edge latency %0.2f..%0.2f us over %0d edges",
            min_delay/1000,max_delay/1000,edges);
        // Unplug mid-stream: back to an open port within 80 us.
        txd_a=0;rts_a=0;#5000;cable=1;t0=$realtime;
        wait(!linked_a&&!linked_b);
        if($realtime-t0>80000)$fatal(1,"Link-down took %0.1f us",($realtime-t0)/1000);
        $display("Unlinked after %0.1f us",($realtime-t0)/1000);
        #1000;check_open("After unplugging");txd_a=1;rts_a=1;
        // Noise and a Game Boy stream are not a Game.com.
        cable=2;#3000000;check_open("Noise");
        cable=3;#1000000;check_open("Game Boy traffic");
        // Plugging back in recovers.
        cable=0;t0=$realtime;wait(linked_a&&linked_b);#10000;
        if(!(rxd_a&&cts_a&&dsr_a&&rxd_b&&cts_b&&dsr_b))$fatal(1,"Relink idle lines");
        $display("PASS link: open-port defaults, link-up, null-modem handshakes, unplug, noise and foreign traffic rejected, relink");
        $finish;
    end
    initial begin #40000000;$fatal(1,"Link bench timeout");end
endmodule
