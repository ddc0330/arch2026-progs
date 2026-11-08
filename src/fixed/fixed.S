
# Fixed-point and bitwise operations: RV32I
#
# op1_asm(a, b, n): a0, a1, a2 -> a0
# op2_asm(a, b):    a0, a1 -> a0
# op3_asm(a, b):    a0, a1 -> a0
# q_mul_asm(a, b):  a0, a1 -> a0
#
# RV32I implementation.

    .text

    # ------------------------------------------------
    # op1: Bitwise Adder - Optimization V2
    # Loop Branch Reduction
    # ------------------------------------------------
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2

op1_asm:
    addi    t0, zero, 0

    # Check whether carry is initially zero.
    beq     a1, zero, .Lop1_done

.Lop1_loop:
    # Calculate carry.
    and     t1, a0, a1

    # Calculate sum without carry.
    xor     a0, a0, a1

    # Shift carry directly into a1.
    slli    a1, t1, 1

    # Count iterations.
    addi    t0, t0, 1

    # Continue only when carry is nonzero.
    bne     a1, zero, .Lop1_loop

.Lop1_done:
    # Store iteration count.
    sw      t0, 0(a2)
    ret

    .size   op1_asm, .-op1_asm


    # ------------------------------------------------
    # op2: Unsigned Subtraction
    # ------------------------------------------------
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2

op2_asm:
    sub     a0, a0, a1
    ret

    .size   op2_asm, .-op2_asm


    # ------------------------------------------------
    # op3: Overflow-safe Average
    # ------------------------------------------------
    .globl  op3_asm
    .type   op3_asm, @function
    .align  2

op3_asm:
    and     t0, a0, a1
    xor     t1, a0, a1
    srli    t1, t1, 1
    add     a0, t0, t1
    ret

    .size   op3_asm, .-op3_asm


    # ------------------------------------------------
    # q_mul: Dummy (not implemented yet)
    # ------------------------------------------------
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2

q_mul_asm:
    li      a0, 0
    ret

    .size   q_mul_asm, .-q_mul_asm
