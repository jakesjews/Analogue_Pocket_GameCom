// SPDX-License-Identifier: GPL-2.0-or-later
module pocket_gamecom (
    input wire clk_bridge, input wire clk_sys, input wire clk_video,
    input wire pll_locked, input wire reset_n,
    input wire [31:0] bridge_addr, input wire bridge_wr, input wire bridge_rd,
    input wire [31:0] bridge_wr_data, output reg [31:0] bridge_rd_data,
    input wire slot_write, input wire [15:0] slot_id,
    input wire [31:0] slot_size, input wire all_complete,
    output wire slot_write_ok, output wire setup_done,
    input wire [31:0] rtc_date, input wire [31:0] rtc_time, input wire rtc_valid,
    input wire state_start, input wire state_load,
    output wire state_start_ack, output wire state_start_busy, output wire state_start_ok, output wire state_start_err,
    output wire state_load_ack, output wire state_load_busy, output wire state_load_ok, output wire state_load_err,
    input wire in_menu, input wire [31:0] keys, input wire [31:0] joy,
    output wire [23:0] video_rgb, output wire video_de, output wire video_skip,
    output wire video_hs, output wire video_vs,
    output wire audio_mclk, output wire audio_lrck, output wire audio_dac,
    output wire [21:16] cram_a, inout wire [15:0] cram_dq,
    input wire cram_wait, output wire cram_clk, output wire cram_adv_n,
    output wire cram_cre, output wire cram_ce0_n, output wire cram_ce1_n,
    output wire cram_oe_n, output wire cram_we_n,
    output wire cram_ub_n, output wire cram_lb_n,
    output wire [16:0] sram_a, inout wire [15:0] sram_dq,
    output wire sram_oe_n, output wire sram_we_n,
    output wire sram_ub_n, output wire sram_lb_n
);
    // Power-up recovery is independent of host reset; assets arrive while
    // reset_n is low. Allow 1 ms for PSRAM initialization before APF setup.
    reg [16:0] power_count = 0;
    always @(posedge clk_bridge) begin
        if (!pll_locked) power_count <= 0;
        else if (!setup_done) power_count <= power_count + 1'b1;
    end
    assign setup_done = power_count == 74250;
    wire power_reset = !pll_locked;
    wire rom_idle, rom_overflow, cart_idle, cart_overflow, bios_idle, bios_overflow;
    assign rom_idle = cart_idle && bios_idle;
    assign rom_overflow = cart_overflow || bios_overflow;
    reg loading = 0, bios_loaded = 0;
    reg drain_pending = 0;
    reg [1:0] cart_loaded = 0;
    reg [20:0] cart1_mask = 0, cart2_mask = 0;
    reg [1:0] palette = 0;
    reg [23:0] power_hold = 0, sound_hold = 0, reset_hold = 0;
    wire cart_size_ok = slot_size >= 32768 && slot_size <= 2097152 &&
                       (slot_size & (slot_size-1)) == 0;
    assign slot_write_ok = ((slot_id == 0 || slot_id == 2) && cart_size_ok) ||
                          (slot_id == 1 && slot_size == 262144) ||
                          (slot_id == 3 && slot_size == 8192);
    always @(posedge clk_bridge) begin
        if (power_hold != 0) power_hold <= power_hold - 1'b1;
        if (sound_hold != 0) sound_hold <= sound_hold - 1'b1;
        if (reset_hold != 0) reset_hold <= reset_hold - 1'b1;
        if (all_complete) drain_pending <= 1;
        if (drain_pending && rom_idle) begin loading <= 0; drain_pending <= 0; end
        if (slot_write && slot_write_ok) begin
            loading <= 1;
            case (slot_id)
                0: begin cart_loaded[0] <= 1; cart1_mask <= slot_size[20:0] - 1'b1; end
                1: bios_loaded <= 1;
                2: begin cart_loaded[1] <= 1; cart2_mask <= slot_size[20:0] - 1'b1; end
                default: ;
            endcase
        end
        if (bridge_wr && bridge_addr[31:8] == 24'h400000) begin
            case (bridge_addr[7:0])
                8'h00: palette <= bridge_wr_data[1:0];
                8'h04: if (bridge_wr_data[0]) power_hold <= 24'd7425000;
                8'h08: if (bridge_wr_data[0]) sound_hold <= 24'd7425000;
                8'h0c: if (bridge_wr_data[0]) reset_hold <= 24'd74250;
                8'h10: if (bridge_wr_data[0]) begin cart_loaded[1] <= 0; reset_hold <= 74250; end
                default: ;
            endcase
        end
    end

    wire bridge_cart1 = bridge_addr[31:21] == 0;
    wire bridge_cart2 = bridge_addr[31:21] == 11'h100;
    wire bridge_bios = bridge_addr[31:18] == 14'h0400;
    wire bridge_save = bridge_addr[31:13] == 19'h18000;
    wire [22:0] load_addr = {1'b0, bridge_cart2, bridge_addr[20:0]};

    wire reset_request = !reset_n || !setup_done || loading ||
                         !bios_loaded || rom_overflow || reset_hold != 0;
    (* async_reg = "true" *) reg [2:0] reset_sync = 7;
    (* async_reg = "true" *) reg [1:0] menu_sync = 0;
    reg [47:0] config_meta = 0, config_sync = 0;
    reg [64:0] rtc_meta = 0, rtc_sync = 0;
    wire [64:0] rtc_payload = {rtc_valid, 16'd0, rtc_date[23:0], rtc_time[23:0]};
    always @(posedge clk_sys) begin
        reset_sync <= {reset_sync[1:0], reset_request};
        menu_sync <= {menu_sync[0], in_menu};
        config_meta <= {power_hold != 0, sound_hold != 0, palette,
                        cart_loaded, cart2_mask, cart1_mask};
        config_sync <= config_meta;
        rtc_meta <= rtc_payload; rtc_sync <= rtc_meta;
    end
    wire core_reset = reset_sync[2];
    reg [1:0] phase = 0;
    always @(posedge clk_sys) phase <= phase + 1'b1;
    wire phi0 = phase == 0;
    wire phi1 = phase == 2;
    wire [20:0] cart_addr;
    wire cart_rd, slot1_sel, slot2_sel;
    wire bios_sel = cart_addr < 21'h40000;
    wire slot2 = slot2_sel && !slot1_sel;
    wire present = bios_sel || (slot1_sel && config_sync[42]) || (slot2 && config_sync[43]);
    wire [20:0] cart_mirrored = cart_addr & (slot2 ? config_sync[41:21] : config_sync[20:0]);
    wire [22:0] physical_addr = bios_sel ? {5'b10000, cart_addr[17:0]} :
                                           {1'b0, slot2, cart_mirrored};
    wire rom_ready;
    wire [7:0] rom_data, bios_data;
    pocket_bios bios (
        .clk_bridge(clk_bridge), .reset(power_reset),
        .load_wr(bridge_wr && bridge_bios), .load_addr(bridge_addr[17:0]), .load_data(bridge_wr_data),
        .load_idle(bios_idle), .overflow(bios_overflow),
        .cpu_addr(cart_addr[17:0]), .cpu_data(bios_data),
        .sram_a(sram_a), .sram_dq(sram_dq), .sram_oe_n(sram_oe_n), .sram_we_n(sram_we_n),
        .sram_ub_n(sram_ub_n), .sram_lb_n(sram_lb_n)
    );
    pocket_rom rom (
        .clk_bridge(clk_bridge), .clk_sys(clk_sys), .reset(power_reset),
        .load_wr(bridge_wr && (bridge_cart1 || bridge_cart2)),
        .load_addr(load_addr), .load_data(bridge_wr_data),
        .load_idle(cart_idle), .overflow(cart_overflow),
        .invalidate(core_reset || state_pause), .cpu_rd(cart_rd && !bios_sel && present && !core_reset),
        .cpu_addr(physical_addr), .cpu_ready(rom_ready), .cpu_data(rom_data),
        .cram_a(cram_a), .cram_dq(cram_dq), .cram_wait(cram_wait),
        .cram_clk(cram_clk), .cram_adv_n(cram_adv_n), .cram_cre(cram_cre),
        .cram_ce0_n(cram_ce0_n), .cram_ce1_n(cram_ce1_n),
        .cram_oe_n(cram_oe_n), .cram_we_n(cram_we_n),
        .cram_ub_n(cram_ub_n), .cram_lb_n(cram_lb_n)
    );

    wire [12:0] save_addr;
    wire [7:0] save_data, save_q;
    wire save_rd, save_wr;
    reg [12:0] save_addr_hold = 0;
    always @(posedge clk_sys) if (save_rd || save_wr) save_addr_hold <= save_addr;
    reg [10:0] save_bridge_addr;
    always @(posedge clk_bridge) if (bridge_rd && bridge_save) save_bridge_addr <= bridge_addr[12:2];
    wire [31:0] save_bridge_q;
    pocket_save_ram nvram (
        .clk_bridge(clk_bridge),
        .bridge_addr(bridge_wr && bridge_save ? bridge_addr[12:2] : save_bridge_addr),
        .bridge_wr(bridge_wr && bridge_save), .bridge_data(bridge_wr_data),
        .bridge_q(save_bridge_q), .clk_sys(clk_sys),
        .cpu_addr(state_mem_active && state_mem_type == 0 ? state_mem_addr[12:0] :
                  (save_rd || save_wr ? save_addr : save_addr_hold)),
        .cpu_wr(state_mem_active && state_mem_type == 0 ? state_mem_wr : save_wr),
        .cpu_data(state_mem_active && state_mem_type == 0 ? state_mem_data : save_data), .cpu_q(save_q)
    );
    reg [31:0] last_read_addr;
    always @(posedge clk_bridge) if (bridge_rd) last_read_addr <= bridge_addr;
    always @* begin
        bridge_rd_data = 0;
        if (last_read_addr[31:28] == 3) bridge_rd_data = save_bridge_q;
        if (last_read_addr[31:28] == 5) bridge_rd_data = state_bridge_q;
        if (last_read_addr[31:8] == 24'h400000) begin
            case (last_read_addr[7:0])
                8'h00: bridge_rd_data = {30'd0, palette};
                8'h20: bridge_rd_data = {24'd0, 1'b0, core_reset, rom_overflow,
                                        loading, rom_idle, bios_loaded, cart_loaded};
                8'h24: bridge_rd_data = 32'h47434f4d;
                default: ;
            endcase
        end
    end
    wire state_pause_req, state_pause_ready;
    reg state_pause = 0;
    always @(posedge clk_sys) begin
        if (!state_pause_req || core_reset) state_pause <= 0;
        else if (state_pause_ready) state_pause <= 1;
    end
    wire state_mem_active, state_mem_rd, state_mem_wr;
    wire [2:0] state_mem_type;
    wire [24:0] state_mem_addr;
    wire [7:0] state_mem_data, state_core_q;
    wire [31:0] state_bridge_q;
    pocket_state memories (
        .clk_bridge(clk_bridge), .clk_sys(clk_sys), .reset(core_reset),
        .start(state_start), .load(state_load),
        .start_ack(state_start_ack), .start_busy(state_start_busy), .start_ok(state_start_ok), .start_err(state_start_err),
        .load_ack(state_load_ack), .load_busy(state_load_busy), .load_ok(state_load_ok), .load_err(state_load_err),
        .bridge_wr(bridge_wr && bridge_addr[31:15] == 17'h0a000),
        .bridge_rd(bridge_rd && bridge_addr[31:15] == 17'h0a000),
        .bridge_addr(bridge_addr[14:0]), .bridge_data(bridge_wr_data), .bridge_q(state_bridge_q),
        .pause_req(state_pause_req), .pause_ready(state_pause),
        .mem_active(state_mem_active), .mem_type(state_mem_type), .mem_addr(state_mem_addr),
        .mem_rd(state_mem_rd), .mem_wr(state_mem_wr), .mem_wdata(state_mem_data),
        .mem_q(state_mem_type == 0 ? save_q : state_core_q)
    );
    wire [11:0] buttons;
    wire touching, cursor;
    wire [3:0] touch_x, touch_y;
    pocket_input controls (
        .clk(clk_sys), .reset(core_reset), .in_menu(menu_sync[1]),
        .keys(keys), .joy(joy), .power_press(config_sync[47]), .sound_press(config_sync[46]),
        .buttons(buttons), .touching(touching), .cursor_visible(cursor),
        .touch_x(touch_x), .touch_y(touch_y)
    );
    wire ce, hb, vb, hs, vs;
    wire [2:0] shade;
    wire [15:0] pcm;
    GameCom #(.VIDEO_DIV(5), .DMA_ROM_WAIT(1'b1), .ENABLE_CHEATS(1'b0)) machine (
        .clk_sys(clk_sys), .phi0(phi0 && !state_pause), .phi1(phi1 && !state_pause), .clk_vid(clk_video),
        .reset(core_reset), .stop_disable_i(1'b0), .warm_boot_i(1'b0),
        .video_reset_i(!pll_locked),
        .cart_din_i(bios_sel ? bios_data : (present ? rom_data : 8'hff)),
        .rom_read_ready_i(bios_sel || !present || rom_ready),
        .uart_rxd_i(1'b1), .uart_cts_i(1'b1), .uart_dsr_i(1'b1),
        .buttons_i(buttons), .touch_active_i(touching), .touch_x_i(touch_x), .touch_y_i(touch_y),
        .video_60hz_i(1'b1), .palette_four_color_i(1'b0),
        .cursor_enable_i(cursor), .cursor_x_i(touch_x), .cursor_y_i(touch_y),
        .save_din_i(save_q), .rtc_i(rtc_sync),
        .savestate_pause_req_i(state_pause_req), .savestate_mem_active_i(state_mem_active && state_mem_type != 0),
        .savestate_mem_type_i(state_mem_type), .savestate_mem_addr_i(state_mem_addr),
        .savestate_mem_rd_i(state_mem_rd), .savestate_mem_wr_i(state_mem_wr),
        .savestate_mem_wdata_i(state_mem_data), .cheat_clear_i(core_reset), .cheat_code_i(129'd0),
        .ce_pix(ce), .HBlank(hb), .VBlank(vb), .HSync(hs), .VSync(vs), .shade(shade),
        .cart_addr_o(cart_addr), .cart_dout_o(), .cart_doe_o(), .cart_rd_o(cart_rd),
        .cart_wr_o(), .cart_slot1_sel_o(slot1_sel), .cart_slot2_sel_o(slot2_sel),
        .save_addr_o(save_addr), .save_dout_o(save_data), .save_rd_o(save_rd), .save_wren_o(save_wr),
        .cpu_sound_o(), .audio_pcm_o(pcm), .cpu_txdb_o(), .cpu_lcd_clk_o(),
        .cpu_doffb_o(), .uart_rts_o(), .uart_dtr_o(),
        .savestate_pause_ready_o(state_pause_ready), .savestate_mem_rdata_o(state_core_q)
    );
    (* async_reg = "true" *) reg [1:0] palette_meta, palette_video;
    always @(posedge clk_video) begin palette_meta <= palette; palette_video <= palette_meta; end
    pocket_video display (
        .clk(clk_video), .reset(!pll_locked), .ce(ce), .hblank(hb), .vblank(vb),
        .hs(hs), .vs(vs), .shade(shade), .palette(palette_video),
        .rgb(video_rgb), .de(video_de), .skip(video_skip), .out_hs(video_hs), .out_vs(video_vs)
    );
    pocket_audio sound (
        .clk_bridge(clk_bridge), .clk_sys(clk_sys), .reset(core_reset), .pcm_unsigned(pcm),
        .mclk(audio_mclk), .lrck(audio_lrck), .dac(audio_dac)
    );
endmodule
