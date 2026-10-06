# Speed

`pixi run bench` produces the CPU figures, `make -f cuda/Makefile bench` and `bench-device` the
CUDA figures, and `make -f target/Makefile bench` the offload figures.

## CPU

Apple M4, one thread, `pixi run bench`, gfortran 16, 2^24 elements, minimum of seven runs:

| | GiB/s |
|---|---|
| `rng%fill`, `real64` array | 17.4 |
| `rng%fill`, `real32` array | 17.4 |
| `rng%fill`, `int32` array | 20.1 |
| `rng%fill`, `int64` array | 20.5 |
| `rng%next_real64()` in a loop | 4.4 |
| intrinsic `random_number`, `real64` array | 10.3 |
| intrinsic `random_number`, `real32` array | 4.9 |
| `rng%fill_normal`, `real64` array (ziggurat) | 7.2 |
| `rng%fill_normal`, `real32` array (Box-Muller) | 5.0 |

The fills run at the speed of the C library, and clang for the C part (`FPM_CC=clang`) gives
the same figures. The scalar loop pays a call into C per draw. The normal rows are the median of
three such runs on 2026-10-05.

## GPU

NVIDIA A100 40 GB (PCIe), CUDA 12.8, `make -f cuda/Makefile bench`, 2^28 elements, minimum of 21
`cudaEvent` timings after a half-second warm-up. All GPU figures on this page come from one window
on 2026-10-06 with no other process on the GPU, and a second pass agreed within 4 %. The cuRAND
column is Philox4x32-10 of cuRAND 10.3.9 in the same program, by the same method. cuRAND has no
64-bit integer output for Philox, so the `int64` row's cuRAND figure is `curandGenerate` writing
the same bytes as 32-bit words, marked "nearest".

| | GiB/s written | cuRAND Philox4x32-10 | cuRAND call |
|---|---|---|---|
| `tandem_device_fill_real64` | 1392 | 809 | `curandGenerateUniformDouble` |
| `tandem_device_fill_real32` | 1379 | 1327 | `curandGenerateUniform` |
| `tandem_device_fill_int64` | 1393 | 1350 | `curandGenerate`, nearest |
| `tandem_device_fill_int32` | 1383 | 1336 | `curandGenerate` |

These are the rates of `tandem.cuh`'s tile kernel, about the card's memory bandwidth.

Draws inside a kernel, `make -f cuda/Makefile bench-device`, nvfortran 25.3. The cuRAND rows are
kernels with the same thread count, each thread drawing from its own Philox4x32-10 subsequence of
`curand_device` and storing with a grid stride:

| | GiB/s written | cuRAND Philox4x32-10 | cuRAND call |
|---|---|---|---|
| `tandem_dev_next_real64` in a kernel | 244 | 1411 | `curand_uniform_double` |
| `tandem_dev_next_int32` in a kernel | 174 | 1241 | `curand` |

In the kernel module each 32-bit word is emulated in an `int64` with its products built from
16-bit halves, and each draw goes through the scalar alignment and cache check, so draws inside
a kernel run at about a sixth of the device fills and of cuRAND's device draws.

### OpenMP target and do concurrent

Throughput on an NVIDIA A100 40 GB (PCIe), nvfortran 25.3, CUDA driver 570, 2^28 elements held
on the device, minimum of seven timings after two warm-up fills, in the window above. The CUDA
Fortran and cuRAND columns are the rows of `make -f cuda/Makefile bench` above. cuRAND has no
bounded integers, so that row's cuRAND figure is `curandGenerate`, marked "nearest":

| fill | CUDA Fortran | `_target` | `_stdpar` | cuRAND Philox4x32-10 |
|---|---|---|---|---|
| `real64` | 1392 GiB/s | 787 | 779 | 809 |
| `real32` | 1379 | 386 | 390 | 1327 |
| `int64` | 1393 | 780 | 1274 | 1350, nearest |
| `int32` | 1383 | 481 | 1200 | 1336 |
| bounded `int32`, bound 1000 | not measured | 195 | 319 | 1336, nearest |

These run below the CUDA fills because each iteration writes whole blocks at a stride of one
row, where the tile kernel of `tandem.cuh` stages them through shared memory for coalesced
stores. LLVM flang with OpenMP offload to NVIDIA was not run: batserv01 has no flang with an
NVPTX offload runtime and the conda-forge flang lacks its intrinsic modules.
