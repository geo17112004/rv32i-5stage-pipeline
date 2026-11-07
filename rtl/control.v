`timescale 1ns/1ps
// ============================================================================
// control.v - Main decoder for the RV32I base integer ISA
// ============================================================================
module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg  [1:0] wb_sel,     // 0: ALU result, 1: load data, 2: PC+4
    output reg  [1:0] a_sel,      // 0: rs1, 1: PC, 2: zero
    output reg        b_sel,      // 0: rs2, 1: immediate
    output reg  [3:0] alu_op,
    output reg        branch,
    output reg        jal,
    output reg        jalr,
    output reg        uses_rs1,
    output reg        uses_rs2
);
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;

    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_SLL  = 4'd2;
    localparam ALU_SLT  = 4'd3;
    localparam ALU_SLTU = 4'd4;
    localparam ALU_XOR  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_OR   = 4'd8;
    localparam ALU_AND  = 4'd9;

    // funct3 -> ALU operation (alt selects SUB / SRA)
    function [3:0] alu_decode;
        input [2:0] f3;
        input       alt;
        begin
            case (f3)
                3'b000: alu_decode = alt ? ALU_SUB : ALU_ADD;
                3'b001: alu_decode = ALU_SLL;
                3'b010: alu_decode = ALU_SLT;
                3'b011: alu_decode = ALU_SLTU;
                3'b100: alu_decode = ALU_XOR;
                3'b101: alu_decode = alt ? ALU_SRA : ALU_SRL;
                3'b110: alu_decode = ALU_OR;
                default: alu_decode = ALU_AND;
            endcase
        end
    endfunction

    always @(*) begin
        // defaults = NOP (FENCE / ECALL / EBREAK / unknown decode to NOP)
        reg_write = 1'b0;  mem_read = 1'b0;  mem_write = 1'b0;
        wb_sel    = 2'd0;  a_sel    = 2'd0;  b_sel     = 1'b0;
        alu_op    = ALU_ADD;
        branch    = 1'b0;  jal      = 1'b0;  jalr      = 1'b0;
        uses_rs1  = 1'b0;  uses_rs2 = 1'b0;

        case (opcode)
            OP_LUI: begin
                reg_write = 1'b1; a_sel = 2'd2; b_sel = 1'b1;
            end
            OP_AUIPC: begin
                reg_write = 1'b1; a_sel = 2'd1; b_sel = 1'b1;
            end
            OP_JAL: begin
                reg_write = 1'b1; wb_sel = 2'd2; jal = 1'b1;
            end
            OP_JALR: begin
                reg_write = 1'b1; wb_sel = 2'd2; jalr = 1'b1;
                b_sel = 1'b1; uses_rs1 = 1'b1;
            end
            OP_BRANCH: begin
                branch = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
            end
            OP_LOAD: begin
                reg_write = 1'b1; mem_read = 1'b1; wb_sel = 2'd1;
                b_sel = 1'b1; uses_rs1 = 1'b1;
            end
            OP_STORE: begin
                mem_write = 1'b1; b_sel = 1'b1;
                uses_rs1 = 1'b1; uses_rs2 = 1'b1;
            end
            OP_IMM: begin
                reg_write = 1'b1; b_sel = 1'b1; uses_rs1 = 1'b1;
                // only SRAI uses funct7[5]; ADDI never subtracts
                alu_op = alu_decode(funct3, (funct3 == 3'b101) & funct7[5]);
            end
            OP_REG: begin
                reg_write = 1'b1; uses_rs1 = 1'b1; uses_rs2 = 1'b1;
                alu_op = alu_decode(funct3, funct7[5]);
            end
            default: ;
        endcase
    end
endmodule
