`timescale 1ns/1ps
// A new numbered, coordinate-dependent image on every native frame proves
// delivery cadence, complete frames, pixel ordering and absence of tearing.
module video_cadence_tb;
    reg clk_sys = 0, clk_vid = 0, reset = 1, measure = 0, run_source = 1;
    // Common timebase preserves the PLL's exact 2:3 clock relationship.
    // Separate rounded delays would drift through unsafe sampling phases.
    integer tick = 11;
    always #8.333 begin
        tick = (tick + 1) % 12;
        clk_sys = (tick % 6) < 3;
        clk_vid = (tick % 4) < 2;
    end
    reg [1:0] phase = 0;
    always @(posedge clk_sys)
        if (reset) phase <= 0;
        else phase <= phase + 1'b1;
    wire ce_pix = run_source && phase == 0;
    wire [12:0] vram_addr;
    reg [7:0] vram_data = 0;
    wire ce_out, hblank, vblank, native_vblank;
    wire [2:0] shade;
    integer source_id = 1;
    reg prev_native_blank = 1;
    integer native_frames = 0, captures = 0, outputs = 0, fresh = 0, repeats = 0;
    integer pixels = 0, decoded_id = 0, previous_id = -1, checked_frames = 0;
    integer x, y, value, expected, step;
    integer single_steps = 0, double_steps = 0;
    integer completions = 0, presentations = 0, simultaneous = 0;
    reg prev_blank = 1;

    function automatic [1:0] pixel_value(input integer id, px, py);
        pixel_value = 2'((id >> ((px % 8) * 2)) ^ py ^ (px / 8));
    endfunction
    always @(posedge clk_sys) begin
        // Match the actual VRAM's synchronous read and rotated byte layout.
        for (integer i = 0; i < 4; i++)
            vram_data[7-i*2 -: 2] <= pixel_value(source_id, int'(vram_addr)/40,
                                                               (int'(vram_addr)%40)*4+i);
        if (reset) begin
            source_id <= 1;
            prev_native_blank <= 1;
        end else if (ce_pix) begin
            prev_native_blank <= native_vblank;
            if (native_vblank && !prev_native_blank) begin
                source_id <= source_id + 1;
                if (measure) native_frames++;
            end
            if (measure && dut.native_frame_end_w && dut.capture_active_q) captures++;
        end
    end
    gamecom_video #(.TV60_DIV(5)) dut (
        .clk_sys_i(clk_sys), .clk_vid_i(clk_vid), .ce_pix_i(ce_pix),
        .reset_i(reset), .display_enable_i(1'b1), .display_page_req_i(1'b0),
        .display_palette_i(2'b00), .display_normal_black_i(1'b0),
        .palette_four_color_i(1'b1), .video_60hz_i(1'b1), .stop_mode_i(1'b0),
        .cursor_enable_i(1'b0), .cursor_x_i(4'd0), .cursor_y_i(4'd0),
        .vram0_din_i(vram_data), .vram1_din_i(vram_data),
        .vram_addr_o(vram_addr), .ce_pix_o(ce_out), .hblank_o(hblank), .hsync_o(),
        .vblank_o(vblank), .native_vblank_o(native_vblank), .vsync_o(), .shade_o(shade)
    );
    always @(posedge clk_vid) if (!reset && ce_out) begin
        if (!vblank && !hblank && dut.fb_display_valid_q) begin
            x = pixels % 200;
            y = pixels / 200;
            if (shade < 1 || shade > 4) $fatal(1, "Invalid active shade %0d at (%0d,%0d), native %0d", shade, x, y, source_id);
            value = 4 - int'(shade);
            if (y == 0 && x < 8) decoded_id = decoded_id | (value << (x * 2));
            else begin
                expected = int'(pixel_value(decoded_id, x, y));
                if (value != expected)
                    $fatal(1, "Torn/corrupt frame %0d pixel (%0d,%0d): %0d expected %0d",
                           decoded_id, x, y, value, expected);
            end
            pixels++;
        end
        if (vblank && !prev_blank) begin
            if (pixels != 0) begin
                if (pixels != 32000) $fatal(1, "Incomplete frame: %0d pixels", pixels);
                checked_frames++;
                if (measure) begin
                    outputs++;
                    step = decoded_id - previous_id;
                    if (step == 0) repeats++;
                    else begin
                        fresh++;
                        if (step == 1) single_steps++;
                        else if (step == 2) double_steps++;
                        else $fatal(1, "Unexpected source-frame jump %0d", step);
                    end
                end
                previous_id = decoded_id;
            end
            pixels = 0;
            decoded_id = 0;
        end
        prev_blank = vblank;
    end
    always @(posedge clk_vid) if (!reset && dut.vid60_s2_q) begin
        if (dut.fb_write_buf_q > 2 || dut.fb_ready_buf_q > 2 || dut.fb_display_buf_q > 2 ||
            dut.fb_write_buf_q == dut.fb_ready_buf_q ||
            dut.fb_write_buf_q == dut.fb_display_buf_q ||
            dut.fb_ready_buf_q == dut.fb_display_buf_q)
            $fatal(1, "Framebuffer ownership overlap");
        if (dut.fb_complete_w) completions++;
        if (dut.fb_present_w) presentations++;
        if (dut.fb_complete_w && dut.fb_present_w) simultaneous++;
    end
    always @(posedge clk_vid) if ($test$plusargs("TRACE") && dut.fb_wren_w && dut.fb_waddr_q < 8)
        $display("WRITE %0t addr=%0d shade=%0d", $time, dut.fb_waddr_q, dut.fb_wdata_q);
    integer reset_delay = 1000;
    initial begin
        if ($value$plusargs("RESET_NS=%d", reset_delay)) begin end
        #(reset_delay);
        @(negedge clk_sys); reset = 0;
        #100000000; // Warm up for 100 ms.
        measure = 1;
        #1000000000;
        measure = 0;
        $display("One second: native=%0d captured=%0d output=%0d fresh=%0d repeated=%0d",
                 native_frames, captures, outputs, fresh, repeats);
        $display("Source-frame advances: one=%0d two=%0d; intact frames=%0d",
                 single_steps, double_steps, checked_frames);
        if (native_frames < 75 || native_frames > 76 || outputs < 60 || outputs > 61)
            $fatal(1, "Unexpected raster cadence");
        if (repeats != 0 || fresh != outputs || captures != native_frames)
            $fatal(1, "Converter unnecessarily skipped or repeated a frame");
        // Exercise the rare same-clock completion/presentation race. Insert
        // an early presentation boundary inside real output blanking, while
        // a real complete source frame arrives. Active pixels stay checked.
        // A system rising edge can coincide with a video falling edge;
        // let its nonblocking assignments settle before choosing the pulse.
        do begin
            @(negedge clk_vid);
            #0.001;
        end while (!(dut.fb_complete_w && vblank));
        force dut.fb_present_w = 1'b1;
        @(negedge clk_vid);
        release dut.fb_present_w;
        if (simultaneous == 0) $fatal(1, "Simultaneous handoff was not exercised");
        #100000000;
        // Memories pauses the source while the output clock keeps running.
        // Retained and resumed images must still be complete and coherent.
        @(negedge clk_sys); run_source = 0;
        #50000000;
        @(negedge clk_sys); run_source = 1;
        #100000000;
        outputs = 0; fresh = 0; repeats = 0;
        measure = 1;
        #200000000;
        measure = 0;
        if (repeats != 0 || fresh != outputs || outputs < 12)
            $fatal(1, "Frame delivery did not recover after source pause");
        $display("PASS: pause/resume fresh=%0d repeated=%0d; %0d complete frames checked",
                 fresh, repeats, checked_frames);
        $display("Handoffs: completed=%0d presented=%0d simultaneous=%0d",
                 completions, presentations, simultaneous);
        $finish;
    end
    initial begin #5000000000; $fatal(1, "Video regression timeout"); end
endmodule
