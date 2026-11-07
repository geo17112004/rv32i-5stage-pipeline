`timescale 1ns/1ps
// ============================================================================
// dmem.v - Data memory with byte write strobes
//   Synchronous write, asynchronous read. Byte/half alignment and sign
//   extension are handled in the core's MEM stage.
// ============================================================================
module dmem #(
    parameter ADDR_W = 10              // 2^10 words = 4 KB
)(
    input  wire        clk,
    input  wire        we,
    input  wire [3:0]  wstrb,
    input  wire [31:0] addr,
    input  wire [31:0] wdata,
    output wire [31:0] rdata
);
    reg [31:0] mem [0:(1<<ADDR_W)-1];
    wire [ADDR_W-1:0] idx = addr[ADDR_W+1:2];

    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1) mem[i] = 32'd0;
    end

    always @(posedge clk) begin
        if (we) begin
            if (wstrb[0]) mem[idx][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[idx][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[idx][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[idx][31:24] <= wdata[31:24];
        end
    end

    assign rdata = mem[idx];
endmodule
