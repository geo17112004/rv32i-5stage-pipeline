`timescale 1ns/1ps
// ============================================================================
// forwarding_unit.v - Resolves RAW data hazards by bypassing results into EX
//   sel = 2'b00 : value read from register file (ID/EX)
//   sel = 2'b10 : forward from EX/MEM (instruction 1 ahead)  - higher priority
//   sel = 2'b01 : forward from MEM/WB (instruction 2 ahead)
// ============================================================================
module forwarding_unit (
    input  wire [4:0] id_ex_rs1,
    input  wire [4:0] id_ex_rs2,
    input  wire [4:0] ex_mem_rd,
    input  wire       ex_mem_reg_write,
    input  wire [4:0] mem_wb_rd,
    input  wire       mem_wb_reg_write,
    output reg  [1:0] fwd_a,
    output reg  [1:0] fwd_b
);
    always @(*) begin
        // operand A
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1))
            fwd_a = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1))
            fwd_a = 2'b01;
        else
            fwd_a = 2'b00;

        // operand B
        if (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2))
            fwd_b = 2'b10;
        else if (mem_wb_reg_write && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2))
            fwd_b = 2'b01;
        else
            fwd_b = 2'b00;
    end
endmodule
