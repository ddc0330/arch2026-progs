
#include "bf16.h"

uint16_t bf16_from_f32(uint32_t f32bits)
{
    uint32_t exponent = (f32bits >> 23) & 0xFFu;
    uint32_t upper = f32bits >> 16;

    if (exponent == 0xFFu)
        return (uint16_t) upper;

    uint32_t lsb = upper & 1u;
    uint32_t rounded = f32bits + 0x7FFFu + lsb;

    return (uint16_t) (rounded >> 16);
}

uint16_t bf16_mul(uint16_t a, uint16_t b)
{
    uint32_t sign = (a ^ b) & 0x8000u;

    uint32_t exp_a = (a >> 7) & 0xFFu;
    uint32_t exp_b = (b >> 7) & 0xFFu;

    uint32_t frac_a = a & 0x7Fu;
    uint32_t frac_b = b & 0x7Fu;

    /* Handle special values of operand a first. */
    if (exp_a == 0xFFu) {
        if (frac_a != 0)
            return a;

        if (exp_b == 0 && frac_b == 0)
            return 0x7FC0u;

        return (uint16_t) (sign | 0x7F80u);
    }

    /* Handle special values of operand b. */
    if (exp_b == 0xFFu) {
        if (frac_b != 0)
            return b;

        if (exp_a == 0 && frac_a == 0)
            return 0x7FC0u;

        return (uint16_t) (sign | 0x7F80u);
    }

    /* Zero multiplied by a finite value. */
    if ((exp_a == 0 && frac_a == 0) || (exp_b == 0 && frac_b == 0))
        return (uint16_t) sign;

    /* Normalize operand a. */
    int32_t e_a;
    uint32_t sig_a;

    if (exp_a == 0) {
        e_a = 1;
        sig_a = frac_a;

        while (sig_a < 128u) {
            sig_a <<= 1;
            e_a--;
        }
    } else {
        e_a = (int32_t) exp_a;
        sig_a = 128u + frac_a;
    }

    /* Normalize operand b. */
    int32_t e_b;
    uint32_t sig_b;

    if (exp_b == 0) {
        e_b = 1;
        sig_b = frac_b;

        while (sig_b < 128u) {
            sig_b <<= 1;
            e_b--;
        }
    } else {
        e_b = (int32_t) exp_b;
        sig_b = 128u + frac_b;
    }

    /* Multiply the two significands. */
    uint32_t product = sig_a * sig_b;

    int32_t result_exp;
    uint32_t result_sig;

    /* Normalize the product. */
    if (product & 0x8000u) {
        result_sig = product >> 8;
        result_exp = e_a + e_b - 126;
    } else {
        result_sig = product >> 7;
        result_exp = e_a + e_b - 127;
    }

    /* Handle overflow. */
    if (result_exp >= 255)
        return (uint16_t) (sign | 0x7F80u);

    /* Handle underflow and denormal results. */
    if (result_exp <= 0) {
        if (result_exp < -6)
            return (uint16_t) sign;

        /* Shift the fraction only, excluding the hidden bit. */
        result_sig &= 0x7Fu;
        result_sig >>= (uint32_t) (1 - result_exp);

        return (uint16_t) (sign | result_sig);
    }

    /* Assemble the normal BF16 result. */
    return (uint16_t) (sign | ((uint32_t) result_exp << 7) |
                       (result_sig & 0x7Fu));
}

uint16_t bf16_sqrt(uint16_t a)
{
    (void) a;
    return 0;
}
