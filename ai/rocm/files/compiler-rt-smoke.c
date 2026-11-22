/* x86_64 host ABI regression: link with private Clang's --rtlib=compiler-rt.
 * Exercise every 16-bit input, including subnormals, infinities and NaNs.
 * This checks conversions/ABI, not all rounding cases or GPU arithmetic. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern float __extendhfsf2(_Float16);
extern _Float16 __truncsfhf2(float);
extern _Float16 __truncdfhf2(double);
extern float __extendbfsf2(__bf16);
extern __bf16 __truncsfbf2(float);

_Static_assert(sizeof(_Float16) == 2 && sizeof(__bf16) == 2,
               "16-bit source types required");
_Static_assert(sizeof(float) == 4 && sizeof(double) == 8,
               "IEEE binary32/binary64 required");

static uint64_t half_expected(uint16_t h, unsigned fraction_bits, unsigned bias)
{
    unsigned exponent_bits = bias == 127 ? 8 : 11;
    uint64_t sign = (uint64_t)(h >> 15) << (fraction_bits + exponent_bits);
    unsigned e = (h >> 10) & 31, f = h & 1023;
    if (e == 31)
        return sign | ((uint64_t)(2 * bias + 1) << fraction_bits) |
               ((uint64_t)f << (fraction_bits - 10));
    if (e)
        return sign | ((uint64_t)(e + bias - 15) << fraction_bits) |
               ((uint64_t)f << (fraction_bits - 10));
    if (!f)
        return sign;
    int exponent = -14;
    while (!(f & 1024)) {
        f <<= 1;
        --exponent;
    }
    return sign | ((uint64_t)(exponent + (int)bias) << fraction_bits) |
           ((uint64_t)(f & 1023) << (fraction_bits - 10));
}

int main(void)
{
    for (unsigned raw = 0; raw < 65536; ++raw) {
        uint16_t h = (uint16_t)raw, back_f, back_d, back_b;
        _Float16 x;
        __bf16 bx;
        float f, bf;
        double d;
        uint32_t fb, bfb;
        uint64_t db;
        memcpy(&x, &h, 2);
        memcpy(&bx, &h, 2);
        f = __extendhfsf2(x);
        d = (double)x;
        bf = __extendbfsf2(bx);
        memcpy(&fb, &f, 4);
        memcpy(&db, &d, 8);
        memcpy(&bfb, &bf, 4);
        uint64_t expected_d = half_expected(h, 52, 1023);
        /* x86's native float-to-double instruction quiets signaling NaNs. */
        if ((h & 0x7c00) == 0x7c00 && (h & 0x3ff))
            expected_d |= UINT64_C(1) << 51;
        if (fb != half_expected(h, 23, 127) || db != expected_d ||
            bfb != ((uint32_t)h << 16)) {
            fprintf(stderr, "extend ABI/value mismatch at 0x%04x: "
                    "float=%08x double=%016llx bf=%08x\n",
                    raw, fb, (unsigned long long)db, bfb);
            return 1;
        }
        _Float16 hf = __truncsfhf2(f), hd = __truncdfhf2(d);
        __bf16 hb = __truncsfbf2(bf);
        memcpy(&back_f, &hf, 2);
        memcpy(&back_d, &hd, 2);
        memcpy(&back_b, &hb, 2);
        int nan_h = (h & 0x7c00) == 0x7c00 && (h & 0x3ff);
        int nan_b = (h & 0x7f80) == 0x7f80 && (h & 0x7f);
        if ((!nan_h && (back_f != h || back_d != h)) ||
            (!nan_b && back_b != h) ||
            (nan_h && ((back_f & 0x7c00) != 0x7c00 || !(back_f & 0x3ff) ||
                       (back_d & 0x7c00) != 0x7c00 || !(back_d & 0x3ff))) ||
            (nan_b && ((back_b & 0x7f80) != 0x7f80 || !(back_b & 0x7f)))) {
            fprintf(stderr, "trunc ABI/value mismatch at 0x%04x: "
                    "float=%04x double=%04x bf=%04x\n",
                    raw, back_f, back_d, back_b);
            return 1;
        }
    }
    volatile _Float16 a = (_Float16)1.25f, b = (_Float16)2.5f;
    _Float16 c = a + b;
    volatile float result = (float)c;
    if (result != 3.75f)
        return 1;
    puts("compiler-rt _Float16/__bf16 ABI: 65536 patterns, "
         "float/double conversions, arithmetic PASS");
    return 0;
}
