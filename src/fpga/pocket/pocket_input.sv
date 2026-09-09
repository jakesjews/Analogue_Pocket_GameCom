// SPDX-License-Identifier: GPL-2.0-or-later
// L + D-pad positions the 12x10 touch grid, R touches it. While L is held,
// A is also a touch button and the D-pad/A do not reach the game buttons.
module pocket_input #(parameter REPEAT_CYCLES = 2500000) (
    input wire clk, input wire reset, input wire in_menu,
    input wire [31:0] keys, input wire [31:0] joy,
    input wire power_press, input wire sound_press,
    output wire [11:0] buttons,
    output wire touching, output wire cursor_visible,
    output reg [3:0] touch_x = 5, output reg [3:0] touch_y = 4
);
    (* async_reg = "true" *) reg [31:0] keys_meta, keys_sync;
    (* async_reg = "true" *) reg [31:0] joy_meta, joy_sync;
    reg [21:0] startup;
    reg [23:0] repeat_count;
    reg [3:0] previous_move;
    wire gamepad = keys_sync[31:28] >= 1 && keys_sync[31:28] <= 3;
    wire [15:0] k = gamepad && !in_menu ? keys_sync[15:0] : 16'd0;
    wire analog = keys_sync[31:28] == 3 && !in_menu;
    wire [3:0] movement = (k[8] ? k[3:0] : 4'd0) |
        {analog && joy_sync[23:16] > 192, analog && joy_sync[23:16] < 64,
         analog && joy_sync[31:24] > 192, analog && joy_sync[31:24] < 64};
    assign buttons = {power_press || (startup != 0), k[15], k[7], k[6],
                      k[5], k[4] && !k[8], sound_press, k[14],
                      (k[8] ? 4'd0 : k[3:0])};
    assign touching = k[9] || (k[8] && k[4]);
    assign cursor_visible = k[8] || touching || (analog && |movement);
    always @(posedge clk) begin
        keys_meta <= keys; keys_sync <= keys_meta;
        joy_meta <= joy; joy_sync <= joy_meta;
        if (reset) begin
            startup <= 22'd2000000;
            repeat_count <= 0; previous_move <= 0;
            touch_x <= 5; touch_y <= 4;
        end else begin
            if (startup != 0) startup <= startup - 1'b1;
            previous_move <= movement;
            if (!(|movement)) repeat_count <= 0;
            else if (movement != previous_move || repeat_count == 0) begin
                repeat_count <= REPEAT_CYCLES-1;
                if (movement[0] && !movement[1] && touch_y != 0) touch_y <= touch_y - 1'b1;
                if (movement[1] && !movement[0] && touch_y != 9) touch_y <= touch_y + 1'b1;
                if (movement[2] && !movement[3] && touch_x != 0) touch_x <= touch_x - 1'b1;
                if (movement[3] && !movement[2] && touch_x != 11) touch_x <= touch_x + 1'b1;
            end else repeat_count <= repeat_count - 1'b1;
        end
    end
endmodule
