// SPDX-License-Identifier: GPL-2.0-or-later
// Cartridge ROM backing in the first PSRAM die. Byte layout:
// 000000-1fffff cart 1, 200000-3fffff cart 2. The BIOS is in SRAM.
// Bridge words are little endian. APF has no wait signal: a 1024-word FIFO
// absorbs bursts while each word is committed as two 16-bit PSRAM writes.
// CPU reads are served from two halfword entries: the current halfword and
// the next one, which is prefetched while the CPU works on the current one.
module pocket_rom (
    input wire clk_bridge, input wire clk_sys, input wire reset,
    input wire load_wr, input wire [22:0] load_addr,
    input wire [31:0] load_data,
    output wire load_idle, output reg overflow = 0,
    input wire invalidate, input wire cpu_rd, input wire [22:0] cpu_addr,
    output wire cpu_ready, output wire [7:0] cpu_data,
    output wire [21:16] cram_a, inout wire [15:0] cram_dq,
    input wire cram_wait, output wire cram_clk, output wire cram_adv_n,
    output wire cram_cre, output wire cram_ce0_n, output wire cram_ce1_n,
    output wire cram_oe_n, output wire cram_we_n,
    output wire cram_ub_n, output wire cram_lb_n
);
    (* ramstyle = "M10K" *) reg [52:0] fifo [0:1023];
    reg [9:0] wr_ptr = 0, rd_ptr = 0;
    reg [10:0] count = 0;
    reg [52:0] fifo_q;
    reg [3:0] state = 0;
    localparam IDLE=0, FETCH=1, WRITE_LO=2, WAIT_LO=3,
               WRITE_HI=4, WAIT_HI=5, READ_START=6, READ_WAIT=7;
    wire pop = state == IDLE && count != 0;
    wire push = load_wr && (count < 1024 || pop);
    reg [21:0] addr_latched;
    reg [31:0] data_latched;
    wire ps_busy, ps_read_avail;
    wire [15:0] ps_q;
    wire ps_wr = state == WRITE_LO || state == WRITE_HI;
    wire ps_rd = state == READ_START;
    assign load_idle = count == 0 && state == IDLE && !load_wr;

    // Bundled-data mailbox: request address remains held until the returned
    // acknowledgement has crossed back. Response data remains held until the
    // next request. Only synchronizer chains cross asynchronous control.
    reg request = 0, ack = 0;
    reg [21:0] request_addr = 0;
    reg [15:0] response = 0;
    (* async_reg = "true" *) reg [1:0] request_sync = 0, ack_sync = 0;
    // Entry 0 holds the halfword the CPU is using; entry 1 holds the next.
    // Every entry is filled by a completed read of its own address, so a hit
    // is always correct data. Only one request is in flight at a time.
    reg [21:0] current_addr = 0, next_addr = 0;
    reg [15:0] current_data = 0, next_data = 0;
    reg current_valid = 0, next_valid = 0;
    wire [21:0] halfword = cpu_addr[22:1];
    wire current_hit = current_valid && current_addr == halfword;
    wire next_hit = next_valid && next_addr == halfword;
    wire hit = current_hit || next_hit;
    assign cpu_ready = !cpu_rd || (hit && !invalidate);
    wire [15:0] hit_data = next_hit ? next_data : current_data;
    assign cpu_data = cpu_addr[0] ? hit_data[15:8] : hit_data[7:0];
    reg outstanding = 0, prefetching = 0;
    wire [21:0] following = current_addr + 1'b1;
    wire want_prefetch = current_valid && !(next_valid && next_addr == following);
    always @(posedge clk_sys) begin
        ack_sync <= {ack_sync[0], ack};
        if (reset) begin
            request <= 0; request_addr <= 0; current_valid <= 0; next_valid <= 0;
            outstanding <= 0; prefetching <= 0; ack_sync <= 0;
        end else begin
            // The CPU has moved on to the prefetched halfword.
            if (!invalidate && cpu_rd && next_hit && !current_hit) begin
                current_addr <= next_addr; current_data <= next_data;
                current_valid <= 1; next_valid <= 0;
            end
            if (outstanding && ack_sync[1] == request) begin
                if (prefetching) begin
                    next_addr <= request_addr; next_data <= response; next_valid <= !invalidate;
                end else begin
                    current_addr <= request_addr; current_data <= response; current_valid <= !invalidate;
                end
                outstanding <= 0;
            end
            if (invalidate) begin current_valid <= 0; next_valid <= 0; end
            if (!invalidate && !outstanding) begin
                if (cpu_rd && !hit) begin
                    request_addr <= halfword; request <= !request;
                    outstanding <= 1; prefetching <= 0;
                end else if (want_prefetch && !(cpu_rd && next_hit && !current_hit)) begin
                    request_addr <= following; request <= !request;
                    outstanding <= 1; prefetching <= 1;
                end
            end
        end
    end
    always @(posedge clk_bridge) begin
        request_sync <= {request_sync[0], request};
        fifo_q <= fifo[rd_ptr];
        if (push) begin
            fifo[wr_ptr] <= {load_addr[22:2], load_data};
            wr_ptr <= wr_ptr + 1'b1;
        end
        case ({push, pop})
            2'b10: count <= count + 1'b1;
            2'b01: count <= count - 1'b1;
            default: ;
        endcase
        if (load_wr && !push) overflow <= 1;
        if (reset) begin
            state <= IDLE; wr_ptr <= 0; rd_ptr <= 0; count <= 0;
            request_sync <= 0; ack <= 0; overflow <= 0;
        end else begin
            case (state)
                IDLE: if (count != 0) begin
                    state <= FETCH;
                    rd_ptr <= rd_ptr + 1'b1;
                end else if (request_sync[1] != ack && !load_wr) begin
                    addr_latched <= request_addr;
                    state <= READ_START;
                end
                FETCH: begin
                    addr_latched <= {fifo_q[52:32], 1'b0};
                    data_latched <= fifo_q[31:0];
                    state <= WRITE_LO;
                end
                WRITE_LO: state <= WAIT_LO;
                WAIT_LO: if (!ps_busy) begin
                    addr_latched <= addr_latched + 1'b1;
                    state <= WRITE_HI;
                end
                WRITE_HI: state <= WAIT_HI;
                WAIT_HI: if (!ps_busy) state <= IDLE;
                READ_START: state <= READ_WAIT;
                READ_WAIT: if (ps_read_avail) begin
                    response <= ps_q;
                    ack <= request_sync[1];
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
    psram #(.CLOCK_SPEED(74.25), .MAX_ACCESS_TIME_FROM_ADV(100),
            .MIN_WRITE_TIME_FROM_ADV(100)) memory (
        .clk(clk_bridge), .bank_sel(1'b0), .addr(addr_latched),
        .write_en(ps_wr), .data_in(state == WRITE_HI ? data_latched[31:16] : data_latched[15:0]),
        .write_high_byte(1'b1), .write_low_byte(1'b1),
        .read_en(ps_rd), .read_avail(ps_read_avail), .data_out(ps_q), .busy(ps_busy),
        .cram_a(cram_a), .cram_dq(cram_dq), .cram_wait(cram_wait),
        .cram_clk(cram_clk), .cram_adv_n(cram_adv_n), .cram_cre(cram_cre),
        .cram_ce0_n(cram_ce0_n), .cram_ce1_n(cram_ce1_n),
        .cram_oe_n(cram_oe_n), .cram_we_n(cram_we_n),
        .cram_ub_n(cram_ub_n), .cram_lb_n(cram_lb_n)
    );
endmodule
