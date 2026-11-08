#include "fixed.h"

/* Dummies: every function returns 0. Replace with the real routines. */
uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int passes = 0;

    while (b != 0) {
        uint32_t c = (a & b) << 1;

        a = a ^ b;
        b = c;

        passes++;
    }

    *n = passes;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}

uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}


int32_t q_mul(int32_t a, int32_t b)
{
    /* Convert signed inputs to unsigned magnitudes. */
    uint32_t ma = a < 0 ? 0u - (uint32_t) a : (uint32_t) a;
    uint32_t mb = b < 0 ? 0u - (uint32_t) b : (uint32_t) b;

    /* Split each 32-bit operand into two 16-bit parts. */
    uint32_t al = ma & 0xFFFF;
    uint32_t ah = ma >> 16;
    uint32_t bl = mb & 0xFFFF;
    uint32_t bh = mb >> 16;

    /* Compute the 64-bit magnitude using partial products. */
    uint64_t magnitude = (uint64_t) (al * bl) + ((uint64_t) (al * bh) << 16) +
                         ((uint64_t) (ah * bl) << 16) +
                         ((uint64_t) (ah * bh) << 32);

    /* Restore the sign. */
    int64_t product = (int64_t) magnitude;

    if ((a < 0) != (b < 0))
        product = -product;

    /* Apply rounding and convert back to Q11.20. */
    product += (int64_t) 1 << (Q - 1);

    return (int32_t) (product >> Q);
}
