// SPDX-License-Identifier: GPL-2.0-or-later
// L + D-pad positions the 13x10 touch grid, R touches it. While L is held,
// A is also a touch button and the D-pad/A do not reach the game buttons.
// The right-stick directions arrive already thresholded on the bridge clock,
// so each synchronized bit is independent and cannot tear.
module pocket_input #(parameter REPEAT_CYCLES = 2500000, parameter POWER_CYCLES = 2000000) (
    input wire clk, input wire reset, input wire in_menu,
    input wire [31:0] keys, input wire [3:0] stick,
    input wire power_press, input wire sound_press, input wire stopped,
    output wire [11:0] buttons,
    output wire touching, output wire cursor_visible,
    output reg [3:0] touch_x = 5, output reg [3:0] touch_y = 4
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [31:0] keys_meta, keys_sync;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *) reg [3:0] stick_meta, stick_sync;
    // A 100 ms Power press: supplied once after reset to start the BIOS, and
    // again when a face button or Start is pressed while the Game.com is
    // stopped (powered off), so it can be woken without the Pocket menu.
    reg [21:0] power_pulse;
    reg [23:0] repeat_count;
    reg [3:0] previous_move;
    reg previous_wake;
    wire gamepad = keys_sync[31:28] >= 1 && keys_sync[31:28] <= 3;
    wire [15:0] k = gamepad && !in_menu ? keys_sync[15:0] : 16'd0;
    wire analog = keys_sync[31:28] == 3 && !in_menu;
    wire [3:0] movement = (k[8] ? k[3:0] : 4'd0) | (analog ? stick_sync : 4'd0);
    wire wake = k[15] || (|k[7:4]);
    assign buttons = {power_press || (power_pulse != 0), k[15], k[7], k[6],
                      k[5], k[4] && !k[8], sound_press, k[14],
                      (k[8] ? 4'd0 : k[3:0])};
    assign touching = k[9] || (k[8] && k[4]);
    assign cursor_visible = k[8] || touching || (analog && |movement);
    always @(posedge clk) begin
        keys_meta <= keys; keys_sync <= keys_meta;
        stick_meta <= stick; stick_sync <= stick_meta;
        previous_wake <= wake;
        if (reset) begin
            power_pulse <= POWER_CYCLES;
            repeat_count <= 0; previous_move <= 0;
            touch_x <= 5; touch_y <= 4;
        end else begin
            if (stopped && wake && !previous_wake) power_pulse <= POWER_CYCLES;
            else if (power_pulse != 0) power_pulse <= power_pulse - 1'b1;
            previous_move <= movement;
            if (!(|movement)) repeat_count <= 0;
            else if (movement != previous_move || repeat_count == 0) begin
                repeat_count <= REPEAT_CYCLES-1;
                if (movement[0] && !movement[1] && touch_y != 0) touch_y <= touch_y - 1'b1;
                if (movement[1] && !movement[0] && touch_y != 9) touch_y <= touch_y + 1'b1;
                if (movement[2] && !movement[3] && touch_x != 0) touch_x <= touch_x - 1'b1;
                if (movement[3] && !movement[2] && touch_x != 12) touch_x <= touch_x + 1'b1;
            end else repeat_count <= repeat_count - 1'b1;
        end
    end
endmodule
