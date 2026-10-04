<p align="center"><img src="assets/lockup.png" width="560" alt="tandem rng .f90"></p>

# tandem-fortran

Fortran bindings for [Tandem8x32](https://github.com/tandem-rng/spec), a noncryptographic
pseudorandom number generator built to be fast on CPUs and GPUs alike. The module
`tandem_rng` wraps a vendored copy of the reference C implementation and produces the stream
the specification defines, bit for bit. The module `tandem_rng_cuda` fills NVIDIA GPU memory
with the same stream.

- Fortran 2018, fpm or any build that compiles `src/tandem_rng.f90` and `src/c/tandem.c`.
  Tested with LLVM flang 21 (with clang for the C), gfortran and ifx.
- `type(tandem_t)` is a plain value. Assignment copies a generator, and the copy draws the
  same stream.
- Every type in the specification: `real64`, `real32`, `int64` to `int8`, `logical`,
  `complex`, 128-bit words, binary16 bit patterns, Unicode scalars. Fills take contiguous
  arrays of any rank, scalars included. Random access without advancing. Split by index,
  fork at the current block, sub by purpose.
- Bounded integers and normals, not part of the specification: they follow `tandem-cuda`, so
  every port returns the same values for the same generator.
- Device fills write what a CPU fill of the same generator would write and move the
  generator past them, so CPU draws and device fills interleave on one stream.
- With nvfortran, the module `tandem_rng_device` draws inside CUDA Fortran kernels: a
  per-thread generator whose draws equal the CPU draws for the same key and position.

## Use

```fortran
use tandem_rng

type(tandem_t) :: rng, worker, kids(4)
real(real64) :: x, z, zz(2), grid(100, 100)
integer(int32) :: words(1024), k

rng = tandem_new(42_int64)                  ! 128-bit seed: tandem_new(lo, hi), K optional
x = rng%next_real64()                       ! the spec's Float64 draw, in [0, 1)
call rng%fill(grid)                         ! any rank, in array element order
call tandem_random_number(rng, grid)        ! the same, spelled like random_number
call rng%fill(words)                        ! unsigned 32-bit words as int32 bit patterns
x = rng%at_real64(10_int64)                 ! element 10 of the fill from here, no advance
worker = rng%split(7_int64)                 ! by index, from the key alone
call rng%fork(kids)                         ! from the current block, parent moves on
k = rng%below(1000_int32)                   ! uniform on [0, 1000), int64 bounds work too
call rng%fill_below(words, 1000_int32)      ! any rank
z = rng%next_normal64()                     ! standard normal, next_normal32 for single
zz = rng%next_normal_pair64()               ! both halves of a Box-Muller step
call rng%fill_normal(grid)                  ! real64 or real32 arrays of any rank
print *, rng%key(), rng%position(), rng%chunk_length()
rng = tandem_from_key([1, 2, 3, 4], pos=0_int64, K=32)
```

Scalar draws: `next_real64`, `next_real32`, `next_int64`, `next_int32`, `next_int16`,
`next_int8`, `next_logical`, `next_complex64`, `next_complex32`, `next_int128`,
`next_real16_bits`, `next_char`. Fills: the generic `fill` for the first nine of those
types and for `logical(c_bool)`, and `fill_int128`, `fill_real16_bits`, `fill_char`. Random
access: `at_real64`, `at_real32`, `at_int64`, `at_int32`, indexed from 0 like the
specification.

`below(n)` is Lemire's multiply and reject over the 32-bit or 64-bit draw, as `Rng::urand`
of tandem-cuda. A rejected draw is discarded, so `below` consumes a varying number of draws,
and `n` is an unsigned bit pattern like every integer here. `fill_below(x, n)` maps draw `i`
of the plain fill to element `i`, and retries a rejected draw on a fallback generator, so it
consumes exactly `size(x)` draws and equals the scalar calls except where a draw is
rejected. Normals are Box-Muller from two 64-bit draws, or two 32-bit float draws for
`real32`. A step gives two normals, the cos half and the sin half. `next_normal64` returns
the cos half and drops the other, `next_normal_pair64` returns both, and `fill_normal` is the
flattened pairs: an odd size keeps the cos half of its last pair and still consumes both
uniforms. Normals agree with other ports to a few ulps, not bit for bit, since libm functions
differ between platforms.

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

The device fills are `tandem_device_fill_` plus `real64`, `real32`, `int64`, `int32`, `int16`,
`int8`, `logical`, `real16_bits`, `complex64`, `complex32`, `below_int32`, `below_int64`,
`normal_real64` or `normal_real32`. A logical takes one byte per element, so the memory is
`logical(c_bool)`, and `real16_bits` fills `int16` memory. The bounded fills take the bound
after the count, `tandem_device_fill_below_int32(rng, d, n, 1000_int32)`, and equal the host
`fill_below` bit for bit, rejected draws included. A normal fill is the flattened Box-Muller
pairs, as on the host, and agrees with it to a few ulps, since device `log`, `cos` and `sin`
differ from the host's in the last bits. The position moves exactly as it does for the host
fill.

Fills run asynchronously on the default stream. The allocation and copy helpers bind
`cudaMalloc`, `cudaMemcpy` and `cudaFree` for gfortran programs without CUDA Fortran. Each
call takes an optional `stat` and stops the program on a CUDA error without one.

With nvfortran `-cuda`, `tandem_rng_cuda_arrays` replaces `tandem_rng_cuda`. It exports the
same names, and every device fill above also takes contiguous `device` arrays of rank 1 to 3:

```fortran
use tandem_rng_cuda_arrays

real(real64), device, allocatable :: x(:, :)

allocate (x(1000, 1000))
call tandem_device_fill_real64(rng, x)      ! every element, in array element order
call tandem_device_fill_below_int32(rng, k, 1000_int32)  ! the bound follows the array
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

The rest of `tandem::Rng` is there too:

```fortran
type(tandem_dev_t) :: rng, kids(8)

call tandem_dev_fork(rng, kids, 5)             ! 5 children from the current block, parent moves on
x = tandem_dev_at_real64(rng, 10_int64)        ! element 10 of the fill from here, no advance;
                                               ! also _real32, _int64, _int32
k = tandem_dev_below_int32(rng, 1000_int32)    ! uniform on [0, 1000), also _int64
z = tandem_dev_next_normal64(rng)              ! cos half of a step, also _normal32
zz = tandem_dev_next_normal_pair64(rng)        ! both halves, also _pair32
```

These match the host `fork`, `at_*`, `below` and `next_normal64/32` for the same key and
position, the position after each included. `below` rejects and redraws as the C library does,
and 64-bit products come from 32-bit pieces, so a 64-bit bound costs more than a 32-bit one.
Device `log`, `cos` and `sin` differ from the host's in the last bits, so normals agree to a few
ulps.

### Integers are bit patterns

Fortran has no unsigned integers. Integer draws return the specification's unsigned value
reinterpreted as the signed type of the same width, so a 32-bit word above 2^31 - 1 comes
back negative. Use `iand(int(w, int64), int(z'ffffffff', int64))` for the unsigned value.
Seeds, positions, indices and purposes are 64-bit unsigned in the specification and pass the
same way. `tandem_new(seed)` takes the 64-bit pattern as the low half of the 128-bit seed.
Keys are four `int32` bit patterns, word 0 first.

## Parallel use

Element `i` of a fill, counted from 0, is draw `i`, at bit `64 i` for `real64`, so a rank or
thread that sets its generator to the position of its first element writes its part of one
global fill. `split` gives one stream per task from the key alone, and `sub` one per purpose.
Results then do not depend on the number of ranks or threads.
[Appendix B](https://github.com/tandem-rng/spec/blob/main/SPEC.md#appendix-b-parallel-decomposition-non-normative)
of the specification gives the patterns.

```fortran
mine = field                                ! a copy of the global generator
call mine%set_position(64 * first)          ! first element of this rank, from 0
call mine%fill(x(first + 1:first + count))
task = noise%split(task_index)              ! by task, not by rank
```

`example/mpi` fills a field of 2^24 doubles across MPI ranks or OpenMP threads, draws a batch
of normals per block from `split(block)`, and prints a hash of the result, the same hash as the
C example of tandem-c. `pixi run -e mpi check-mpi` builds it with MPICH and checks that 1, 2
and 4 ranks and 1, 4 and 14 threads print the hash of a serial run. CI runs the same check.

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

`test/test_sampling.f90` compares bounded integers, bounded fills and normal pairs with the
values `core.hpp` of tandem-cuda produces, including the end position, which pins the number of
rejected draws. The values come from tandem-c's `tests/cross_*.h` through
`tools/gen_cross.py` into `test/cross.f90`. It also checks that normal fills equal the pairs
from an unaligned start and that rank 3 fills equal rank 1 fills.

`cuda/test_cuda.f90` checks device fills against the vectors and the dumps, and against CPU
fills of the same generator for K from 1 to 256, six start positions, five lengths and four
output offsets, which runs both kernels of `tandem.cuh` and its aligned and unaligned stores.
It runs the narrow, complex, bounded and normal fills against CPU fills of the same
generator at several chunk lengths, starts, lengths and output offsets, the bounded fills also
against the cross fixtures, and the bounded and normal fills against the fixtures that
tandem-cuda derives on the device. It also interleaves CPU draws and device fills. `cuda/test_device.cuf` runs the kernel module
on the GPU against the vectors and against the C library's scalar draws, at four chunk
lengths, three keys and ten start positions, with mixed widths, splits and subs, and checks
a level 1 fill into a CUDA Fortran device array. It also compares device `below` and normals
with the host at bounds that reject a quarter of the draws, device `at_*` with the host's, and
`fork` children with the host's. GitHub runners have no GPU, so CI only builds
the gfortran CUDA part. The SDK is too large for CI, so the nvfortran part is tested by hand.
CI runs LLVM flang 21 from apt.llvm.org first, with clang for the C, then gfortran on Linux and
macOS and ifx on Linux, with warnings as errors and strict standard conformance. flang gets
`-Wno-interoperability`, because it warns about the `c_loc` of a default logical that the
logical fill uses. conda-forge's flang ships no intrinsic modules, so locally gfortran is the
default: macOS has no flang package. The pixi environments set `FPM_CC=clang`, and CI keeps
gcc compiling the C in the gfortran jobs as a check.

## Known nvfortran 25.3 defects

- `select rank` does not compile, and a `bind(C)` dummy procedure is called wrongly, so
  the code selects among specific procedures instead.
- `c_loc` and `c_devloc` of an assumed-rank argument of rank 2 and up return the address of
  the element at index zero in every dimension, not of the first element. The device array
  fills therefore have one specific per rank, and the host `fill` of arrays of rank 2 and up
  writes to a wrong address under nvfortran. Fill rank 1 arrays or sections there.

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
refreshes them from sibling checkouts, and CI fails when they, the dumps, the vector module or
the cross-check module drift from upstream. `tandem.c` calls libm, so link with `-lm`; fpm does
this through `fpm.toml`. `tandem_t` holds a field-for-field `bind(C)` mirror of the C struct
`tandem_rng`, so C reads it in place and returns it by value with the C layout. The tests
compare the mirror's size and field offsets with the header through `tandem_layout_matches`.

## AI assistance

This port was written with the help of large language models under human
direction. The design and the specification are human work, as is much of the
Julia implementation. The code is tested bit for bit against every vector of
the specification and against long stream dumps from the Julia implementation,
and every value must match. The output does not depend on who or what wrote the
code.

## License

Apache License 2.0. See `LICENSE` and `NOTICE`.
