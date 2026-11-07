# ============================================================================
# test_all.s - Self-checking test suite for the 5-stage RV32I core
#
# x31 holds the current test number. On failure the test number is written
# to TOHOST (0x7FC); on success the value 1 is written. The testbench watches
# that address and reports PASS / FAIL.
# ============================================================================

# ---------------------------------------------------------------- T2: ADDI
        addi x31, x0, 2
        addi x5, x0, 123
        li   x6, 123
        bne  x5, x6, fail

# ------------------------------------------- T3: EX/MEM + MEM/WB forwarding
        addi x31, x0, 3
        addi x1, x0, 10
        addi x2, x0, 20
        add  x3, x1, x2          # x2 from EX/MEM, x1 from MEM/WB
        li   x6, 30
        bne  x3, x6, fail

# ---------------------------------------------------- T4: SUB, dependent chain
        addi x31, x0, 4
        sub  x4, x3, x1          # 20
        add  x5, x4, x4          # 40, both operands forwarded
        li   x6, 40
        bne  x5, x6, fail
        sub  x7, x1, x2          # -10
        li   x6, -10
        bne  x7, x6, fail

# ------------------------------------------------------------ T5: logic ops
        addi x31, x0, 5
        li   x1, 0x0F0F0F0F
        li   x2, 0x00FF00FF
        xor  x3, x1, x2
        li   x6, 0x0FF00FF0
        bne  x3, x6, fail
        or   x3, x1, x2
        li   x6, 0x0FFF0FFF
        bne  x3, x6, fail
        and  x3, x1, x2
        li   x6, 0x000F000F
        bne  x3, x6, fail
        xori x3, x1, -1
        li   x6, 0xF0F0F0F0
        bne  x3, x6, fail
        ori  x3, x1, 0x0F0
        li   x6, 0x0F0F0FFF
        bne  x3, x6, fail
        andi x3, x1, 0x7FF
        li   x6, 0x70F
        bne  x3, x6, fail

# ---------------------------------------------------------------- T6: shifts
        addi x31, x0, 6
        li   x1, 0x80000010
        addi x2, x0, 4
        sll  x3, x1, x2
        li   x6, 0x00000100
        bne  x3, x6, fail
        srl  x3, x1, x2
        li   x6, 0x08000001
        bne  x3, x6, fail
        sra  x3, x1, x2
        li   x6, 0xF8000001
        bne  x3, x6, fail
        slli x3, x1, 1
        li   x6, 0x00000020
        bne  x3, x6, fail
        srli x3, x1, 31
        li   x6, 1
        bne  x3, x6, fail
        srai x3, x1, 31
        li   x6, -1
        bne  x3, x6, fail
        addi x2, x0, 36          # only low 5 bits used -> shift by 4
        sll  x3, x1, x2
        li   x6, 0x00000100
        bne  x3, x6, fail

# -------------------------------------------------------- T7: set-less-than
        addi x31, x0, 7
        addi x1, x0, -5
        addi x2, x0, 3
        slt  x3, x1, x2          # -5 < 3        -> 1
        addi x6, x0, 1
        bne  x3, x6, fail
        sltu x3, x1, x2          # 0xFFFFFFFB < 3 -> 0
        bne  x3, x0, fail
        slti x3, x1, -4          # -5 < -4       -> 1
        bne  x3, x6, fail
        sltiu x3, x2, -1         # 3 < 0xFFFFFFFF -> 1
        bne  x3, x6, fail
        slt  x3, x2, x1          # 3 < -5        -> 0
        bne  x3, x0, fail

# --------------------------------------------------------- T8: LUI / AUIPC
        addi x31, x0, 8
        lui  x3, 0xABCDE
        li   x6, 0xABCDE000
        bne  x3, x6, fail
auipc0: auipc x3, 0
        la   x6, auipc0
        bne  x3, x6, fail
auipc1: auipc x3, 1
        la   x6, auipc1+4096
        bne  x3, x6, fail

# --------------------------------------------- T9: SW / LW + load-use stall
        addi x31, x0, 9
        li   x1, 0x100
        li   x2, 0x12345678
        sw   x2, 0(x1)
        lw   x3, 0(x1)
        addi x4, x3, 1           # load-use on rs1 -> 1 stall
        li   x6, 0x12345679
        bne  x4, x6, fail
        lw   x3, 0(x1)
        add  x4, x3, x3          # load-use, both operands
        li   x6, 0x2468ACF0
        bne  x4, x6, fail
        lw   x3, 0(x1)
        add  x4, x0, x3          # load-use on rs2
        li   x6, 0x12345678
        bne  x4, x6, fail

