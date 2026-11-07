`timescale 1ns/1ps
// ============================================================================
// imm_gen.v - Immediate generator for I, S, B, U and J formats
// ============================================================================
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;

    always @(*) begin
        case (instr[6:0])
            OP_IMM, OP_LOAD, OP_JALR:                       // I-type
                imm = {{20{instr[31]}}, instr[31:20]};
            OP_STORE:                                       // S-type
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            OP_BRANCH:                                      // B-type
                imm = {{19{instr[31]}}, instr[31], instr[7],
                       instr[30:25], instr[11:8], 1'b0};
            OP_LUI, OP_AUIPC:                               // U-type
                imm = {instr[31:12], 12'd0};
            OP_JAL:                                         // J-type
                imm = {{11{instr[31]}}, instr[31], instr[19:12],
                       instr[20], instr[30:21], 1'b0};
            default:
                imm = 32'd0;
        endcase
    end
endmodule
