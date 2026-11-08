# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only.

    .text

    # op1: Dummy
    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    sw      zero, 0(a2)
    li      a0, 0
    ret
    .size   op1_asm, .-op1_asm


    # op2: Unsigned subtraction
    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    sub     a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm


    # op3: Overflow-safe average
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


    # q_mul: Dummy
    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    li      a0, 0
    ret
    .size   q_mul_asm, .-q_mul_asm