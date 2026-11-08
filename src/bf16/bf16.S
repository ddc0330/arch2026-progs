# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    # t0 = exponent = (f32bits >> 23) & 0xFF
    srli    t0, a0, 23
    andi    t0, t0, 255

    # if exponent == 0xFF, return upper 16 bits unchanged
    addi    t1, zero, 255
    beq     t0, t1, .Lfrom_f32_special

    # t0 = upper = f32bits >> 16
    srli    t0, a0, 16

    # t1 = lsb = upper & 1
    andi    t1, t0, 1

    # t2 = 0x7FFF
    lui     t2, 0x8
    addi    t2, t2, -1

    # rounded = f32bits + 0x7FFF + lsb
    add     t2, t2, t1
    add     a0, a0, t2

    # return rounded >> 16
    srli    a0, a0, 16
    jalr    zero, 0(ra)

.Lfrom_f32_special:
    # Inf / NaN: return top 16 bits unchanged
    srli    a0, a0, 16
    jalr    zero, 0(ra)

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    li      a0, 0
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
