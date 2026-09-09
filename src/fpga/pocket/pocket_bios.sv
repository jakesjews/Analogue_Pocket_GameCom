// SPDX-License-Identifier: GPL-2.0-or-later
// The 256 KB external BIOS exactly fits Pocket's 128K x 16 asynchronous SRAM.
// Reads follow the CPU bus directly (55 ns SRAM in a 100 ns half-beat).
// APF writes occur while the CPU is held in reset. The FIFO absorbs bursts;
// each halfword gets an 81 ns WE pulse, with separate setup/hold/turnaround.
module pocket_bios (
    input wire clk_bridge,input wire reset,
    input wire load_wr,input wire [17:0] load_addr,input wire [31:0] load_data,
    output wire load_idle,output reg overflow=0,
    input wire [17:0] cpu_addr,output wire [7:0] cpu_data,
    output wire [16:0] sram_a,inout wire [15:0] sram_dq,
    output reg sram_oe_n=0,output reg sram_we_n=1,
    output wire sram_ub_n,output wire sram_lb_n
);
    (* ramstyle="M10K" *) reg [47:0] fifo[0:1023];
    reg [9:0] wr_ptr=0,rd_ptr=0;
    reg [10:0] count=0;
    reg [47:0] fifo_q;
    reg [4:0] state=0;
    reg [15:0] write_addr,write_data;
    reg [47:0] pending;
    reg half=0,drive=0;
    wire pop=state==0&&count!=0;
    wire push=load_wr&&(count<1024||pop);
    assign load_idle=count==0&&state==0&&!load_wr;
    assign sram_a=state==0?cpu_addr[17:1]:{write_addr,half};
    assign sram_dq=drive?write_data:16'hzzzz;
    assign sram_ub_n=0;
    assign sram_lb_n=0;
    assign cpu_data=cpu_addr[0]?sram_dq[15:8]:sram_dq[7:0];
    always @(posedge clk_bridge)begin
        fifo_q<=fifo[rd_ptr];
        if(push)begin fifo[wr_ptr]<={load_addr[17:2],load_data};wr_ptr<=wr_ptr+1'b1;end
        case({push,pop})
            2'b10:count<=count+1'b1;
            2'b01:count<=count-1'b1;
            default:;
        endcase
        if(load_wr&&!push)overflow<=1;
        if(reset)begin
            state<=0;wr_ptr<=0;rd_ptr<=0;count<=0;overflow<=0;
            drive<=0;sram_oe_n<=0;sram_we_n<=1;
        end else begin
            if(state!=0)state<=state+1'b1;
            case(state)
                0:if(count!=0)begin
                    state<=1;rd_ptr<=rd_ptr+1'b1;sram_oe_n<=1;
                end
                1:pending<=fifo_q;
                3:begin write_addr<=pending[47:32];half<=0;write_data<=pending[15:0];drive<=1;end
                4:sram_we_n<=0;
                10:sram_we_n<=1;
                12:begin half<=1;write_data<=pending[31:16];end
                13:sram_we_n<=0;
                19:sram_we_n<=1;
                21:drive<=0;
                22:begin sram_oe_n<=0;state<=0;end
                default:;
            endcase
        end
    end
endmodule
