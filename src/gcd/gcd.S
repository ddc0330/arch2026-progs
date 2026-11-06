# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.

.text
    .globl gcd_u32_asm
    .type gcd_u32_asm, @function
    .align 2

gcd_u32_asm:
    # The contract defines gcd(0, x) = x.
    beqz    a0, .Lreturn_b
    beqz    a1, .Ldone

    # Neither a nor b can reduce the result below one.
    li      t2, 1
    beq     a0, t2, .Lreturn_one
    beq     a1, t2, .Lreturn_one

    li      t0, 0

.Lcommon_twos:
    # Remove only factors of two shared by both operands.
    or      t1, a0, a1
    andi    t1, t1, 1
    bnez    t1, .Lmake_a_odd
    srli    a0, a0, 1
    srli    a1, a1, 1
    addi    t0, t0, 1
    j       .Lcommon_twos

.Lmake_a_odd:
    andi    t1, a0, 1
    bnez    t1, .Linitial_b_odd
    srli    a0, a0, 1
    j       .Lmake_a_odd

.Linitial_b_odd:
    andi    t1, a1, 1
    bnez    t1, .Lcompare
    srli    a1, a1, 1
    j       .Linitial_b_odd

.Lcompare:
    # Both operands are odd. Keep the smaller one in a0.
    bgeu    a1, a0, .Lsubtract
    mv      t1, a0
    mv      a0, a1
    mv      a1, t1

.Lsubtract:
    # gcd(1, odd) is one; restore the common power of two.
    beq     a0, t2, .Lfinish
    sub     a1, a1, a0
    beqz    a1, .Lfinish

.Lstrip_b:
    # The nonzero difference of two odd operands is even.
    srli    a1, a1, 1
    andi    t1, a1, 1
    beqz    t1, .Lstrip_b
    j       .Lcompare

.Lfinish:
    sll     a0, a0, t0
    ret

.Lreturn_one:
    li      a0, 1
    ret

.Lreturn_b:
    mv      a0, a1

.Ldone:
    ret

    .size gcd_u32_asm, .-gcd_u32_asm
