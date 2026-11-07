# ============================================================================
# bubble_sort.s - Sorts a 10-element array in data memory, then verifies it
#   Array at 0x200 is initialised to a permutation of 0..9.
#   After sorting, a[k] must equal k. Result written to TOHOST (0x7FC):
#   1 = PASS, otherwise (failing index + 2).
# ============================================================================
        li   x10, 0x200          # base address

        # --- initialise: 9 3 7 1 8 2 6 0 5 4
        addi x5, x0, 9
        sw   x5, 0(x10)
        addi x5, x0, 3
        sw   x5, 4(x10)
        addi x5, x0, 7
        sw   x5, 8(x10)
        addi x5, x0, 1
        sw   x5, 12(x10)
        addi x5, x0, 8
        sw   x5, 16(x10)
        addi x5, x0, 2
        sw   x5, 20(x10)
        addi x5, x0, 6
        sw   x5, 24(x10)
        addi x5, x0, 0
        sw   x5, 28(x10)
        addi x5, x0, 5
        sw   x5, 32(x10)
        addi x5, x0, 4
        sw   x5, 36(x10)

        addi x11, x0, 10         # n
        addi x12, x11, -1        # i = n - 1
outer:  beq  x12, x0, done
        addi x13, x0, 0          # j = 0
        add  x14, x10, x0        # p = &a[0]
inner:  beq  x13, x12, inner_end
        lw   x15, 0(x14)         # a[j]
        lw   x16, 4(x14)         # a[j+1]
        bge  x16, x15, noswap    # load-use hazard on x16
        sw   x16, 0(x14)
        sw   x15, 4(x14)
noswap: addi x14, x14, 4
        addi x13, x13, 1
        j    inner
inner_end:
        addi x12, x12, -1
        j    outer

        # --- verify a[k] == k
done:   addi x13, x0, 0
        add  x14, x10, x0
check:  beq  x13, x11, pass
        lw   x15, 0(x14)
        addi x31, x13, 2
        bne  x15, x13, fail
        addi x14, x14, 4
        addi x13, x13, 1
        j    check

pass:   addi x1, x0, 1
        sw   x1, 0x7FC(x0)
pass_loop:
        j    pass_loop

fail:   sw   x31, 0x7FC(x0)
fail_loop:
        j    fail_loop
