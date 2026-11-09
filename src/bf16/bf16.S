
    .text

    # ------------------------------------------------------------
    # uint16_t bf16_from_f32_asm(uint32_t f32bits)
    # ------------------------------------------------------------

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2

bf16_from_f32_asm:
    # Drop the sign; exponent 255 makes the shifted word >= 0xff000000.
    lui     t0, 0xff000
    slli    t1, a0, 1

    bgeu    t1, t0, .Lfrom_f32_special

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
    xor     t0, a0, a1
    lui     a5, 8
    and     t0, t0, a5

    srli    t1, a0, 7
    andi    t1, t1, 255
    andi    t3, a0, 127

    srli    t2, a1, 7
    andi    t2, t2, 255
    andi    t4, a1, 127

    addi    a5, zero, 255

    bne     t1, a5, .Lmul_check_b_special
    bne     t3, zero, .Lmul_return_a

    beq     t2, zero, .Lmul_check_inf_a_zero_b
    jal     zero, .Lmul_infinity

.Lmul_check_inf_a_zero_b:
    bne     t4, zero, .Lmul_infinity
    jal     zero, .Lmul_invalid

.Lmul_return_a:
    jalr    zero, 0(ra)

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

.Lmul_check_zero:
    bne     t1, zero, .Lmul_check_b_zero
    bne     t3, zero, .Lmul_check_b_zero
    jal     zero, .Lmul_return_zero

.Lmul_check_b_zero:
    bne     t2, zero, .Lmul_normalize_a
    bne     t4, zero, .Lmul_normalize_a
    jal     zero, .Lmul_return_zero

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
    addi    a5, zero, 255
    bge     a6, a5, .Lmul_overflow

    bge     zero, a6, .Lmul_underflow

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
    # RV32I integer square root using binary search.
    # ------------------------------------------------------------

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2

bf16_sqrt_asm:
    # Register allocation:
    # t0 = sign
    # t1 = exponent
    # t2 = fraction
    # t3 = temporary
    # t4 = unbiased exponent
    # t5 = normalized significand
    # t6 = binary search low
    # a1 = binary search high
    # a2 = midpoint
    # a3 = square multiplicand
    # a4 = square multiplier
    # a5 = square product / temporary
    # a6 = temporary bit
    # a7 = result exponent

    # Extract sign
    lui     t3, 8
    and     t0, a0, t3

    # Extract exponent and fraction
    srli    t1, a0, 7
    andi    t1, t1, 255
    andi    t2, a0, 127

    # Handle NaN and infinity
    addi    t3, zero, 255
    bne     t1, t3, .Lsqrt_not_special

    # NaN: return original input
    bne     t2, zero, .Lsqrt_return_input

    # Positive infinity: return original input
    beq     t0, zero, .Lsqrt_return_input

    # Negative infinity: return quiet NaN
    jal     zero, .Lsqrt_nan

.Lsqrt_return_input:
    jalr    zero, 0(ra)

.Lsqrt_not_special:

    # Handle positive and negative zero
    bne     t1, zero, .Lsqrt_check_sign
    bne     t2, zero, .Lsqrt_check_sign

    addi    a0, zero, 0
    jalr    zero, 0(ra)

.Lsqrt_check_sign:

    # Negative nonzero input returns quiet NaN
    beq     t0, zero, .Lsqrt_check_denormal
    jal     zero, .Lsqrt_nan

.Lsqrt_check_denormal:

    # Positive subnormal input returns zero
    bne     t1, zero, .Lsqrt_normal

    addi    a0, zero, 0
    jalr    zero, 0(ra)

.Lsqrt_normal:

    # e = exponent - 127
    addi    t4, t1, -127

    # m = 128 + fraction
    addi    t5, t2, 128

    # If exponent is odd:
    # m *= 2
    # e -= 1
    andi    t3, t4, 1
    beq     t3, zero, .Lsqrt_exponent_ready

    slli    t5, t5, 1
    addi    t4, t4, -1

.Lsqrt_exponent_ready:

    # Initialize binary search
    addi    t6, zero, 90
    addi    a1, zero, 256

.Lsqrt_search_loop:

    # Stop when low >= high
    bgeu    t6, a1, .Lsqrt_search_done

    # mid = (low + high + 1) / 2
    add     a2, t6, a1
    addi    a2, a2, 1
    srli    a2, a2, 1

    # Calculate mid * mid using shift-and-add
    addi    a3, a2, 0
    addi    a4, a2, 0
    addi    a5, zero, 0

.Lsqrt_square_loop:

    beq     a4, zero, .Lsqrt_square_done

    andi    a6, a4, 1
    beq     a6, zero, .Lsqrt_square_skip

    add     a5, a5, a3

.Lsqrt_square_skip:

    slli    a3, a3, 1
    srli    a4, a4, 1
    jal     zero, .Lsqrt_square_loop

.Lsqrt_square_done:

    # Check (mid * mid) / 128 <= m
    srli    a5, a5, 7
    bgeu    t5, a5, .Lsqrt_set_low

    # Otherwise high = mid - 1
    addi    a1, a2, -1
    jal     zero, .Lsqrt_search_loop

.Lsqrt_set_low:

    addi    t6, a2, 0
    jal     zero, .Lsqrt_search_loop

.Lsqrt_search_done:

    # result_exp = e / 2 + 127
    # e is guaranteed to be even here.
    srai    a7, t4, 1
    addi    a7, a7, 127

    # Handle overflow
    addi    a5, zero, 255
    bge     a7, a5, .Lsqrt_overflow

    # Handle underflow
    bge     zero, a7, .Lsqrt_underflow

    # Assemble BF16 result
    andi    t6, t6, 127
    slli    a7, a7, 7
    or      a0, a7, t6
    jalr    zero, 0(ra)

.Lsqrt_overflow:

    lui     a0, 8
    addi    a0, a0, -128
    jalr    zero, 0(ra)

.Lsqrt_underflow:

    addi    a0, zero, 0
    jalr    zero, 0(ra)

.Lsqrt_nan:

    # Canonical quiet NaN: 0x7FC0
    lui     a0, 8
    addi    a0, a0, -64
    jalr    zero, 0(ra)

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
