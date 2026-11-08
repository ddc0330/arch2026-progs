
# Fixed-point and bitwise operations: RV32I

    .text

    # ------------------------------------------------
    # op1: Bitwise Adder - Optimization V2
    # ------------------------------------------------
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2

op1_asm:
    addi    t0, zero, 0
    beq     a1, zero, .Lop1_done

.Lop1_loop:
    and     t1, a0, a1
    xor     a0, a0, a1
    slli    a1, t1, 1
    addi    t0, t0, 1
    bne     a1, zero, .Lop1_loop

.Lop1_done:
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
    # q_mul: Q11.20 multiplication - Baseline
    #
    # (signed_a * signed_b + 2^19) >> 20
    #
    # RV32I shift-and-add 64-bit multiplication.
    # ------------------------------------------------
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2

q_mul_asm:

    # Convert a to unsigned magnitude.
    srai    t3, a0, 31
    xor     a0, a0, t3
    sub     a0, a0, t3

    # Convert b to unsigned magnitude.
    srai    t4, a1, 31
    xor     a1, a1, t4
    sub     a1, a1, t4

    # Determine final sign.
    xor     t3, t3, t4

    # 64-bit multiplicand: t0:a0
    addi    t0, zero, 0

    # 64-bit accumulator: t2:t1
    addi    t1, zero, 0
    addi    t2, zero, 0

    # Process 32 multiplier bits.
    addi    t4, zero, 32

.Lqmul_loop:

    # Check the lowest multiplier bit.
    andi    t5, a1, 1
    beq     t5, zero, .Lqmul_skip_add

    # Add multiplicand to accumulator.
    add     t6, t1, a0
    sltu    t5, t6, t1

    add     t2, t2, t0
    add     t2, t2, t5

    addi    t1, t6, 0

.Lqmul_skip_add:

    # Correct 64-bit left shift.
    # New high = (high << 1) | (low >> 31)
    # New low  = low << 1

    srli    t6, a0, 31
    slli    a0, a0, 1
    slli    t0, t0, 1
    or      t0, t0, t6

    # Shift multiplier right.
    srli    a1, a1, 1

    # Decrement loop counter.
    addi    t4, t4, -1
    bne     t4, zero, .Lqmul_loop

    # ------------------------------------------------
    # Restore product sign.
    # ------------------------------------------------

    beq     t3, zero, .Lqmul_round

    # Two's complement negation of t2:t1.
    xori    t1, t1, -1
    xori    t2, t2, -1

    addi    t1, t1, 1
    sltiu   t5, t1, 1
    add     t2, t2, t5

.Lqmul_round:

    # Add rounding bias: 2^19 = 0x00080000.
    lui     t5, 0x80

    add     t6, t1, t5
    sltu    t5, t6, t1

    addi    t1, t6, 0
    add     t2, t2, t5

    # Extract bits [51:20] of 64-bit result.
    srli    a0, t1, 20
    slli    t2, t2, 12
    or      a0, a0, t2

    ret

    .size   q_mul_asm, .-q_mul_asm