# --------------------------------------------- T10: byte / halfword access
        addi x31, x0, 10
        sw   x0, 4(x1)
        addi x2, x0, 0x81
        sb   x2, 4(x1)           # byte 0 = 0x81
        addi x2, x0, 0x7F
        sb   x2, 5(x1)           # byte 1 = 0x7F
        li   x2, 0xBEEF
        sh   x2, 6(x1)           # bytes 2,3 = 0xEF, 0xBE
        lw   x3, 4(x1)
        li   x6, 0xBEEF7F81
        bne  x3, x6, fail
        lb   x3, 4(x1)
        li   x6, 0xFFFFFF81
        bne  x3, x6, fail
        lbu  x3, 4(x1)
        li   x6, 0x81
        bne  x3, x6, fail
        lb   x3, 5(x1)
        li   x6, 0x7F
        bne  x3, x6, fail
        lh   x3, 6(x1)
        li   x6, 0xFFFFBEEF
        bne  x3, x6, fail
        lhu  x3, 6(x1)
        li   x6, 0xBEEF
        bne  x3, x6, fail
        lh   x3, 4(x1)
        li   x6, 0x7F81
        bne  x3, x6, fail
        lb   x3, 7(x1)
        li   x6, 0xFFFFFFBE
        bne  x3, x6, fail
        lbu  x3, 6(x1)
        li   x6, 0xEF
        bne  x3, x6, fail

# ------------------------------------------------------------- T11: branches
        addi x31, x0, 11
        addi x1, x0, -1
        addi x2, x0, 1
        beq  x1, x2, fail
        beq  x2, x2, b1
        j    fail
b1:     bne  x2, x2, fail
        bne  x1, x2, b2
        j    fail
b2:     blt  x2, x1, fail        # 1 < -1 false
        blt  x1, x2, b3
        j    fail
b3:     bge  x1, x2, fail
        bge  x2, x1, b4
        j    fail
b4:     bge  x2, x2, b5          # equal -> taken
        j    fail
b5:     bltu x1, x2, fail        # 0xFFFFFFFF < 1 false
        bltu x2, x1, b6
        j    fail
b6:     bgeu x2, x1, fail
        bgeu x1, x2, b7
        j    fail
b7:     addi x7, x0, 0           # wrong-path instructions must be flushed
        beq  x0, x0, b8
        addi x7, x0, 1
        addi x7, x0, 2
b8:     bne  x7, x0, fail

# ------------------------------------------------------------------ T12: JAL
        addi x31, x0, 12
        addi x7, x0, 0
        jal  x1, jt1
jal_ret:
        addi x7, x0, 99          # shadow - must be flushed
jt1:    bne  x7, x0, fail
        la   x6, jal_ret
        bne  x1, x6, fail
        jal  x1, jt2
jt2:    addi x8, x1, 0           # link value forwarded from EX/MEM
        la   x6, jt2
        bne  x8, x6, fail

# ----------------------------------------------------------------- T13: JALR
        addi x31, x0, 13
        la   x8, jr_t
        addi x7, x0, 0
        jalr x9, 0(x8)           # base forwarded
jr_next:
        addi x7, x0, 1           # shadow - must be flushed
jr_t:   bne  x7, x0, fail
        la   x6, jr_next
        bne  x9, x6, fail
        la   x8, jr_t2+1         # odd address: JALR must clear bit 0
        jalr x0, 0(x8)
        j    fail
jr_t2:  auipc x3, 0              # PC must be even (bit 0 cleared)
        la   x6, jr_t2
        bne  x3, x6, fail

# ----------------------------------------------------------- T14: loop 1..10
        addi x31, x0, 14
        addi x1, x0, 0
        addi x2, x0, 1
        addi x3, x0, 11
loop:   add  x1, x1, x2
        addi x2, x2, 1
        bne  x2, x3, loop
        addi x6, x0, 55
        bne  x1, x6, fail

# -------------------------------------------- T15: x0 is never written/fwd
        addi x31, x0, 15
        addi x0, x0, 5
        add  x5, x0, x0          # must not forward the "5"
        bne  x5, x0, fail
        lw   x0, 0x100(x0)       # load into x0: no stall, no write
        add  x5, x0, x0
        bne  x5, x0, fail

# --------------------------------------------------- T16: load -> store fwd
        addi x31, x0, 16
        li   x1, 0x100
        li   x2, 0xCAFEBABE
        sw   x2, 8(x1)
        lw   x3, 8(x1)
        sw   x3, 12(x1)          # store data from a just-loaded register
        lw   x4, 12(x1)
        bne  x4, x2, fail

# ------------------------------------------- T17: forwarding priority
        addi x31, x0, 17
        addi x1, x0, 1
        addi x1, x0, 2
        add  x2, x1, x0          # newest value (EX/MEM) must win -> 2
        addi x6, x0, 2
        bne  x2, x6, fail

# ------------------------------------------- T18: WB -> ID regfile bypass
        addi x31, x0, 18
        addi x3, x0, 7
        nop
        nop
        add  x4, x3, x0          # reads x3 in ID while addi is in WB
        addi x6, x0, 7
        bne  x4, x6, fail

# ------------------------------------------- T19: load followed by branch
        addi x31, x0, 19
        li   x1, 0x100
        li   x6, 0x12345678
        lw   x3, 0(x1)
        bne  x3, x6, fail        # load-use into branch comparator

# ------------------------------------------------------------- result
pass:   addi x1, x0, 1
        sw   x1, 0x7FC(x0)
pass_loop:
        j    pass_loop

fail:   sw   x31, 0x7FC(x0)
fail_loop:
        j    fail_loop
