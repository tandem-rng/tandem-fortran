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

NVIDIA A100 40 GB (PCIe), CUDA 12.8, `make -f cuda/Makefile bench`, 2^28 elements:

| | GiB/s written |
|---|---|
| `tandem_device_fill_real64` | 1392 |
| `tandem_device_fill_real32` | 1395 |
| `tandem_device_fill_int64` | 1380 |
| `tandem_device_fill_int32` | 1411 |

These are the rates of `tandem.cuh`'s tile kernel, about the card's memory bandwidth.

Draws inside a kernel, `make -f cuda/Makefile bench-device`, nvfortran 25.3:

| | GiB/s written |
|---|---|
| `tandem_dev_next_real64` in a kernel | 243 |
| `tandem_dev_next_int32` in a kernel | 172 |

In the kernel module each 32-bit word is emulated in an `int64` with its products built from
16-bit halves, and each draw goes through the scalar alignment and cache check, so draws inside
a kernel run at about a sixth of the device fills.

### OpenMP target and do concurrent

Throughput on an NVIDIA A100 40 GB (PCIe), nvfortran 25.3, CUDA driver 570, 2^28 elements held
on the device, minimum of seven timings after two warm-up fills, GPU 1 idle before and during
the run (`nvidia-smi` listed only the benchmark). The CUDA Fortran row is
`tandem_device_fill_*`, measured in the same window with `make -f cuda/Makefile bench`:

| fill | CUDA Fortran | `_target` | `_stdpar` |
|---|---|---|---|
| `real64` | 1390 GiB/s | 781 | 777 |
| `real32` | 1381 | 389 | 389 |
| `int64` | 1393 | 775 | 1278 |
| `int32` | 1381 | 481 | 1199 |
| bounded `int32`, bound 1000 | not measured | 194 | 318 |

These run below the CUDA fills because each iteration writes whole blocks at a stride of one
row, where the tile kernel of `tandem.cuh` stages them through shared memory for coalesced
stores. LLVM flang with OpenMP offload to NVIDIA was not run: batserv01 has no flang with an
NVPTX offload runtime and the conda-forge flang lacks its intrinsic modules.
