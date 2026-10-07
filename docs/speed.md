# Speed

`pixi run bench` produces the CPU figures, `make -f cuda/Makefile bench` and `bench-device` the
CUDA figures, and `make -f target/Makefile bench` the offload figures.

## CPU

Apple M4, one thread, `pixi run bench`, gfortran 16, 2^24 elements, minimum of seven runs, GiB/s
of output, the median of three passes in one session. The baseline is the intrinsic
`random_number`, gfortran's xoshiro256**. It returns reals only, so the integer rows scale a
`real64` draw, all 32 bits for `int32` and 53 of the 64 for `int64`. Its normals are Box-Muller
pairs over one array of uniforms, in the row's precision.

| | Tandem | `random_number` |
|---|---|---|
| `rng%fill`, `real64` array | 17.0 | 9.8 |
| `rng%fill`, `real32` array | 16.3 | 4.8 |
| `rng%fill`, `int32` array | 19.6 | 4.3 |
| `rng%fill`, `int64` array | 18.9 | 8.1 |
| `rng%next_real64()` in a loop | 4.5 | 3.1 |
| `rng%fill_normal`, `real64` array (ziggurat) | 7.6 | 0.96 |
| `rng%fill_normal`, `real32` array (Box-Muller) | 5.5 | 0.55 |

The fills run at the speed of the C library, and clang for the C part (`FPM_CC=clang`) gives
the same figures. The scalar loop pays a call into C per draw.

## GPU

NVIDIA A100 40 GB (PCIe), CUDA 12.8, `make -f cuda/Makefile bench`, 2^28 elements, minimum of 21
`cudaEvent` timings after a half-second warm-up. All GPU figures on this page come from one window
on 2026-10-06 with no other process on the GPU, and a second pass agreed within 2 %. The cuRAND
column is Philox4x32-10 of cuRAND 10.3.9 in the same program, by the same method. cuRAND has no
64-bit integer output for Philox, so the `int64` row's cuRAND figure is `curandGenerate` writing
the same bytes as 32-bit words, marked "nearest".

| | GiB/s written | cuRAND Philox4x32-10 | cuRAND call |
|---|---|---|---|
| `tandem_device_fill_real64` | 1392 | 806 | `curandGenerateUniformDouble` |
| `tandem_device_fill_real32` | 1381 | 1329 | `curandGenerateUniform` |
| `tandem_device_fill_int64` | 1393 | 1348 | `curandGenerate`, nearest |
| `tandem_device_fill_int32` | 1383 | 1336 | `curandGenerate` |

These are the rates of `tandem.cuh`'s tile kernel, about the card's memory bandwidth.

Draws inside a kernel, `make -f cuda/Makefile bench-device`, nvfortran 25.3 with `-gpu=lto`. Each
thread walks one chunk's K blocks, and the timed kernels store with a grid stride. The cuRAND rows
are kernels with the same thread count, each thread drawing from its own Philox4x32-10
subsequence of `curand_device` and storing with a grid stride:

| | GiB/s written | cuRAND Philox4x32-10 | cuRAND call |
|---|---|---|---|
| `tandem_dev_next_real64` in a kernel | 1099 | 1411 | `curand_uniform_double` |
| `tandem_dev_next_int32` in a kernel | 635 | 1334 | `curand` |

The kernel module keeps its words as `int32` bit patterns, a draw from the cached block costs one
compare, and link-time optimization inlines the draws into the kernel. Before those changes the
rows read 244 and 174 GiB/s. They stay below cuRAND's: each Tandem draw advances the 64-bit stream
position, aligns it and checks its block, about 40 instructions per 32-bit draw in nvfortran's
code, while a cuRAND draw takes the next word of its four-word buffer.

### OpenMP target and do concurrent

Throughput on an NVIDIA A100 40 GB (PCIe), nvfortran 25.3, CUDA driver 570, 2^28 elements held
on the device, minimum of seven timings after two warm-up fills, in the window above. The CUDA
Fortran and cuRAND columns are the rows of `make -f cuda/Makefile bench` above. cuRAND has no
bounded integers, so that row's cuRAND figure is `curandGenerate`, marked "nearest":

| fill | CUDA Fortran | `_target` | `_stdpar` | cuRAND Philox4x32-10 |
|---|---|---|---|---|
| `real64` | 1392 GiB/s | 786 | 781 | 806 |
| `real32` | 1381 | 387 | 388 | 1329 |
| `int64` | 1393 | 1290 | 1279 | 1348, nearest |
| `int32` | 1383 | 481 | 1223 | 1336 |
| bounded `int32`, bound 1000 | not measured | 194 | 319 | 1336, nearest |

These run below the CUDA fills and cuRAND because each iteration writes whole blocks at a stride
of one row, the direct kernel's pattern: `do concurrent` and OpenMP target cannot stage rows
through shared memory as the tile kernel of `tandem.cuh` does. The `int64` fills reach the
direct kernel's rate. The others are compute bound in nvfortran's code for the portable module,
whose words are `int64` values: the `_target` `int64` fill ran at 780 GiB/s until a signed division
per element became a shift. LLVM flang with OpenMP offload to NVIDIA was not run: batserv01 has no
flang with an NVPTX offload runtime and the conda-forge flang lacks its intrinsic modules.
