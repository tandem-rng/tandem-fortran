# API

## Use

```fortran
use tandem_rng

type(tandem_t) :: rng, worker, kids(4)
type(tandem_choice_t) :: table
real(real64) :: x, z, zz(2), grid(100, 100)
integer(int32) :: words(1024), k

rng = tandem_new(42_int64)                  ! 128-bit seed: tandem_new(lo, hi), K optional
x = rng%next_real64()                       ! the spec's Float64 draw, in [0, 1)
call rng%fill(grid)                         ! any rank, in array element order
call rng%fill(words)                        ! unsigned 32-bit words as int32 bit patterns
x = rng%at_real64(10_int64)                 ! element 10 of the fill from here, no advance
worker = rng%split(7_int64)                 ! by index, from the key alone
call rng%fork(kids)                         ! from the current block, parent moves on
k = rng%below(1000_int32)                   ! uniform on [0, 1000)
call rng%fill_normal(grid)                  ! real64 or real32 arrays of any rank
call table%build([1.0_real64, 2.5_real64])  ! weighted choice, Appendix C
call rng%fill_choice(words, table)          ! indices in [0, 2), any rank
```

## Reference

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
- Without CUDA Fortran, `tandem_rng_target` fills the GPU through OpenMP target offload or
  `do concurrent`, in plain Fortran, with the same output as the CPU fills.
- With nvfortran, the module `tandem_rng_device` draws inside CUDA Fortran kernels: a
  per-thread generator whose draws equal the CPU draws for the same key and position.

Scalar draws: `next_real64`, `next_real32`, `next_int64`, `next_int32`, `next_int16`,
`next_int8`, `next_logical`, `next_complex64`, `next_complex32`, `next_int128`,
`next_real16_bits`, `next_char`. Fills: the generic `fill` for the first nine of those
types and for `logical(c_bool)`, and `fill_int128`, `fill_real16_bits`, `fill_char`, and
`tandem_random_number(rng, a)` in the shape of the intrinsic `random_number`. Random
access: `at_real64`, `at_real32`, `at_int64`, `at_int32`, indexed from 0 like the
specification. These, `split` and `sub` are elemental, so `rng%at_real64(idx)` and
`rng%split(idx)` take an index array.

`below(n)` and `fill_below(x, n)` give bounded integers, and `next_normal64`, `next_normal32`,
`next_normal_pair32` and `fill_normal` give normals, and `next_exponential64`,
`next_exponential32` and `fill_exponential` give standard exponentials -log(1 - u) of one
uniform each, bit for bit with tandem-c. [Design](design.md) says how they draw.

`type(tandem_choice_t)` is a weighted choice table, Appendix C of the specification.
`call table%build(weights, ok)` builds it from `real64` weights that are finite, not negative
and not all zero. Otherwise `ok` is false, or the program stops without `ok`. `choice(table)`
returns an `int32` index in [0, m), counted from 0 like `below`, from one 64-bit draw.
`fill_choice(x, table)` fills `int32` arrays of any rank: element `i` maps draw `i`, so a fill
equals `size(x)` calls of `choice`, and an empty fill aligns the position to 64 bits.
`capacity()`, `cut()` and `alias()` return the table, bit for bit with every port.

`set_position(pos, ok)` refuses a start at or past 2^63, that is a negative `pos`, and leaves
the generator unchanged. Then `ok` is false, or the program stops without `ok`. Draws and fills
may still run past 2^63.

### Integers are bit patterns

Fortran has no unsigned integers. Integer draws return the specification's unsigned value
reinterpreted as the signed type of the same width, so a 32-bit word above 2^31 - 1 comes
back negative. Use `iand(int(w, int64), int(z'ffffffff', int64))` for the unsigned value.
Seeds, positions, indices and purposes are 64-bit unsigned in the specification and pass the
same way. `tandem_new(seed)` takes the 64-bit pattern as the low half of the 128-bit seed.
Keys are four `int32` bit patterns, word 0 first.

