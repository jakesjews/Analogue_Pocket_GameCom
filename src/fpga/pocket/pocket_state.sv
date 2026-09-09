// SPDX-License-Identifier: GPL-2.0-or-later
// APF Memories snapshot buffer. APF writes a restore blob before issuing its
// load command. Capture/restore starts only after the CPU reaches a safe pause.
module pocket_state (
    input wire clk_bridge,input wire clk_sys,input wire reset,
    input wire start,input wire load,
    output wire start_ack,output wire start_busy,output wire start_ok,output wire start_err,
    output wire load_ack,output wire load_busy,output wire load_ok,output wire load_err,
    input wire bridge_wr,input wire bridge_rd,input wire [14:0] bridge_addr,
    input wire [31:0] bridge_data,output wire [31:0] bridge_q,
    output wire pause_req,input wire pause_ready,
    output wire mem_active,output reg [2:0] mem_type,output reg [24:0] mem_addr,
    output wire mem_rd,output wire mem_wr,output wire [7:0] mem_wdata,input wire [7:0] mem_q
);
    localparam BYTES=26912; // 32-byte header + 8192 + 256 + 8192 + 8192 + 2048
    localparam IDLE=0,PAUSE=1,HEADER=2,READ_WAIT=3,COPY=4,RESTORE_WAIT=5,RESTORE=6,RELEASE=7;
    reg [3:0] state=IDLE;
    reg restoring=0;
    reg [14:0] index=0;
    reg start_prev=0,load_prev=0;
    (* async_reg="true" *) reg [1:0] start_sync=0,load_sync=0;
    reg [7:0] status=0;
    reg [7:0] status_meta=0,status_bridge=0;
    reg invalid_header=0;
    // Reject truncated or out-of-order restore transfers, even if an older
    // complete snapshot remains in the staging RAM.
    reg [12:0] restore_words=0;
    reg restore_order_bad=0;
    (* async_reg="true" *) reg [1:0] restore_complete_sync=0;
    always @(posedge clk_bridge) begin
        if(reset)begin restore_words<=0;restore_order_bad<=0;end
        else if(bridge_wr)begin
            if(bridge_addr==0)begin restore_words<=1;restore_order_bad<=0;end
            else if(!restore_order_bad&&bridge_addr=={restore_words,2'b00}&&restore_words<BYTES/4)
                restore_words<=restore_words+1'b1;
            else restore_order_bad<=1;
        end
    end
    reg [23:0] timeout=0;
    // Status bits: start ack/busy/ok/error, then load ack/busy/ok/error.
    assign {load_err,load_ok,load_busy,load_ack,start_err,start_ok,start_busy,start_ack}=status_bridge;
    always @(posedge clk_bridge)begin status_meta<=status;status_bridge<=status_meta;end
    assign pause_req=state!=IDLE&&state!=RELEASE;
    assign mem_active=index>=32&&(state==READ_WAIT||state==COPY||state==RESTORE_WAIT||state==RESTORE);
    assign mem_rd=state==READ_WAIT||state==COPY;
    assign mem_wr=state==RESTORE&&index>=32;
    wire [7:0] buffer_q;
    reg [7:0] buffer_data;
    wire buffer_wr=!restoring&&(state==HEADER||state==COPY);
    assign mem_wdata=buffer_q;
    reg [12:0] bridge_hold=0;
    always @(posedge clk_bridge)if(bridge_rd)bridge_hold<=bridge_addr[14:2];
    pocket_save_ram #(.ADDR_WIDTH(15)) buffer (
        .clk_bridge(clk_bridge),.bridge_addr(bridge_wr?bridge_addr[14:2]:bridge_hold),
        .bridge_wr(bridge_wr),.bridge_data(bridge_data),.bridge_q(bridge_q),
        .clk_sys(clk_sys),.cpu_addr(index),.cpu_wr(buffer_wr),.cpu_data(buffer_data),.cpu_q(buffer_q)
    );
    function [7:0] header(input[4:0] n);
        case(n)
            0:header="G";1:header="C";2:header="P";3:header="K";
            4:header=1; // format version
            8:header=BYTES&255;9:header=BYTES>>8;
            default:header=0;
        endcase
    endfunction
    always @* begin
        if(index<32)begin mem_type=0;mem_addr=0;end
        else if(index<8224)begin mem_type=0;mem_addr=index-32;end
        else if(index<8480)begin mem_type=1;mem_addr=index-8224;end
        else if(index<16672)begin mem_type=2;mem_addr=index-8480;end
        else if(index<24864)begin mem_type=3;mem_addr=index-16672;end
        else begin mem_type=4;mem_addr=index-24864;end
        buffer_data=index<32?header(index[4:0]):mem_q;
    end
    always @(posedge clk_sys)begin
        start_sync<={start_sync[0],start};load_sync<={load_sync[0],load};
        restore_complete_sync<={restore_complete_sync[0],restore_words==BYTES/4&&!restore_order_bad};
        start_prev<=start_sync[1];load_prev<=load_sync[1];
        if(!start_sync[1])status[0]<=0;
        if(!load_sync[1])status[4]<=0;
        if(reset)begin state<=IDLE;status<=0;timeout<=0;end
        else if(state==IDLE)begin
            timeout<=0;
            if((start_sync[1]&&!start_prev)||(load_sync[1]&&!load_prev))begin
                restoring<=load_sync[1]&&!load_prev;
                status<=(load_sync[1]&&!load_prev)?8'h30:8'h03;
                index<=0;invalid_header<=0;state<=PAUSE;
            end
        end else begin
            timeout<=timeout+1'b1;
            if(timeout==24'hffffff)begin
                status<=restoring?8'h80:8'h08;state<=RELEASE;
            end else case(state)
                PAUSE:if(pause_ready)begin
                    if(restoring&&!restore_complete_sync[1])begin status<=8'h80;state<=RELEASE;end
                    else state<=restoring?RESTORE_WAIT:HEADER;
                end
                HEADER:begin
                    index<=index+1'b1;
                    if(index==31)state<=READ_WAIT;
                end
                READ_WAIT:state<=COPY;
                COPY:begin
                    if(index==BYTES-1)begin status<=8'h04;state<=RELEASE;end
                    else begin index<=index+1'b1;state<=READ_WAIT;end
                end
                RESTORE_WAIT:state<=RESTORE;
                RESTORE:begin
                    // Header bytes never drive the machine's memory write port.
                    if(index<32&&buffer_q!=header(index[4:0]))invalid_header<=1;
                    if(index==31&&(invalid_header||buffer_q!=header(31)))begin
                        status<=8'h80;state<=RELEASE;
                    end else if(index==BYTES-1)begin status<=8'h40;state<=RELEASE;end
                    else begin index<=index+1'b1;state<=RESTORE_WAIT;end
                end
                RELEASE:if(!pause_ready)state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
