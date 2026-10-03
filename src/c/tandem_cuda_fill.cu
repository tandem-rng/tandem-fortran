/* C entry points over tandem.cuh for the Fortran module tandem_rng_cuda.
 *
 * Each fill writes n elements to device memory from the stream at *pos, exactly as the C
 * library's tandem_fill_* would, and moves *pos past them. The launch is asynchronous on the
 * default stream. The return value is the cudaError_t of the launch.
 *
 * Copyright 2026 Jessica Cox. Apache License 2.0, see LICENSE.
 */
#include "tandem.cuh"

extern "C" {

int tandem_cuda_fill_u32(const uint32_t key[4], uint64_t *pos, uint32_t K, uint32_t *out,
                         size_t n) {
    *pos = tandem::fill_u32(key, *pos, K, out, n);
    return (int)cudaGetLastError();
}

int tandem_cuda_fill_u64(const uint32_t key[4], uint64_t *pos, uint32_t K, uint64_t *out,
                         size_t n) {
    *pos = tandem::fill_u64(key, *pos, K, out, n);
    return (int)cudaGetLastError();
}

int tandem_cuda_fill_f32(const uint32_t key[4], uint64_t *pos, uint32_t K, float *out,
                         size_t n) {
    *pos = tandem::fill_f32(key, *pos, K, out, n);
    return (int)cudaGetLastError();
}

int tandem_cuda_fill_f64(const uint32_t key[4], uint64_t *pos, uint32_t K, double *out,
                         size_t n) {
    *pos = tandem::fill_f64(key, *pos, K, out, n);
    return (int)cudaGetLastError();
}

}
