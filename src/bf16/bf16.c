#include "bf16.h"

/* Dummies: every function returns 0. Replace with the real routines. */

uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exponent = (f32bits >> 23) & 0xFFu;
    uint32_t upper = f32bits >> 16;

    /* Preserve Infinity and NaN bit patterns. */
    if (exponent == 0xFFu)
        return (uint16_t) upper;

    /* Round to nearest, ties to even. */
    uint32_t lsb = upper & 1u;
    uint32_t rounded = f32bits + 0x7FFFu + lsb;

    return (uint16_t) (rounded >> 16);
}


uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    (void) a;
    (void) b;
    return 0;
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
