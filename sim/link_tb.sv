`timescale 1ns/1ps
// Two link transports back to back on independent clocks, as two Pockets
// joined by a Game Boy link cable. Checks the open-port defaults, link-up and
// link-down timing, handshake transport, a full-duplex UART stream at the
// BIOS's fastest link rate, rejection of noise and foreign traffic, and a
// stream through a cable with slow, ringing edges.
module link_tb;
    // 20 MHz and 20 MHz + 200 ppm: two Pockets never share an oscillator.
    reg clk_a=0,clk_b=0;
    always #25 clk_a=~clk_a;
    always #24.995 clk_b=~clk_b;
    reg reset=1;
    reg txd_a=1,rts_a=1,dtr_a=1,txd_b=1,rts_b=1,dtr_b=1;
    wire rxd_a,cts_a,dsr_a,rxd_b,cts_b,dsr_b,linked_a,linked_b,so_a,so_b;
    // The cable: 0 = crossed normally, 1 = unplugged, 2 = noise into B,
    // 3 = a Game Boy style 512 kHz stream into B, 4 = crossed through a poor
    // cable whose rising edges arrive 600 ns late, falling edges 150 ns late,
    // and every edge rings for 40 ns.
    integer cable=1;
    reg noise=1,gameboy=1;
    reg slow_a=1,slow_b=1,ring_a=0,ring_b=0;
    always @(so_b) slow_a <= #(so_b ? 600 : 150) so_b;
    always @(so_a) slow_b <= #(so_a ? 600 : 150) so_a;
    always @(slow_a) begin #30 ring_a=1; #40 ring_a=0; end
    always @(slow_b) begin #30 ring_b=1; #40 ring_b=0; end
    wire si_a = cable==0 ? so_b : cable==4 ? slow_a^ring_a : 1'b1;
    wire si_b = cable==0 ? so_a : cable==2 ? noise : cable==3 ? gameboy : cable==4 ? slow_b^ring_b : 1'b1;
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

    // The BIOS's fastest link setting in this core: 89.6 us bits, 8N1.
    localparam real BIT=89600;
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
        // Plug in: both sides link within 200 us.
        cable=0;t0=$realtime;wait(linked_a&&linked_b);
        if($realtime-t0>200000)$fatal(1,"Link-up took %0.1f us",($realtime-t0)/1000);
        $display("Linked after %0.1f us",($realtime-t0)/1000);
        #40000;if(!(rxd_a&&cts_a&&dsr_a&&rxd_b&&cts_b&&dsr_b))$fatal(1,"Idle lines not high after link-up");
        // Compete.com: P3.0 -> peer P3.2; P3.1 -> peer P3.3.
        for(integer i=0;i<4;i++)begin
            {rts_a,dtr_a}=2'(i);{rts_b,dtr_b}=~2'(i);#40000;
            if({dsr_b,cts_b}!={rts_a,dtr_a}||{dsr_a,cts_a}!={rts_b,dtr_b})
                $fatal(1,"Compete.com P3 handshake mapping, state %0d",i);
        end
        rts_a=1;dtr_a=1;rts_b=1;dtr_b=1;#40000;
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
        if(min_delay<10000||max_delay>28500||max_delay-min_delay>16500)
            $fatal(1,"Edge latency %0.2f..%0.2f us",min_delay/1000,max_delay/1000);
        $display("PASS serial: 128 bytes both ways at 11161 baud, edge latency %0.2f..%0.2f us over %0d edges",
            min_delay/1000,max_delay/1000,edges);
        // Unplug mid-stream: back to an open port within 300 us.
        txd_a=0;rts_a=0;#40000;cable=1;t0=$realtime;
        wait(!linked_a&&!linked_b);
        if($realtime-t0>300000)$fatal(1,"Link-down took %0.1f us",($realtime-t0)/1000);
        $display("Unlinked after %0.1f us",($realtime-t0)/1000);
        #1000;check_open("After unplugging");txd_a=1;rts_a=1;
        // Noise and a Game Boy stream are not a Game.com.
        cable=2;#3000000;check_open("Noise");
        cable=3;#1000000;check_open("Game Boy traffic");
        // Plugging back in recovers.
        cable=0;t0=$realtime;wait(linked_a&&linked_b);#40000;
        if(!(rxd_a&&cts_a&&dsr_a&&rxd_b&&cts_b&&dsr_b))$fatal(1,"Relink idle lines");
        // A poor cable still carries a full-duplex stream intact.
        cable=1;wait(!linked_a&&!linked_b);
        cable=4;wait(linked_a&&linked_b);#40000;
        fork
            for(integer i=0;i<16;i++)begin send(0,sent_a[i]);#($urandom_range(0,20000));end
            for(integer i=0;i<16;i++)begin send(1,sent_b[i]);#($urandom_range(0,20000));end
            for(integer i=0;i<16;i++)receive(1,got_b[i]);
            for(integer i=0;i<16;i++)receive(0,got_a[i]);
        join
        for(integer i=0;i<16;i++)
            if(got_b[i]!==sent_a[i]||got_a[i]!==sent_b[i])$fatal(1,"Poor cable byte %0d corrupted",i);
        if(!linked_a||!linked_b)$fatal(1,"Poor cable dropped the link");
        $display("PASS link: open-port defaults, link-up, Compete.com handshakes, unplug, noise and foreign traffic rejected, relink, poor cable");
        $finish;
    end
    initial begin #200000000;$fatal(1,"Link bench timeout");end
endmodule
