// SPDX-License-Identifier: GPL-2.0-or-later
// 8 KB console NVRAM. Four byte lanes give APF atomic 32-bit accesses while
// preserving the CPU's synchronous byte-wide RAM interface.
module pocket_save_ram #(parameter ADDR_WIDTH = 13) (
    input wire clk_bridge, input wire [ADDR_WIDTH-3:0] bridge_addr,
    input wire bridge_wr, input wire [31:0] bridge_data,
    output wire [31:0] bridge_q,
    input wire clk_sys, input wire [ADDR_WIDTH-1:0] cpu_addr,
    input wire cpu_wr, input wire [7:0] cpu_data,
    output wire [7:0] cpu_q
);
    reg [1:0] cpu_lane;
    wire [31:0] cpu_words;
    always @(posedge clk_sys) cpu_lane <= cpu_addr[1:0];
    assign cpu_q = cpu_words[cpu_lane * 8 +: 8];
    genvar lane;
    generate for (lane = 0; lane < 4; lane = lane + 1) begin : lanes
`ifdef ALTERA_RESERVED_QIS
        altsyncram #(
            .operation_mode("BIDIR_DUAL_PORT"), .intended_device_family("Cyclone V"),
            .width_a(8), .widthad_a(ADDR_WIDTH-2), .numwords_a(1 << (ADDR_WIDTH-2)),
            .width_b(8), .widthad_b(ADDR_WIDTH-2), .numwords_b(1 << (ADDR_WIDTH-2)),
            .width_byteena_a(1), .width_byteena_b(1),
            .outdata_reg_a("UNREGISTERED"), .outdata_reg_b("UNREGISTERED"),
            .address_reg_b("CLOCK1"), .indata_reg_b("CLOCK1"),
            .wrcontrol_wraddress_reg_b("CLOCK1"), .byteena_reg_b("CLOCK1"),
            .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
            .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
            .read_during_write_mode_mixed_ports("DONT_CARE"),
            .power_up_uninitialized("FALSE"), .lpm_type("altsyncram")
        ) ram (
            .clock0(clk_bridge), .clock1(clk_sys),
            .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
            .aclr0(1'b0), .aclr1(1'b0), .byteena_a(1'b1), .byteena_b(1'b1),
            .address_a(bridge_addr), .data_a(bridge_data[lane*8 +: 8]), .wren_a(bridge_wr),
            .rden_a(1'b1), .q_a(bridge_q[lane*8 +: 8]),
            .address_b(cpu_addr[ADDR_WIDTH-1:2]), .data_b(cpu_data),
            .wren_b(cpu_wr && cpu_addr[1:0] == lane), .rden_b(1'b1),
            .q_b(cpu_words[lane*8 +: 8]), .eccstatus()
        );
`else
        (* ramstyle = "M10K, no_rw_check" *) reg [7:0] mem [0:(1 << (ADDR_WIDTH-2))-1];
        reg [7:0] bridge_out, cpu_out;
        integer i;
        initial for (i=0; i<(1 << (ADDR_WIDTH-2)); i=i+1) mem[i] = 0;
        always @(posedge clk_bridge) begin
            if (bridge_wr) mem[bridge_addr] <= bridge_data[lane*8 +: 8];
            bridge_out <= mem[bridge_addr];
        end
        always @(posedge clk_sys) begin
            if (cpu_wr && cpu_addr[1:0] == lane)
                mem[cpu_addr[ADDR_WIDTH-1:2]] <= cpu_data;
            cpu_out <= mem[cpu_addr[ADDR_WIDTH-1:2]];
        end
        assign bridge_q[lane*8 +: 8] = bridge_out;
        assign cpu_words[lane*8 +: 8] = cpu_out;
`endif
    end endgenerate
endmodule
