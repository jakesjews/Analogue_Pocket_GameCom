// SPDX-License-Identifier: GPL-2.0-or-later
// Convert the core's level syncs / pixel enable into the APF packet raster.
// Run at 30 MHz, accepting one 6 MHz pixel every five clocks. HS is delayed
// three clocks so it never coincides with VS (an APF protocol requirement).
module pocket_video (
    input wire clk, input wire reset,
    input wire ce, input wire hblank, input wire vblank,
    input wire hs, input wire vs, input wire [2:0] shade,
    input wire [1:0] palette,
    output reg [23:0] rgb, output reg de, output reg skip,
    output reg out_hs, output reg out_vs
);
    reg prev_hs, prev_vs;
    reg [2:0] hs_delay;
    reg [119:0] colors;
    reg [23:0] pixel;
    always @* begin
        case (palette)
            0: colors = 120'hE7E8D6D4D8BAA7AF86737D5E424B3B;
            1: colors = 120'hE1E0D4C9C8B6A4A48A7A7A5F4C4D3C;
            default: colors = 120'hFFFFFFBFBFBF808080404040101010;
        endcase
        case (shade)
            4: pixel = colors[119:96];
            3: pixel = colors[95:72];
            2: pixel = colors[71:48];
            1: pixel = colors[47:24];
            default: pixel = colors[23:0];
        endcase
    end
    always @(posedge clk) begin
        if (reset) begin
            prev_hs <= 1; prev_vs <= 1; hs_delay <= 0;
            rgb <= 0; de <= 0; skip <= 0; out_hs <= 0; out_vs <= 0;
        end else begin
            prev_hs <= hs; prev_vs <= vs;
            hs_delay <= {hs_delay[1:0], hs && !prev_hs};
            out_hs <= hs_delay[2];
            out_vs <= vs && !prev_vs;
            de <= !hblank && !vblank;
            skip <= !hblank && !vblank && !ce;
            rgb <= (!hblank && !vblank) ? pixel : 24'd0;
        end
    end
endmodule
