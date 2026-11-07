# RV32I 5-Stage Pipelined Processor (Verilog)

A 32-bit RISC-V processor implementing the **RV32I base integer ISA** on a classic
**5-stage pipeline** (IF → ID → EX → MEM → WB) with **full data forwarding,
load-use hazard detection, and branch flush logic**, verified with a
self-checking assembly test suite.

## Results

| Program | Result | Instructions | Cycles | CPI | Load-use stalls | Branch flushes |
|---|---|---|---|---|---|---|
| `test_all.s` (19 directed tests) | PASS | 298 | 349 | 1.17 | 6 | 21 |
| `bubble_sort.s` (sort + verify 10 words) | PASS | 526 | 756 | 1.44 | 45 | 91 |

**Fault-injection check:** 13 deliberate RTL bugs (forwarding removed, wrong
forwarding priority, no load-use stall, no flush, missing sign-extension, wrong
store strobes, signed/unsigned branch mix-up, JALR LSB not cleared, ...) were each
injected one at a time; the test suite caught all 13.

## Architecture

```
          +------+    +------+    +------+    +-------+    +------+
   PC --> |  IF  |--->|  ID  |--->|  EX  |--->|  MEM  |--->|  WB  |
          +------+    +------+    +------+    +-------+    +------+
             ^   IF/ID   |   ID/EX   |  EX/MEM   |   MEM/WB  |
             |           |           |           |           |
             |       regfile <-------+-----------+-----------+  write-back
             |      (WB->ID bypass)  |           |
             |                       |<--fwd-----+  EX/MEM -> EX
             |                       |<--fwd-----------------+  MEM/WB -> EX
             |                       |
             +---- branch/jump redirect (resolved in EX, flush IF/ID + ID/EX)
```

| Hazard | Handling |
|---|---|
| RAW, ALU → ALU | Forwarding from EX/MEM (priority) and MEM/WB into EX |
| RAW, 3 instructions apart | Register-file write-through bypass (WB → ID) |
| Load-use | `hazard_unit` stalls PC + IF/ID for 1 cycle, inserts bubble in ID/EX |
| Control (branch/JAL/JALR) | Static predict-not-taken, resolved in EX, 2-cycle flush on redirect |
| Writes to x0 | Ignored; forwarding unit never forwards x0 |

**Supported instructions:** LUI, AUIPC, JAL, JALR, BEQ, BNE, BLT, BGE, BLTU, BGEU,
LB, LH, LW, LBU, LHU, SB, SH, SW, ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI,
SRAI, ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND. FENCE / ECALL / EBREAK
execute as NOPs.

## Files

```
rtl/
  rv32i_core.v        pipeline, pipeline registers, MEM-stage load/store alignment
  control.v           main decoder
  alu.v               10-operation ALU
  regfile.v           32x32 register file with write-through bypass
  imm_gen.v           I/S/B/U/J immediate generation
  forwarding_unit.v   EX/MEM and MEM/WB bypass selection
  hazard_unit.v       load-use detection
  branch_unit.v       branch condition evaluation
  imem.v, dmem.v      4 KB instruction / data memories (dmem has byte strobes)
  rv32i_top.v         core + memories
tb/tb_top.v           self-checking testbench, perf counters, optional trace/VCD
sw/rvasm.py           two-pass RV32I assembler written for this project (Python)
sw/test_all.s         19 directed tests (ALU, shifts, forwarding, stalls, branches...)
sw/bubble_sort.s      bubble sort + self-check
sim/run_modelsim.do   ModelSim compile/sim script with organised waveform
run_sim.sh            Icarus Verilog flow
```

## How to run

**Assemble a program** (no RISC-V toolchain needed):
```
python sw/rvasm.py sw/test_all.s      # -> sw/test_all.hex and sw/test_all.lst
```

**ModelSim:** in the Transcript window
```
cd <path to this folder>
do sim/run_modelsim.do
```
Change `+HEX=` in the script to run another program; add `+TRACE` to print
every retired instruction.

**Icarus Verilog:** `./run_sim.sh` (add `+TRACE` or `+VCD` for waves in GTKWave).

The program signals completion by storing to address `0x7FC`:
`1` = PASS, any other value = number of the failing test.

## Possible extensions
- Move branch resolution to ID to cut the misprediction penalty to 1 cycle
- 2-bit dynamic branch predictor + BTB
- CSR / M-extension support, run the official `riscv-tests`
- FPGA implementation with UART output
