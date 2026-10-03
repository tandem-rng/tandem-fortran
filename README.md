<p align="center"><img src="assets/lockup.png" width="560" alt="tandem rng .f90"></p>

# tandem-fortran

Fortran bindings for [Tandem8x32](https://github.com/tandem-rng/spec), a noncryptographic
pseudorandom number generator built to be fast on CPUs and GPUs alike. The module
`tandem_rng` wraps a vendored copy of the reference C implementation and produces the stream
the specification defines, bit for bit. The module `tandem_rng_cuda` fills NVIDIA GPU memory
with the same stream.

- Fortran 2018, fpm or any build that compiles `src/tandem_rng.f90` and `src/c/tandem.c`.
- `type(tandem_t)` is a plain value. Assignment copies a generator, and the copy draws the
  same stream.
- Every type in the specification: `real64`, `real32`, `int64` to `int8`, `logical`,
  `complex`, 128-bit words, binary16 bit patterns, Unicode scalars. Fills take contiguous
  arrays of any rank, scalars included. Random access without advancing. Split by index,
  fork at the current block, sub by purpose.
- Device fills write what a CPU fill of the same generator would write and move the
  generator past them, so CPU draws and device fills interleave on one stream.
- With nvfortran, the module `tandem_rng_device` draws inside CUDA Fortran kernels: a
  per-thread generator whose draws equal the CPU draws for the same key and position.

## Use

```fortran
use tandem_rng

type(tandem_t) :: rng, worker, kids(4)
real(real64) :: x, grid(100, 100)
integer(int32) :: words(1024)

rng = tandem_new(42_int64)                  ! 128-bit seed: tandem_new(lo, hi), K optional
x = rng%next_real64()                       ! the spec's Float64 draw, in [0, 1)
call rng%fill(grid)                         ! any rank, in array element order
call tandem_random_number(rng, grid)        ! the same, spelled like random_number
call rng%fill(words)                        ! unsigned 32-bit words as int32 bit patterns
x = rng%at_real64(10_int64)                 ! element 10 of the fill from here, no advance
worker = rng%split(7_int64)                 ! by index, from the key alone
call rng%fork(kids)                         ! from the current block, parent moves on
print *, rng%key(), rng%position(), rng%chunk_length()
rng = tandem_from_key([1, 2, 3, 4], pos=0_int64, K=32)
```

Scalar draws: `next_real64`, `next_real32`, `next_int64`, `next_int32`, `next_int16`,
`next_int8`, `next_logical`, `next_complex64`, `next_complex32`, `next_int128`,
`next_real16_bits`, `next_char`. Fills: the generic `fill` for the first nine of those
types and for `logical(c_bool)`, and `fill_int128`, `fill_real16_bits`, `fill_char`. Random
access: `at_real64`, `at_real32`, `at_int64`, `at_int32`, indexed from 0 like the
specification.

On the GPU, with device memory as a `type(c_ptr)`:

```fortran
use tandem_rng
use tandem_rng_cuda

type(c_ptr) :: d
real(real64), target :: host(n)

d = tandem_device_alloc(8 * n)
call tandem_device_fill_real64(rng, d, n)   ! also _real32, _int64, _int32
call tandem_copy_to_host(c_loc(host), d, 8 * n)
x = rng%next_real64()                       ! continues after the device fill
call tandem_device_free(d)
```

Fills run asynchronously on the default stream. The allocation and copy helpers bind
`cudaMalloc`, `cudaMemcpy` and `cudaFree` for gfortran programs without CUDA Fortran. Each
call takes an optional `stat` and stops the program on a CUDA error without one.

With nvfortran `-cuda`, `tandem_rng_cuda_arrays` replaces `tandem_rng_cuda`. It exports the
same names, and its device fills also take contiguous `device` arrays of rank 1 to 3:

```fortran
use tandem_rng_cuda_arrays

real(real64), device, allocatable :: x(:, :)

allocate (x(1000, 1000))
call tandem_device_fill_real64(rng, x)      ! every element, in array element order
```

Inside a CUDA Fortran kernel:

```fortran
use tandem_rng_device

attributes(global) subroutine kernel(key, out)
    integer(int32), device :: key(4)
    real(real64), device :: out(*)
    type(tandem_dev_t) :: rng
    integer :: i
    i = (blockIdx%x - 1) * blockDim%x + threadIdx%x
    rng = tandem_dev_split(tandem_dev_from_key(key, 0_int64, 32), int(i - 1, int64))
    out(i) = tandem_dev_next_real64(rng)
end subroutine
```

`tandem_dev_t` holds the transport form and one cached chunk state, like `tandem.cuh`'s
`device_rng`. `tandem_dev_from_key`, `tandem_dev_seed`, `tandem_dev_skip_to`,
`tandem_dev_next_real64/real32/int64/int32/logical`, `tandem_dev_split`, `tandem_dev_sub`,
and the building blocks `tandem_dev_apply_T`, `tandem_dev_apply_F`, `tandem_dev_F_keyed`,
`tandem_dev_block`. All are `attributes(host, device)`. Each 32-bit word lives in an
`int64` in [0, 2^32), and products are built from 16-bit halves, so no signed overflow
occurs.

### Integers are bit patterns

Fortran has no unsigned integers. Integer draws return the specification's unsigned value
reinterpreted as the signed type of the same width, so a 32-bit word above 2^31 - 1 comes
back negative. Use `iand(int(w, int64), int(z'ffffffff', int64))` for the unsigned value.
Seeds, positions, indices and purposes are 64-bit unsigned in the specification and pass the
same way. `tandem_new(seed)` takes the 64-bit pattern as the low half of the 128-bit seed.
Keys are four `int32` bit patterns, word 0 first.

## Build

```sh
fpm build --profile release
fpm test
```

or add `tandem_rng = { git = "https://github.com/tandem-rng/tandem-fortran" }` to the
dependencies in your `fpm.toml`. `pixi run test` supplies gfortran and fpm from conda-forge.

The GPU module needs CUDA, which fpm cannot compile, so `cuda/Makefile` builds the whole stack
with gfortran and nvcc. On a Linux host without a system CUDA install:

```sh
pixi run -e cuda test-cuda
```

The kernel module needs nvfortran from the NVIDIA HPC SDK, which installs without root from
NVIDIA's tarball. With `nvfortran` and `nvcc` on the `PATH`:

```sh
make -f cuda/Makefile test-device
```

## Tests

`test/test_vectors.f90` checks every vector of the specification. `test/vectors.f90` is
generated from the spec repository's `vectors.json` by `tools/gen_vectors.py`.
`test/test_stream.f90` compares fills, scalar draws and random access with the reference
stream dumps in `test/data`, copied from tandem-c. It also checks fills that start inside a
row at eleven offsets against one whole fill, alignment after draws of mixed widths, fills
of any rank and strided sections.

`cuda/test_cuda.f90` checks device fills against the vectors and the dumps, and against CPU
fills of the same generator for K from 1 to 256, six start positions, five lengths and four
output offsets, which runs both kernels of `tandem.cuh` and its aligned and unaligned stores.
It also interleaves CPU draws and device fills. `cuda/test_device.cuf` runs the kernel module
on the GPU against the vectors and against the C library's scalar draws, at four chunk
lengths, three keys and ten start positions, with mixed widths, splits and subs, and checks
a level 1 fill into a CUDA Fortran device array. GitHub runners have no GPU, so CI only builds
the gfortran CUDA part. The SDK is too large for CI, so the nvfortran part is tested by hand.
CI runs gfortran on Linux and macOS and ifx on Linux, with warnings as errors and strict
standard conformance.

## Speed

Apple M4, one thread, `pixi run bench` (fpm release profile, gfortran 16 and GCC 16 for the
C part), 2^24 elements, minimum of seven runs after a half-second warm-up:

| | GiB/s |
|---|---|
| `rng%fill`, `real64` array | 17.4 |
| `rng%fill`, `real32` array | 17.4 |
| `rng%fill`, `int32` array | 20.1 |
| `rng%fill`, `int64` array | 20.5 |
| `rng%next_real64()` in a loop | 4.4 |
| intrinsic `random_number`, `real64` array | 10.3 |
| intrinsic `random_number`, `real32` array | 4.9 |

The fills run at the speed of the C library, and clang for the C part (`FPM_CC=clang`) gives
the same figures. The scalar loop pays a call into C per draw.

NVIDIA A100 40 GB (PCIe), CUDA 12.8, `make -f cuda/Makefile bench`: 2^28 elements into device
memory, minimum of 21 `cudaEvent` timings per row after a half-second warm-up, GPU idle
before the run. Three consecutive runs agreed within 4%.

| | GiB/s written |
|---|---|
| `tandem_device_fill_real64` | 1392 |
| `tandem_device_fill_real32` | 1395 |
| `tandem_device_fill_int64` | 1380 |
| `tandem_device_fill_int32` | 1411 |

These are the rates of `tandem.cuh`'s tile kernel, about the card's memory bandwidth.

Draws inside a kernel, `make -f cuda/Makefile bench-device` (nvfortran 25.3): one
`tandem_dev_t` per chunk at K = 32, each walking its 32 blocks and storing them where the
stream puts them, so the output equals the fills above, which the bench checks first. Same
size, timing and idle check:

| | GiB/s written |
|---|---|
| `tandem_dev_next_real64` in a kernel | 243 |
| `tandem_dev_next_int32` in a kernel | 172 |

Each 32-bit word is emulated in an `int64` with its products built from 16-bit halves, and
each draw goes through the scalar alignment and cache check, so these run at about a sixth
of the fills above.

## Vendored sources

`src/c/tandem.c` and `src/c/tandem.h` come from
[tandem-c](https://github.com/tandem-rng/tandem-c), `src/c/tandem.cuh` and
`src/c/tandem/core.hpp` from
[tandem-cuda](https://github.com/tandem-rng/tandem-cuda), unchanged. `tools/sync_c.sh`
refreshes them from sibling checkouts, and CI fails when they, the dumps or the vector module
drift from upstream. `tandem_t` holds a field-for-field `bind(C)` mirror of the C struct
`tandem_rng`, so C reads it in place and returns it by value with the C layout. The tests
compare the mirror's size and field offsets with the header through `tandem_layout_matches`.

## License

Apache License 2.0. See `LICENSE` and `NOTICE`.
