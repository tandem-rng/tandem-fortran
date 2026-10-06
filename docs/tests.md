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

`test/test_conformance.f90` reads the specification's conformance fixtures and shows each
section of tandem-spec's `conformance/CHECKLIST.md`, all bit for bit:

| section | check |
|---|---|
| Fallback by global draw index | every case of `fill_below.json` and `normal.json`, and the shift of `CROSS_BELOW32_AT[4]`, `CROSS_BELOW64_AT[6]` and `CROSS_NORMAL[1]` by one element |
| Width from range | the integer kind names the width: `int32` and `int64` range 1000 fills match `CROSS_BELOW32[3]` and `CROSS_BELOW64[3]`, and range 0 returns 0 and takes one draw |
| n = 0 | the seven empty cases, end position only |
| Odd n | `CROSS_NORMAL32[0]` to `[4]`, end `align(start, 32) + 64 ceil(n / 2)` |
| Pair rule | `CROSS_NORMALF`, its first 33 values against `CROSS_NORMAL32[1]`, the scalar cos half and its two draws, the shift of `CROSS_NORMAL32[2]` by one pair |
| Weighted choice | the tables of the `vectors.json` cases, every case of `choice.json`, the shift of `CROSS_CHOICE[1]`, scalar draws, m = 1, and weights that build no table |
| Cut fill | every fill case cut at elements 1, 7, 20, 21 and n - 1, Float32 normals between pairs only, and n scalar draws for the bounded, Float64 normal, exponential and choice cases |
| Block and 2^63 boundaries | the SHA-256 of every stream of `hashes.json` from the fills, the FNV-1a of every long output, complex draws across a block, starts 2^63 - 1, 2^63 and 2^64 - 1, and a 64-bit draw at 2^63 - 1 |

The specification's last item, a fill whose end reaches 2^64, is not checked: tandem.c, which
the module binds, does not refuse it.

`test/test_sampling.f90` checks that `real64` normal fills equal the `next_normal64` calls and
`real32` fills the pairs from an unaligned start, that an empty `real64` fill aligns the
position, and that rank 3 bounded, normal and choice fills equal rank 1 fills. Bounded fills of
1000 elements cut at arbitrary elements equal the whole fill at an unaligned start, rejected
draws included, and the OpenMP target and CUDA tests check the same cut.

`cuda/test_cuda.f90` checks device fills against the vectors and the dumps, and against CPU
fills of the same generator for K from 1 to 256, six start positions, five lengths and four
output offsets, which runs both kernels of `tandem.cuh` and its aligned and unaligned stores.
It runs the narrow, complex, bounded and normal fills against CPU fills of the same
generator at several chunk lengths, starts, lengths and output offsets, `real64` normals bit
for bit at lengths that take one kernel and two. Exponential and choice fills equal CPU fills
bit for bit at three chunk lengths, three starts and several lengths. Every case of
`fill_below.json`, `normal.json`, `exponential.json` and `choice.json` runs on the device, whole
and cut, with the second piece right after the first in device memory: bit for bit with the end
position, except that `real32` normals match to the fixtures' tolerance. The device fills of ten
stream types match the SHA-256 of `hashes.json`, and the `real64` normal and the exponential
fills of 10^6 elements from five starts match its FNV-1a. It also interleaves CPU draws and
device fills.
`cuda/test_device.cuf` runs the kernel module on the GPU against the vectors and against the C
library's scalar draws, at four chunk lengths, three keys and ten start positions, with mixed
widths, splits and subs, and checks level 1 fills, choice included, into CUDA Fortran device
arrays. It also
compares device `below` and normals with the host at bounds that reject a quarter of the
draws, device `at_*` with the host's, and `fork` children with the host's. 10^6 device
`real64` normals from each of the five starts of tandem-c's `tests/test_normal_bits.c`, about
21000 misses and 270 tail values, must equal the C fill bit for bit, and so must the host
compilation of the same procedures.

## Fixtures

`test/vectors.f90` is generated from the spec repository's `vectors.json` by
`tools/gen_vectors.py`. The reference stream dumps in `test/data` are copied from tandem-c,
and `tools/sync_c.sh` refreshes them from the pinned commit. `test/conformance/*.json` are
byte-identical copies of tandem-spec f420545 `conformance/`, read at run time by
`test/conformance.f90`, which also holds the SHA-256 and FNV-1a of `hashes.json`. The OpenMP
target test runs every case of `fill_below.json` and the stream hashes of its four types. `cuda/tandem_zig_tables.f90` comes from the spec's ziggurat tables through
`tools/gen_zig_tables.py`.

## CI

- CI builds with `--c-flag -ffp-contract=off`, as `pixi run test` and the Makefiles do.
- CI fails when the vendored sources or the dumps differ from the pinned tandem-c and
  tandem-cuda commits, the conformance copies from tandem-spec f420545, or the ziggurat tables
  from the spec's.
- GitHub runners have no GPU, so CI only builds the gfortran CUDA part, and the GPU tests run
  by hand.
- CI builds and runs the whole `target/` test with gfortran and flang, where the target
  regions run on the host.
- CI runs `pixi run -e mpi check-mpi`.
