// SPDX-License-Identifier: GPL-2.0-or-later
// APF 48 kHz, 16-bit stereo I2S. The whole serializer uses clk_74a enables;
// no fabric-generated clock drives internal registers. A request/ack mailbox
// transfers one coherent mono sample from clk_sys for each stereo frame.
module pocket_audio (
    input wire clk_bridge, input wire clk_sys, input wire reset,
    input wire [15:0] pcm_unsigned,
    output reg mclk = 0, output reg lrck = 0, output reg dac = 0
);
    reg [14:0] accum = 0;
    wire tick = accum >= 15'd12375;
    reg [1:0] mdiv = 0;
    reg [5:0] bitpos = 0;
    reg [15:0] sample = 0;
    reg request = 0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] request_sync = 0;
    reg ack = 0;
    reg [15:0] held = 0;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [1:0] ack_sync = 0;
    reg [15:0] latest = 0;
    always @(posedge clk_sys) begin
        request_sync <= {request_sync[0], request};
        if (request_sync[1] != ack) begin
            held <= reset ? 16'd0 : pcm_unsigned ^ 16'h8000;
            ack <= request_sync[1];
        end
    end
    always @(posedge clk_bridge) begin
        ack_sync <= {ack_sync[0], ack};
        if (ack_sync[1] == request) latest <= held;
        accum <= tick ? accum - 15'd12375 + 15'd4096 : accum + 15'd4096;
        if (tick) begin
            mclk <= !mclk;
            if (!mclk) begin
                mdiv <= mdiv + 1'b1;
                // Falling SCLK edge: update data, sampled on next rising edge.
                if (mdiv == 3) begin
                    bitpos <= bitpos + 1'b1;
                    // LRCK changes one serial clock before the channel MSB.
                    if (bitpos == 63) begin
                        lrck <= 0;
                        sample <= latest;
                        request <= !request;
                    end
                    if (bitpos == 31) lrck <= 1;
                    dac <= (bitpos[4:0] < 16) ? sample[15-bitpos[3:0]] : 1'b0;
                end
            end
        end
    end
endmodule
