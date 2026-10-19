// SPDX-License-Identifier: GPL-2.0-or-later
// The Game.com serial port over the Pocket's link port.
//
// The Compete.com cable was a null modem: it crossed TXD with RXD, RTS with
// CTS and DTR with DSR between two consoles. A Game Boy link cable crosses
// only SO and SI, so the three outputs travel together on SO as a continuous
// stream of 8-bit frames at 2 Mbps, and the peer's frames arrive on SI:
//
//   start 0 | TXD | RTS | DTR | even parity | stop 1 | idle 1 | idle 1
//
// A frame takes 4 us, so a serial edge reaches the other Game.com between 3
// and 7 us late. The fastest Game.com bit is 12.8 us, so the 4 us of jitter
// stays inside the half bit the receiving UART tolerates.
//
// The receiver samples each bit near its middle, counted from the start edge,
// and keeps a frame only if its start, parity and stop bits check. A start
// edge counts only after the line has been high for 2.5 bits: the stop and
// two idle bits always precede a real start, while no edge inside a frame
// follows more than two high bits, so the receiver cannot lock onto the
// wrong edge. Eight good frames in a row connect the link; 16 frame periods
// without one disconnect it, so an unplugged cable or a Pocket in another
// core looks like an open port within 64 us: RXD, CTS and DSR all read high,
// as with no cable.
//
// Each Pocket runs this clock from its own 74.25 MHz oscillator, so the two
// sides agree to within parts per million and an eight-bit frame needs no
// clock recovery beyond its start edge.
module pocket_link #(parameter BIT_CLOCKS = 10) (
    input wire clk, input wire reset,
    input wire txd, input wire rts, input wire dtr,
    output wire rxd, output wire cts, output wire dsr,
    output reg linked = 0,
    output reg so = 1, input wire si
);
    // Eight bits per frame: tx_bit and rx_bit wrap at 3'd7.
    localparam FRAME_BITS = 8;
    localparam SAMPLE_CLOCK = BIT_CLOCKS / 2 - 1;
    localparam START_GAP = BIT_CLOCKS * 5 / 2;
    localparam [10:0] SILENCE_LIMIT = 11'(16 * FRAME_BITS * BIT_CLOCKS);

    // Transmitter: TXD, RTS and DTR are captured together at each start bit
    // so one frame never mixes two states.
    reg [3:0] tx_clock = 0;
    reg [2:0] tx_bit = 0;
    reg [2:0] tx_data = 3'b111;
    always @(posedge clk) begin
        if (reset) begin
            tx_clock <= 0; tx_bit <= 0; tx_data <= 3'b111; so <= 1;
        end else if (tx_clock != BIT_CLOCKS - 1) tx_clock <= tx_clock + 1'b1;
        else begin
            tx_clock <= 0;
            tx_bit <= tx_bit + 1'b1;
            case (tx_bit)
                3'd7: begin so <= 0; tx_data <= {dtr, rts, txd}; end
                3'd0: so <= tx_data[0];
                3'd1: so <= tx_data[1];
                3'd2: so <= tx_data[2];
                3'd3: so <= ^tx_data;
                default: so <= 1;
            endcase
        end
    end

    // Receiver.
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg si_meta = 1, si_sync = 1;
    reg si_last = 1;
    reg [4:0] high_run = 0;
    reg rx_busy = 0;
    reg [3:0] rx_clock = 0;
    reg [2:0] rx_bit = 0;
    reg [4:0] rx_shift = 0;
    reg [2:0] rx_data = 3'b111;
    reg [3:0] good = 0;
    reg [10:0] silence = SILENCE_LIMIT;
    wire sample = rx_busy && rx_clock == SAMPLE_CLOCK;
    wire frame_ok = !rx_shift[0] && rx_shift[4] == ^rx_shift[3:1] && si_sync;
    always @(posedge clk) begin
        si_meta <= si; si_sync <= si_meta; si_last <= si_sync;
        if (!si_sync) high_run <= 0;
        else if (high_run != START_GAP) high_run <= high_run + 1'b1;
        if (reset) begin
            rx_busy <= 0; rx_data <= 3'b111; good <= 0;
            silence <= SILENCE_LIMIT; linked <= 0;
        end else begin
            if (silence != SILENCE_LIMIT) silence <= silence + 1'b1;
            else begin linked <= 0; good <= 0; end
            if (!rx_busy) begin
                if (si_last && !si_sync && high_run == START_GAP) begin
                    rx_busy <= 1; rx_clock <= 1; rx_bit <= 0;
                end
            end else begin
                rx_clock <= rx_clock == BIT_CLOCKS - 1 ? 4'd0 : rx_clock + 1'b1;
                if (rx_clock == BIT_CLOCKS - 1) rx_bit <= rx_bit + 1'b1;
                if (sample) begin
                    rx_shift[rx_bit[2:0]] <= si_sync;
                    // A start bit that is gone by mid-bit was a glitch.
                    if (rx_bit == 0 && si_sync) rx_busy <= 0;
                    if (rx_bit == 3'd5) begin
                        rx_busy <= 0;
                        if (frame_ok) begin
                            rx_data <= rx_shift[3:1]; silence <= 0;
                            if (good != 8) good <= good + 1'b1;
                            if (good == 7) linked <= 1;
                        end else good <= 0;
                    end
                end
            end
        end
    end
    assign rxd = !linked || rx_data[0];
    assign cts = !linked || rx_data[1];
    assign dsr = !linked || rx_data[2];
endmodule
