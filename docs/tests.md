# Tests

```sh
pixi run test                       # fpm test
pixi run -e cuda test-cuda          # device fills, on a GPU host
make -f cuda/Makefile test-device   # the kernel module, with nvfortran
make -f target/Makefile test        # gfortran -fopenmp, target regions on the CPU
pixi run -e mpi check-mpi           # 1, 2 and 4 ranks print the hash of a serial run
```

## Suite

`test/test_vectors.f90` checks every vector of the specification. `test/test_stream.f90`
compares fills, scalar draws and random access with the reference stream dumps in `test/data`.
It also checks fills that start inside a row at eleven offsets against one whole fill,
alignment after draws of mixed widths, fills of any rank and strided sections, and the
elemental forms of `at_*`, `split` and `sub`.

`test/test_sampling.f90` compares bounded integers and bounded fills with the values `core.hpp`
of tandem-cuda produces, `real64` normal fills with tandem-c's ziggurat fixture at six starts,
whose last rows hold a wedge accept, a wedge reject and a tail value, and `real32` normal pairs
with tandem-c's, all bit for bit and including the end position, which pins the number of
rejected draws. It also checks that `real64` normal fills equal the `next_normal64` calls and
`real32` fills the pairs from an unaligned start, that an empty `real64` fill aligns the
position, and that rank 3 fills equal rank 1 fills. Exponential fills and scalar draws match
tandem-c's `tests/cross_exponential.h` bit for bit, end positions included. Bounded fills cut at arbitrary elements equal the whole
fill at an unaligned start, rejected draws included, and the OpenMP target and CUDA tests check
the same cut.

`cuda/test_cuda.f90` checks device fills against the vectors and the dumps, and against CPU
fills of the same generator for K from 1 to 256, six start positions, five lengths and four
output offsets, which runs both kernels of `tandem.cuh` and its aligned and unaligned stores.
It runs the narrow, complex, bounded and normal fills against CPU fills of the same
generator at several chunk lengths, starts, lengths and output offsets, `real64` normals bit
for bit at lengths that take one kernel and two, the bounded fills also against the cross
fixtures, and the bounded and normal fills against the fixtures that tandem-cuda derives on the
device. Exponential fills equal CPU fills bit for bit at three chunk lengths, three starts,
five lengths and two output offsets. Device `real64` normal and exponential fills match
tandem-c's `tests/cross_normal.h` and `tests/cross_exponential.h` rows bit for bit, end positions
included. It also interleaves CPU draws and device fills.
`cuda/test_device.cuf` runs the kernel module on the GPU against the vectors and against the C
library's scalar draws, at four chunk lengths, three keys and ten start positions, with mixed
widths, splits and subs, and checks a level 1 fill into a CUDA Fortran device array. It also
compares device `below` and normals with the host at bounds that reject a quarter of the
draws, device `at_*` with the host's, and `fork` children with the host's. 10^6 device
`real64` normals from each of the five starts of tandem-c's `tests/test_normal_bits.c`, about
21000 misses and 270 tail values, must equal the C fill bit for bit, and so must the host
compilation of the same procedures.

## Fixtures

`test/vectors.f90` is generated from the spec repository's `vectors.json` by
`tools/gen_vectors.py`. The reference stream dumps in `test/data` are copied from tandem-c.
The bounded, normal and exponential values come from tandem-c's `tests/cross_*.h` and the device normal
values from tandem-cuda's `tests/cross_fill_normal.h`, through `tools/gen_cross.py` into
`test/cross.f90`. `tools/sync_c.sh` refreshes the dumps and the cross-check module from the
pinned commits. `cuda/tandem_zig_tables.f90` comes from the spec's ziggurat tables through
`tools/gen_zig_tables.py`.

## CI

- CI builds with `--c-flag -ffp-contract=off`, as `pixi run test` and the Makefiles do.
- CI fails when the vendored sources, the dumps or the cross-check module differ from the
  pinned tandem-c and tandem-cuda commits, or the ziggurat tables from the spec's.
- GitHub runners have no GPU, so CI only builds the gfortran CUDA part, and the GPU tests run
  by hand.
- CI builds and runs the whole `target/` test with gfortran and flang, where the target
  regions run on the host.
- CI runs `pixi run -e mpi check-mpi`.
