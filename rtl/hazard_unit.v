`timescale 1ns/1ps
// ============================================================================
// hazard_unit.v - Load-use hazard detection
//   If the instruction in EX is a load whose destination is a source of the
//   instruction in ID, the value is not available in time for forwarding.
//   -> stall PC and IF/ID for one cycle and inject a bubble into ID/EX.
//   After the stall the loaded value is forwarded from MEM/WB.
// ============================================================================
module hazard_unit (
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_uses_rs1,
    input  wire       id_uses_rs2,
    input  wire       id_ex_mem_read,
    input  wire [4:0] id_ex_rd,
    output wire       load_use_stall
);
    assign load_use_stall = id_ex_mem_read && (id_ex_rd != 5'd0) &&
                            ((id_uses_rs1 && (id_ex_rd == id_rs1)) ||
                             (id_uses_rs2 && (id_ex_rd == id_rs2)));
endmodule
