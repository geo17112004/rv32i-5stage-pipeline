# ============================================================================
# run_modelsim.do - Compile and simulate in ModelSim / QuestaSim
#
# In the ModelSim Transcript window:
#     cd C:/path/to/rv32i-5stage        (the project root folder)
#     do sim/run_modelsim.do
#
# To run a different program, change the +HEX= argument below, e.g.
#     +HEX=sw/bubble_sort.hex
# Add +TRACE to print every retired instruction.
# ============================================================================
quit -sim
if {[file exists work]} { vdel -lib work -all }
vlib work

vlog -work work \
    rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/control.v \
    rtl/forwarding_unit.v rtl/hazard_unit.v rtl/branch_unit.v \
    rtl/imem.v rtl/dmem.v rtl/rv32i_core.v rtl/rv32i_top.v \
    tb/tb_top.v

vsim -voptargs=+acc work.tb_top +HEX=sw/test_all.hex

# ---------------------------------------------------------------- waveform
add wave -divider "Clock / Reset"
add wave           /tb_top/clk
add wave           /tb_top/rst

add wave -divider "Pipeline (instruction in each stage)"
add wave -hex      /tb_top/dut/u_core/pc
add wave -hex      /tb_top/dut/u_core/if_id_instr
add wave -hex      /tb_top/dut/u_core/id_ex_instr
add wave -hex      /tb_top/dut/u_core/ex_mem_instr
add wave -hex      /tb_top/dut/u_core/mem_wb_instr

add wave -divider "Hazards"
add wave           /tb_top/dut/u_core/load_use_stall
add wave           /tb_top/dut/u_core/ex_redirect
add wave -hex      /tb_top/dut/u_core/ex_target
add wave           /tb_top/dut/u_core/fwd_a
add wave           /tb_top/dut/u_core/fwd_b

add wave -divider "EX stage"
add wave -hex      /tb_top/dut/u_core/alu_a
add wave -hex      /tb_top/dut/u_core/alu_b
add wave -hex      /tb_top/dut/u_core/alu_y

add wave -divider "Data memory"
add wave           /tb_top/dut/dmem_we
add wave -hex      /tb_top/dut/dmem_addr
add wave -hex      /tb_top/dut/dmem_wdata
add wave -hex      /tb_top/dut/dmem_rdata

add wave -divider "Write back"
add wave           /tb_top/dut/u_core/wb_reg_write
add wave -unsigned /tb_top/dut/u_core/wb_rd
add wave -hex      /tb_top/dut/u_core/wb_data

add wave -divider "Register file"
add wave -hex      /tb_top/dut/u_core/u_regfile/regs

run -all
wave zoom full
