`timescale 1ns/1ps
// ============================================================================
// imem.v - Instruction memory (word addressed, asynchronous read)
// ============================================================================
module imem #(
    parameter ADDR_W    = 10,          // 2^10 words = 4 KB
    parameter INIT_FILE = ""
)(
    input  wire [31:0] addr,
    output wire [31:0] rdata
);
    reg [31:0] mem [0:(1<<ADDR_W)-1];

    integer i;
    initial begin
        for (i = 0; i < (1<<ADDR_W); i = i + 1) mem[i] = 32'h0000_0013; // NOP
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    assign rdata = mem[addr[ADDR_W+1:2]];
endmodule
