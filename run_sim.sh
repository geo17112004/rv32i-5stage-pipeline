#!/bin/sh
# Assemble all programs and run them on Icarus Verilog.
# Usage: ./run_sim.sh [extra plusargs, e.g. +TRACE +VCD]
set -e
cd "$(dirname "$0")"

for s in sw/*.s; do python3 sw/rvasm.py "$s"; done

iverilog -g2005 -Wall -o sim.out \
    rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control.v \
    rtl/forwarding_unit.v rtl/hazard_unit.v rtl/branch_unit.v \
    rtl/imem.v rtl/dmem.v rtl/rv32i_core.v rtl/rv32i_top.v \
    tb/tb_top.v

for h in sw/*.hex; do
    vvp -n sim.out +HEX="$h" "$@"
done
