// ============================================================================
// tb_top.v - Testbench for the 5-stage RV32I core
//
//   Plusargs
//     +HEX=<file>   program to load (default sw/test_all.hex)
//     +TRACE        print every retired instruction
//     +VCD          dump wave.vcd (for GTKWave)
//
//   The program signals completion by storing to TOHOST (0x7FC):
//     value 1 -> PASS, anything else -> FAIL (value = failing test number)
// ============================================================================
`timescale 1ns/1ps

module tb_top;
    localparam [31:0] TOHOST     = 32'h0000_07FC;
    localparam integer MAX_CYCLES = 200000;

    reg clk = 1'b0;
    reg rst = 1'b1;
    always #5 clk = ~clk;                 // 100 MHz

    rv32i_top dut (
        .clk (clk),
        .rst (rst)
    );

    reg [8*256-1:0] hexfile;
    reg             trace;

    initial begin
        if (!$value$plusargs("HEX=%s", hexfile))
            hexfile = "sw/test_all.hex";
        trace = $test$plusargs("TRACE");
        #1;   // let imem's own initial block (NOP fill) run first
        $readmemh(hexfile, dut.u_imem.mem);
        if ($test$plusargs("VCD")) begin
            $dumpfile("wave.vcd");
            $dumpvars(0, tb_top);
        end
        $display("--------------------------------------------------------");
        $display(" RV32I 5-stage pipeline  |  program: %0s", hexfile);
        $display("--------------------------------------------------------");
        repeat (3) @(posedge clk);
        rst <= 1'b0;
    end

    // ---------------------------------------------------------------- trace
    always @(posedge clk) begin
        if (!rst && trace && dut.u_core.mem_wb_valid) begin
            if (dut.u_core.mem_wb_reg_write && dut.u_core.mem_wb_rd != 5'd0)
                $display("[%6t] pc=%08h  instr=%08h  x%0d <= %08h",
                         $time, dut.u_core.mem_wb_pc, dut.u_core.mem_wb_instr,
                         dut.u_core.mem_wb_rd, dut.u_core.mem_wb_data);
            else
                $display("[%6t] pc=%08h  instr=%08h",
                         $time, dut.u_core.mem_wb_pc, dut.u_core.mem_wb_instr);
        end
    end

    // --------------------------------------------------- end-of-test monitor
    task report;
        input integer pass;
        real cpi;
        begin
            // instret counts instructions in WB; include the TOHOST store
            // that is currently in MEM
            cpi = (dut.u_core.perf_instret + 1 > 0) ?
                  (1.0 * dut.u_core.perf_cycles) / (dut.u_core.perf_instret + 1) : 0.0;
            $display("--------------------------------------------------------");
            if (pass)
                $display(" RESULT : *** PASS ***");
            else
                $display(" RESULT : *** FAIL ***  (failed test #%0d)", dut.dmem_wdata);
            $display(" cycles         : %0d", dut.u_core.perf_cycles);
            $display(" instructions   : %0d", dut.u_core.perf_instret + 1);
            $display(" CPI            : %0.3f", cpi);
            $display(" load-use stalls: %0d", dut.u_core.perf_stalls);
            $display(" branch flushes : %0d", dut.u_core.perf_flushes);
            $display("--------------------------------------------------------");
        end
    endtask

    always @(posedge clk) begin
        if (!rst && dut.dmem_we && dut.dmem_addr == TOHOST) begin
            report(dut.dmem_wdata == 32'd1);
            $finish;
        end
        if (!rst && dut.u_core.perf_cycles >= MAX_CYCLES) begin
            $display(" RESULT : *** TIMEOUT *** after %0d cycles", MAX_CYCLES);
            $finish;
        end
    end
endmodule
