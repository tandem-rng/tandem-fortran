<p align="center"><img src="assets/lockup.png" width="560" alt="tandem rng .f90"></p>

# tandem-fortran

Fortran bindings for [Tandem8x32](https://github.com/tandem-rng/spec), a noncryptographic
random number generator. The module `tandem_rng` wraps the reference C implementation and
writes the specification's stream bit for bit. The GPU modules write the same stream, fast on
CPUs and GPUs.

## Install

```sh
fpm build --profile release --c-flag -ffp-contract=off
```

Or add `tandem_rng = { git = "https://github.com/tandem-rng/tandem-fortran" }` to `fpm.toml`.
`fpm install --profile release --prefix <prefix>` installs the library and modules.
Needs Fortran 2018. Tested with LLVM flang 21, gfortran and ifx. The flag keeps normals equal
across compilers. `src/c` vendors tandem-c and tandem-cuda sources, refreshed by
`tools/sync_c.sh`. Recipes for Spack and conda-forge sit in `packaging/`.

The GPU modules need CUDA, which fpm cannot build. `pixi run -e cuda test-cuda` builds them
with gfortran and nvcc. `make -f cuda/Makefile test-device` builds the kernel module with
nvfortran from the NVIDIA HPC SDK. Under nvfortran 25.3, fill rank 1 arrays on the host, since
`c_loc` of assumed-rank arguments of rank 2 and up returns a wrong address.

Full notes on the API, GPU modules, target offload, tests and speed:
[docs/notes.md](docs/notes.md).

## Use

```fortran
use tandem_rng

type(tandem_t) :: rng, worker, kids(4)
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
```

```fortran
use tandem_rng_cuda

d = tandem_device_alloc(8 * n)
call tandem_device_fill_real64(rng, d, n)   ! also _real32, _int64, _int32
call tandem_copy_to_host(c_loc(host), d, 8 * n)
x = rng%next_real64()                       ! continues after the device fill
call tandem_device_free(d)
```

## What it provides

- `type(tandem_t)`: a plain value. Assignment copies a generator.
- `next_real64`, `next_real32`, `next_int64` to `next_int8`, `next_logical`, `next_complex64`,
  `next_complex32`, `next_int128`, `next_real16_bits`, `next_char`: scalar draws.
- `fill`: the first nine types and `logical(c_bool)`, any rank. Also `fill_int128`,
  `fill_real16_bits`, `fill_char`, and `tandem_random_number(rng, a)`.
- `at_real64`, `at_real32`, `at_int64`, `at_int32`: random access from 0, no advance.
- `split(i)`, `fork(kids)`, `sub(purpose)`, `key()`, `position()`, `set_position(p)`,
  `chunk_length()`, `tandem_from_key`: children and transport form.
- `below(n)`, `fill_below(x, n)`: bounded `int32` and `int64` by Lemire's method.
- `next_normal64`, `next_normal32`, `next_normal_pair64`, `fill_normal`: Box-Muller normals.
- `tandem_device_fill_` plus `real64`, `real32`, `int64`, `int32`, `int16`, `int8`, `logical`,
  `real16_bits`, `complex64`, `complex32`, `below_int32`, `below_int64`, `normal_real64`,
  `normal_real32`: device fills in `tandem_rng_cuda`. They move the generator as a CPU fill does.
- `tandem_rng_cuda_arrays` with nvfortran `-cuda`: the same fills on `device` arrays of rank 1 to 3.
- `tandem_rng_device` with nvfortran: `tandem_dev_t` draws inside CUDA Fortran kernels, with
  `tandem_dev_from_key`, `tandem_dev_split`, `tandem_dev_sub`, `tandem_dev_fork`,
  `tandem_dev_at_real64`, `tandem_dev_below_int32`, `tandem_dev_next_real64`, and normals.
- `tandem_rng_target`, in `target/`: `tandem_fill_target` for OpenMP target offload and
  `tandem_fill_stdpar` for `do concurrent`, plus `tandem_fill_below_target` and
  `tandem_fill_below_stdpar`. They cover `int32`, `int64`, `real32` and `real64` of rank 1.
- Parallel use: a rank that calls `set_position` at its first element writes its part of one
  global fill. `example/mpi` shows it with MPI and OpenMP.

Integer draws are the specification's unsigned value as the signed type of the same width,
so use `iand(int(w, int64), int(z'ffffffff', int64))` for the unsigned value. Seeds, positions
and indices pass the same way. Bounded draws and normals are not in the specification. Normals
agree with other ports and devices to a few ulps.

## Tests

`pixi run test` runs `fpm test`.

- Every vector of the specification, from `test/vectors.f90`, made by `tools/gen_vectors.py`.
- Stream dumps in `test/data` from tandem-c, with cuts at many offsets.
- Bounded and normal fills against fixtures from tandem-c through `tools/gen_cross.py`.
- Device fills against CPU fills over chunk lengths, starts, lengths and offsets
  (`cuda/test_cuda.f90`, `cuda/test_device.cuf`). These run by hand on a GPU host.
- `pixi run -e mpi check-mpi`: 1, 2 and 4 ranks print the hash of a serial run.

## Speed

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

NVIDIA A100 40 GB (PCIe), CUDA 12.8, `make -f cuda/Makefile bench`, 2^28 elements:

| | GiB/s written |
|---|---|
| `tandem_device_fill_real64` | 1392 |
| `tandem_device_fill_real32` | 1395 |
| `tandem_device_fill_int64` | 1380 |
| `tandem_device_fill_int32` | 1411 |


Draws inside a kernel, `make -f cuda/Makefile bench-device`, nvfortran 25.3:

| | GiB/s written |
|---|---|
| `tandem_dev_next_real64` in a kernel | 243 |
| `tandem_dev_next_int32` in a kernel | 172 |


`target/` fills on the same A100, nvfortran 25.3, `make -f target/Makefile bench FC=nvfortran
CC=gcc FFLAGS="-O2 -mp=gpu -stdpar=gpu -gpu=cc80"`:

| fill | CUDA Fortran | `_target` | `_stdpar` |
|---|---|---|---|
| `real64` | 1390 GiB/s | 781 | 777 |
| `real32` | 1381 | 389 | 389 |
| `int64` | 1393 | 775 | 1278 |
| `int32` | 1381 | 481 | 1199 |
| bounded `int32`, bound 1000 | not measured | 194 | 318 |


## AI assistance

This port was written with the help of large language models under human
direction. The design and the specification are human work, as is much of the
Julia implementation. The code is tested bit for bit against every vector of
the specification and against long stream dumps from the Julia implementation,
and every value must match. The output does not depend on who or what wrote the
code.

## License

Apache License 2.0. See `LICENSE` and `NOTICE`.
