#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    unsigned shift = 0;

    /* Remove common factors of two. */
    while (((a | b) & 1u) == 0) {
        a >>= 1;
        b >>= 1;
        shift++;
    }

    /* Make a odd. */
    while ((a & 1u) == 0)
        a >>= 1;

    do {
        /* Make b odd. */
        while ((b & 1u) == 0)
            b >>= 1;

        if (a > b) {
            uint32_t temp = a;
            a = b;
            b = temp;
        }

        b -= a;
    } while (b != 0);

    return a << shift;
}
