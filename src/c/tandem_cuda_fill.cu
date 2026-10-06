/* C entry points over tandem.cuh for the Fortran module tandem_rng_cuda.
 *
 * Each fill writes n elements to device memory from the stream at *pos, exactly as the C
 * library's tandem_fill_* would, and moves *pos past them. The launch is asynchronous on the
 * default stream. The return value is the cudaError_t of the launch.
 *
 * Copyright 2026 Jessica Cox. Apache License 2.0, see LICENSE.
 */
#include "tandem.cuh"

#define FILL(suffix, type)                                                                      \
    int tandem_cuda_fill_##suffix(const uint32_t key[4], uint64_t *pos, uint32_t K, type *out, \
                                  size_t n) {                                                   \
        *pos = tandem::fill_##suffix(key, *pos, K, out, n);                                     \
        return (int)cudaGetLastError();                                                         \
    }

#define FILL_BELOW(suffix, type)                                                                \
    int tandem_cuda_fill_##suffix##_below(const uint32_t key[4], uint64_t *pos, uint32_t K,    \
                                          type range, type *out, size_t n) {                    \
        *pos = tandem::fill_##suffix##_below(key, *pos, K, range, out, n);                      \
        return (int)cudaGetLastError();                                                         \
    }

extern "C" {

FILL(u32, uint32_t)
FILL(u64, uint64_t)
FILL(f32, float)
FILL(f64, double)
FILL(bool, bool)
FILL(u8, uint8_t)
FILL(u16, uint16_t)
FILL(f16_bits, uint16_t)
FILL(normal_f32, float)
FILL(normal_f64, double)
FILL(exponential_f32, float)
FILL(exponential_f64, double)
FILL_BELOW(u32, uint32_t)
FILL_BELOW(u64, uint64_t)

/* cut and alias are device arrays of m entries, from tandem::choice_build on the host. */
int tandem_cuda_fill_choice(const uint32_t key[4], uint64_t *pos, uint32_t K, uint64_t capacity,
                            const uint64_t *cut, const uint32_t *alias, uint32_t m, uint32_t *out,
                            size_t n) {
    *pos = tandem::fill_choice(key, *pos, K, tandem::ChoiceTable{capacity, cut, alias, m}, out, n);
    return (int)cudaGetLastError();
}

}
