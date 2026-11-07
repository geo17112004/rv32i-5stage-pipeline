`timescale 1ns/1ps
// ============================================================================
// rv32i_core.v - 5-stage pipelined RV32I core
//
//   IF -> ID -> EX -> MEM -> WB
//
//   Hazard handling
//   * Data hazards   : full forwarding EX/MEM->EX and MEM/WB->EX,
//                      register-file write-through bypass for WB->ID
//   * Load-use       : 1-cycle stall + bubble (hazard_unit)
//   * Control        : static predict-not-taken; branches/JAL/JALR resolve
//                      in EX, a taken redirect flushes IF/ID and ID/EX
//                      (2-cycle penalty)
//
//   ISA: all 37 RV32I user-level instructions except FENCE/ECALL/EBREAK,
//        which are decoded and executed as NOPs.
// ============================================================================
module rv32i_core #(
    parameter [31:0] RESET_PC = 32'h0000_0000
)(
    input  wire        clk,
    input  wire        rst,             // synchronous, active high

    // instruction memory
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,

    // data memory
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_we,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata,

    // performance counters
    output reg  [31:0] perf_cycles,
    output reg  [31:0] perf_instret,
    output reg  [31:0] perf_stalls,
    output reg  [31:0] perf_flushes
);
    localparam [31:0] NOP = 32'h0000_0013;   // addi x0, x0, 0

    // signals crossing stages (declared early)
    wire        load_use_stall;
    wire        ex_redirect;
    wire [31:0] ex_target;

    // ========================================================================
    // IF stage
    // ========================================================================
    reg  [31:0] pc;
    wire [31:0] pc_plus4 = pc + 32'd4;

    assign imem_addr = pc;

    always @(posedge clk) begin
        if (rst)                 pc <= RESET_PC;
        else if (ex_redirect)    pc <= ex_target;      // flush wins over stall
        else if (!load_use_stall) pc <= pc_plus4;
    end

    // IF/ID pipeline register
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;
    reg        if_id_valid;

    always @(posedge clk) begin
        if (rst || ex_redirect) begin
            if_id_pc    <= 32'd0;
            if_id_instr <= NOP;
            if_id_valid <= 1'b0;
        end else if (!load_use_stall) begin
            if_id_pc    <= pc;
            if_id_instr <= imem_rdata;
            if_id_valid <= 1'b1;
        end
    end

    // ========================================================================
    // ID stage
    // ========================================================================
    wire [6:0] id_opcode = if_id_instr[6:0];
    wire [4:0] id_rd     = if_id_instr[11:7];
    wire [2:0] id_funct3 = if_id_instr[14:12];
    wire [4:0] id_rs1    = if_id_instr[19:15];
    wire [4:0] id_rs2    = if_id_instr[24:20];
    wire [6:0] id_funct7 = if_id_instr[31:25];

    wire        id_reg_write, id_mem_read, id_mem_write, id_b_sel;
    wire        id_branch, id_jal, id_jalr, id_uses_rs1, id_uses_rs2;
    wire [1:0]  id_wb_sel, id_a_sel;
    wire [3:0]  id_alu_op;
    wire [31:0] id_imm;
    wire [31:0] id_rs1_data, id_rs2_data;

    control u_control (
        .opcode    (id_opcode),
        .funct3    (id_funct3),
        .funct7    (id_funct7),
        .reg_write (id_reg_write),
        .mem_read  (id_mem_read),
        .mem_write (id_mem_write),
        .wb_sel    (id_wb_sel),
        .a_sel     (id_a_sel),
        .b_sel     (id_b_sel),
        .alu_op    (id_alu_op),
        .branch    (id_branch),
        .jal       (id_jal),
        .jalr      (id_jalr),
        .uses_rs1  (id_uses_rs1),
        .uses_rs2  (id_uses_rs2)
    );

    imm_gen u_imm_gen (
        .instr (if_id_instr),
        .imm   (id_imm)
    );

    // WB-stage write port (driven further below)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_data;

    regfile u_regfile (
        .clk    (clk),
        .we     (wb_reg_write),
        .waddr  (wb_rd),
        .wdata  (wb_data),
        .raddr1 (id_rs1),
        .raddr2 (id_rs2),
        .rdata1 (id_rs1_data),
        .rdata2 (id_rs2_data)
    );

    // ID/EX pipeline register
    reg [31:0] id_ex_pc, id_ex_instr, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    reg [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    reg [2:0]  id_ex_funct3;
    reg [3:0]  id_ex_alu_op;
    reg [1:0]  id_ex_wb_sel, id_ex_a_sel;
    reg        id_ex_b_sel, id_ex_reg_write, id_ex_mem_read, id_ex_mem_write;
    reg        id_ex_branch, id_ex_jal, id_ex_jalr, id_ex_valid;

    always @(posedge clk) begin
        if (rst || ex_redirect || load_use_stall) begin
            // bubble: no architectural side effects
            id_ex_valid     <= 1'b0;
            id_ex_reg_write <= 1'b0;
            id_ex_mem_read  <= 1'b0;
            id_ex_mem_write <= 1'b0;
            id_ex_branch    <= 1'b0;
            id_ex_jal       <= 1'b0;
            id_ex_jalr      <= 1'b0;
            id_ex_rd        <= 5'd0;
            id_ex_rs1       <= 5'd0;
            id_ex_rs2       <= 5'd0;
            id_ex_pc        <= 32'd0;
            id_ex_instr     <= NOP;
            id_ex_rs1_data  <= 32'd0;
            id_ex_rs2_data  <= 32'd0;
            id_ex_imm       <= 32'd0;
            id_ex_funct3    <= 3'd0;
            id_ex_alu_op    <= 4'd0;
            id_ex_wb_sel    <= 2'd0;
            id_ex_a_sel     <= 2'd0;
            id_ex_b_sel     <= 1'b0;
        end else begin
            id_ex_valid     <= if_id_valid;
            id_ex_reg_write <= id_reg_write;
            id_ex_mem_read  <= id_mem_read;
            id_ex_mem_write <= id_mem_write;
            id_ex_branch    <= id_branch;
            id_ex_jal       <= id_jal;
            id_ex_jalr      <= id_jalr;
            id_ex_rd        <= id_rd;
            id_ex_rs1       <= id_uses_rs1 ? id_rs1 : 5'd0;
            id_ex_rs2       <= id_uses_rs2 ? id_rs2 : 5'd0;
            id_ex_pc        <= if_id_pc;
            id_ex_instr     <= if_id_instr;
            id_ex_rs1_data  <= id_rs1_data;
            id_ex_rs2_data  <= id_rs2_data;
            id_ex_imm       <= id_imm;
            id_ex_funct3    <= id_funct3;
            id_ex_alu_op    <= id_alu_op;
            id_ex_wb_sel    <= id_wb_sel;
            id_ex_a_sel     <= id_a_sel;
            id_ex_b_sel     <= id_b_sel;
        end
    end

    hazard_unit u_hazard (
        .id_rs1         (id_rs1),
        .id_rs2         (id_rs2),
        .id_uses_rs1    (id_uses_rs1),
        .id_uses_rs2    (id_uses_rs2),
        .id_ex_mem_read (id_ex_mem_read),
        .id_ex_rd       (id_ex_rd),
        .load_use_stall (load_use_stall)
    );

    // ========================================================================
    // EX stage
    // ========================================================================
    // EX/MEM registers declared here because forwarding reads them
    reg [31:0] ex_mem_pc, ex_mem_instr, ex_mem_result, ex_mem_store_data;
    reg [4:0]  ex_mem_rd;
    reg [2:0]  ex_mem_funct3;
    reg        ex_mem_reg_write, ex_mem_mem_read, ex_mem_mem_write, ex_mem_valid;

    reg [31:0] mem_wb_pc, mem_wb_instr, mem_wb_data;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write, mem_wb_valid;

    wire [1:0] fwd_a, fwd_b;

    forwarding_unit u_fwd (
        .id_ex_rs1        (id_ex_rs1),
        .id_ex_rs2        (id_ex_rs2),
        .ex_mem_rd        (ex_mem_rd),
        .ex_mem_reg_write (ex_mem_reg_write),
        .mem_wb_rd        (mem_wb_rd),
        .mem_wb_reg_write (mem_wb_reg_write),
        .fwd_a            (fwd_a),
        .fwd_b            (fwd_b)
    );

    wire [31:0] ex_rs1 = (fwd_a == 2'b10) ? ex_mem_result :
                         (fwd_a == 2'b01) ? mem_wb_data   : id_ex_rs1_data;
    wire [31:0] ex_rs2 = (fwd_b == 2'b10) ? ex_mem_result :
                         (fwd_b == 2'b01) ? mem_wb_data   : id_ex_rs2_data;

    wire [31:0] alu_a = (id_ex_a_sel == 2'd1) ? id_ex_pc :
                        (id_ex_a_sel == 2'd2) ? 32'd0    : ex_rs1;
    wire [31:0] alu_b = id_ex_b_sel ? id_ex_imm : ex_rs2;
    wire [31:0] alu_y;

    alu u_alu (
        .a  (alu_a),
        .b  (alu_b),
        .op (id_ex_alu_op),
        .y  (alu_y)
    );

    wire br_cond;
    branch_unit u_branch (
        .a      (ex_rs1),
        .b      (ex_rs2),
        .funct3 (id_ex_funct3),
        .taken  (br_cond)
    );

    wire [31:0] ex_pc_plus4 = id_ex_pc + 32'd4;
    wire [31:0] ex_result   = (id_ex_wb_sel == 2'd2) ? ex_pc_plus4 : alu_y;

    assign ex_redirect = (id_ex_branch & br_cond) | id_ex_jal | id_ex_jalr;
    assign ex_target   = id_ex_jalr ? (alu_y & 32'hFFFF_FFFE)
                                    : (id_ex_pc + id_ex_imm);

    // EX/MEM pipeline register
    always @(posedge clk) begin
        if (rst) begin
            ex_mem_valid      <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_rd         <= 5'd0;
            ex_mem_result     <= 32'd0;
            ex_mem_store_data <= 32'd0;
            ex_mem_funct3     <= 3'd0;
            ex_mem_pc         <= 32'd0;
            ex_mem_instr      <= NOP;
        end else begin
            ex_mem_valid      <= id_ex_valid;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_result     <= ex_result;
            ex_mem_store_data <= ex_rs2;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_pc         <= id_ex_pc;
            ex_mem_instr      <= id_ex_instr;
        end
    end

    // ========================================================================
    // MEM stage
    // ========================================================================
    wire [1:0] byte_off = ex_mem_result[1:0];

    reg [3:0]  st_strb;
    reg [31:0] st_data;
    always @(*) begin
        case (ex_mem_funct3[1:0])
            2'b00: begin                                   // SB
                st_strb = 4'b0001 << byte_off;
                st_data = {4{ex_mem_store_data[7:0]}};
            end
            2'b01: begin                                   // SH
                st_strb = byte_off[1] ? 4'b1100 : 4'b0011;
                st_data = {2{ex_mem_store_data[15:0]}};
            end
            default: begin                                 // SW
                st_strb = 4'b1111;
                st_data = ex_mem_store_data;
            end
        endcase
    end

    assign dmem_addr  = {ex_mem_result[31:2], 2'b00};
    assign dmem_wdata = st_data;
    assign dmem_wstrb = st_strb;
    assign dmem_we    = ex_mem_mem_write;
    assign dmem_re    = ex_mem_mem_read;

    wire [31:0] ld_shift = dmem_rdata >> {byte_off, 3'b000};
    reg  [31:0] ld_data;
    always @(*) begin
        case (ex_mem_funct3)
            3'b000:  ld_data = {{24{ld_shift[7]}},  ld_shift[7:0]};   // LB
            3'b001:  ld_data = {{16{ld_shift[15]}}, ld_shift[15:0]};  // LH
            3'b100:  ld_data = {24'd0, ld_shift[7:0]};                // LBU
            3'b101:  ld_data = {16'd0, ld_shift[15:0]};               // LHU
            default: ld_data = dmem_rdata;                            // LW
        endcase
    end

    wire [31:0] mem_result = ex_mem_mem_read ? ld_data : ex_mem_result;

    // MEM/WB pipeline register
    always @(posedge clk) begin
        if (rst) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_reg_write <= 1'b0;
            mem_wb_rd        <= 5'd0;
            mem_wb_data      <= 32'd0;
            mem_wb_pc        <= 32'd0;
            mem_wb_instr     <= NOP;
        end else begin
            mem_wb_valid     <= ex_mem_valid;
            mem_wb_reg_write <= ex_mem_reg_write;
            mem_wb_rd        <= ex_mem_rd;
            mem_wb_data      <= mem_result;
            mem_wb_pc        <= ex_mem_pc;
            mem_wb_instr     <= ex_mem_instr;
        end
    end

    // ========================================================================
    // WB stage
    // ========================================================================
    assign wb_reg_write = mem_wb_reg_write;
    assign wb_rd        = mem_wb_rd;
    assign wb_data      = mem_wb_data;

    // ========================================================================
    // Performance counters
    // ========================================================================
    always @(posedge clk) begin
        if (rst) begin
            perf_cycles  <= 32'd0;
            perf_instret <= 32'd0;
            perf_stalls  <= 32'd0;
            perf_flushes <= 32'd0;
        end else begin
            perf_cycles <= perf_cycles + 32'd1;
            if (mem_wb_valid)                    perf_instret <= perf_instret + 32'd1;
            if (load_use_stall && !ex_redirect)  perf_stalls  <= perf_stalls  + 32'd1;
            if (ex_redirect)                     perf_flushes <= perf_flushes + 32'd1;
        end
    end
endmodule
