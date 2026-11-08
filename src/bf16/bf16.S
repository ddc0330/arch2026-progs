
    .text

    # ------------------------------------------------------------
    # uint16_t bf16_from_f32_asm(uint32_t f32bits)
    # ------------------------------------------------------------

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2

bf16_from_f32_asm:
    srli    t0, a0, 23
    andi    t0, t0, 255

    addi    t1, zero, 255
    beq     t0, t1, .Lfrom_f32_special

    srli    t0, a0, 16
    andi    t1, t0, 1

    lui     t2, 0x8
    addi    t2, t2, -1

    add     t2, t2, t1
    add     a0, a0, t2

    srli    a0, a0, 16
    jalr    zero, 0(ra)

.Lfrom_f32_special:
    srli    a0, a0, 16
    jalr    zero, 0(ra)

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm


    # ------------------------------------------------------------
    # uint16_t bf16_mul_asm(uint16_t a, uint16_t b)
    # ------------------------------------------------------------

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2

bf16_mul_asm:
    # t0 = sign
    # t1 = exp_a
    # t2 = exp_b
    # t3 = frac_a
    # t4 = frac_b
    # t5 = sig_a / multiplicand
    # t6 = sig_b / multiplier
    # a2 = e_a
    # a3 = e_b
    # a4 = product
    # a5 = temporary
    # a6 = result exponent
    # a7 = result significand

    # Extract sign
    xor     t0, a0, a1
    lui     a5, 8
    and     t0, t0, a5

    # Extract exponent and fraction of a
    srli    t1, a0, 7
    andi    t1, t1, 255
    andi    t3, a0, 127

    # Extract exponent and fraction of b
    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t4, a1, 127

    addi    a5, zero, 255

    # Handle special values of a
    bne     t1, a5, .Lmul_check_b_special
    bne     t3, zero, .Lmul_return_a

    beq     t2, zero, .Lmul_check_inf_a_zero_b
    jal     zero, .Lmul_infinity

.Lmul_check_inf_a_zero_b:
    bne     t4, zero, .Lmul_infinity
    jal     zero, .Lmul_invalid

.Lmul_return_a:
    jalr    zero, 0(ra)

    # Handle special values of b
.Lmul_check_b_special:
    bne     t2, a5, .Lmul_check_zero
    bne     t4, zero, .Lmul_return_b

    beq     t1, zero, .Lmul_check_inf_b_zero_a
    jal     zero, .Lmul_infinity

.Lmul_check_inf_b_zero_a:
    bne     t3, zero, .Lmul_infinity
    jal     zero, .Lmul_invalid

.Lmul_return_b:
    addi    a0, a1, 0
    jalr    zero, 0(ra)

    # Handle zero operands
.Lmul_check_zero:
    bne     t1, zero, .Lmul_check_b_zero
    bne     t3, zero, .Lmul_check_b_zero
    jal     zero, .Lmul_return_zero

.Lmul_check_b_zero:
    bne     t2, zero, .Lmul_normalize_a
    bne     t4, zero, .Lmul_normalize_a
    jal     zero, .Lmul_return_zero

    # Normalize operand a
.Lmul_normalize_a:
    beq     t1, zero, .Lmul_a_subnormal

    addi    a2, t1, 0
    addi    t5, t3, 128
    jal     zero, .Lmul_a_done

.Lmul_a_subnormal:
    addi    a2, zero, 1
    addi    t5, t3, 0

.Lmul_a_loop:
    addi    a5, zero, 128
    bge     t5, a5, .Lmul_a_done
    slli    t5, t5, 1
    addi    a2, a2, -1
    jal     zero, .Lmul_a_loop

.Lmul_a_done:

    # Normalize operand b
    beq     t2, zero, .Lmul_b_subnormal

    addi    a3, t2, 0
    addi    t6, t4, 128
    jal     zero, .Lmul_b_done

.Lmul_b_subnormal:
    addi    a3, zero, 1
    addi    t6, t4, 0

.Lmul_b_loop:
    addi    a5, zero, 128
    bge     t6, a5, .Lmul_b_done
    slli    t6, t6, 1
    addi    a3, a3, -1
    jal     zero, .Lmul_b_loop

.Lmul_b_done:

    # Shift-and-add multiplication
    addi    a4, zero, 0

.Lmul_product_loop:
    beq     t6, zero, .Lmul_product_done

    andi    a5, t6, 1
    beq     a5, zero, .Lmul_product_skip

    add     a4, a4, t5

.Lmul_product_skip:
    slli    t5, t5, 1
    srli    t6, t6, 1
    jal     zero, .Lmul_product_loop

.Lmul_product_done:

    # Calculate result exponent
    add     a6, a2, a3

    lui     a5, 8
    and     a5, a4, a5
    beq     a5, zero, .Lmul_product_low

    srli    a7, a4, 8
    addi    a6, a6, -126
    jal     zero, .Lmul_exp_ready

.Lmul_product_low:
    srli    a7, a4, 7
    addi    a6, a6, -127

.Lmul_exp_ready:

    # Handle overflow
    addi    a5, zero, 255
    bge     a6, a5, .Lmul_overflow

    # Handle underflow
    bge     zero, a6, .Lmul_underflow

    # Assemble normal result
    andi    a7, a7, 127
    slli    a6, a6, 7
    or      a0, t0, a6
    or      a0, a0, a7
    jalr    zero, 0(ra)

.Lmul_underflow:
    addi    a5, zero, -6
    blt     a6, a5, .Lmul_return_zero

    andi    a7, a7, 127
    addi    a5, zero, 1
    sub     a5, a5, a6
    srl     a7, a7, a5

    or      a0, t0, a7
    jalr    zero, 0(ra)

.Lmul_return_zero:
    addi    a0, t0, 0
    jalr    zero, 0(ra)

.Lmul_overflow:
.Lmul_infinity:
    lui     a0, 8
    addi    a0, a0, -128
    or      a0, a0, t0
    jalr    zero, 0(ra)

.Lmul_invalid:
    lui     a0, 8
    addi    a0, a0, -64
    jalr    zero, 0(ra)

    .size   bf16_mul_asm, .-bf16_mul_asm


    # ------------------------------------------------------------
    # uint16_t bf16_sqrt_asm(uint16_t a)
    # Not implemented yet.
    # ------------------------------------------------------------

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

bf16_sqrt_asm:
    addi    a0, zero, 0
    jalr    zero, 0(ra)

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