## Device fills

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
`normal_real64`, `normal_real32`, `exponential_real64`, `exponential_real32` or `choice`. A logical takes one byte per element, so the memory is
`logical(c_bool)`, and `real16_bits` fills `int16` memory. The bounded fills take the bound
after the count, `tandem_device_fill_below_int32(rng, d, n, 1000_int32)`, and equal the host
`fill_below` bit for bit, rejected draws included. A `real64` normal fill runs tandem.cuh's
ziggurat and equals the host fill bit for bit. A `real32` one is the flattened Box-Muller
pairs, as on the host, with the device's fast sine and cosine, and agrees to a few ulps.
Exponential fills equal the host fills bit for bit. The position moves exactly as it does for the host fill.

A choice fill reads a copy of the table in device memory. `tandem_device_choice_upload(table,
d_table)` copies a built `tandem_choice_t`, `tandem_device_fill_choice(rng, d, n, d_table)`
writes `int32` indices equal to the host `fill_choice`, and `tandem_device_choice_free(d_table)`
releases the copy.

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

## Kernels

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
`tandem_dev_block`. All are `attributes(host, device)`. The generator keeps its words as
`int32` bit patterns and forms each product and sum in `int64`, so no signed overflow occurs. The
building blocks take words as `int64` values in [0, 2^32). Build kernels that draw with
`-gpu=lto`: without link-time optimization each draw in a kernel of another module is a call, and
the A100 draws about a third as fast.

The rest of `tandem::Rng` is there too:

```fortran
type(tandem_dev_t) :: rng, kids(8)

call tandem_dev_fork(rng, kids, 5)             ! 5 children from the current block, parent moves on
x = tandem_dev_at_real64(rng, 10_int64)        ! element 10 of the fill from here, no advance;
                                               ! also _real32, _int64, _int32
k = tandem_dev_below_int32(rng, 1000_int32)    ! uniform on [0, 1000), also _int64
z = tandem_dev_next_normal64(rng)              ! ziggurat of one 64-bit draw
y = tandem_dev_next_normal32(rng)              ! cos half of a real32 step
yy = tandem_dev_next_normal_pair32(rng)        ! both halves of the step
```

These match the host `fork`, `at_*`, `below` and `next_normal64/32` for the same key and
position, the position after each included. `below` rejects and redraws as the C library does,
and 64-bit products come from 32-bit pieces, so a 64-bit bound costs more than a 32-bit one.
`real64` normals equal the host's bit for bit. Device `log`, `cos` and `sin` differ from the
host's in the last bits, so `real32` normals agree to a few ulps. Build the module with its
table module `cuda/tandem_zig_tables.f90`, as `cuda/Makefile` does.

## OpenMP target and do concurrent

`target/tandem_rng_target.f90` is plain Fortran for compilers that offload standard Fortran,
no CUDA Fortran needed. It lives outside `src`, so the fpm build does not see it.

```fortran
use tandem_rng
use tandem_rng_target

real(real64), allocatable :: x(:)
integer(int32), allocatable :: k(:)

allocate (x(n), k(n))
!$omp target enter data map(alloc: x, k)    ! optional: otherwise each call maps the array
call tandem_fill_target(rng, x)             ! !$omp target teams distribute parallel do
call tandem_fill_stdpar(rng, x)             ! do concurrent, for nvfortran -stdpar=gpu
call tandem_fill_below_target(rng, k, 1000_int32)  ! also tandem_fill_below_stdpar
```

The fills are generic over `int32`, `int64`, `real32` and `real64` arrays of rank 1, and the
bounded fills over `int32` and `int64`. Each writes what the CPU fill of the same generator
writes, bit for bit, and moves the generator past it, so the fills interleave with CPU draws
as the CUDA fills do. One iteration owns one chunk, as in the direct kernel of `tandem.cuh`.
Normals are not offered: matching the host bit for bit needs tandem.c's ziggurat and its
fallback generators, which this module does not port.

```sh
make -f target/Makefile test                      # gfortran -fopenmp, target regions on the CPU
make -f target/Makefile test FC=nvfortran CC=gcc FFLAGS="-O2 -mp=gpu -stdpar=gpu -gpu=cc80"
make -f target/Makefile bench FC=nvfortran CC=gcc FFLAGS="-O2 -mp=gpu -stdpar=gpu -gpu=cc80"
```

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
and 4 ranks and 1, 4 and 14 threads print the hash of a serial run.
