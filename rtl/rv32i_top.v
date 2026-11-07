`timescale 1ns/1ps
// ============================================================================
// rv32i_top.v - Core + instruction memory + data memory
// ============================================================================
module rv32i_top #(
    parameter IMEM_ADDR_W = 10,
    parameter DMEM_ADDR_W = 10,
    parameter IMEM_INIT   = ""
)(
    input  wire clk,
    input  wire rst
);
    wire [31:0] imem_addr, imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire [3:0]  dmem_wstrb;
    wire        dmem_we, dmem_re;
    wire [31:0] perf_cycles, perf_instret, perf_stalls, perf_flushes;

    rv32i_core u_core (
        .clk          (clk),
        .rst          (rst),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_wstrb   (dmem_wstrb),
        .dmem_we      (dmem_we),
        .dmem_re      (dmem_re),
        .dmem_rdata   (dmem_rdata),
        .perf_cycles  (perf_cycles),
        .perf_instret (perf_instret),
        .perf_stalls  (perf_stalls),
        .perf_flushes (perf_flushes)
    );

    imem #(.ADDR_W(IMEM_ADDR_W), .INIT_FILE(IMEM_INIT)) u_imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    dmem #(.ADDR_W(DMEM_ADDR_W)) u_dmem (
        .clk   (clk),
        .we    (dmem_we),
        .wstrb (dmem_wstrb),
        .addr  (dmem_addr),
        .wdata (dmem_wdata),
        .rdata (dmem_rdata)
    );
endmodule
