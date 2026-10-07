# tandem-fortran

Fortran bindings for Tandem8x32. The module `tandem_rng` wraps the reference C implementation
and produces the stream of the
[specification](https://github.com/tandem-rng/spec/blob/main/SPEC.md) bit for bit. The GPU
modules write the same stream.

- [API](api.md): the CPU module, device fills, kernels, OpenMP target and `do concurrent`
  fills, and parallel use.
- [Design](design.md): the C mirror, bounded integers and normals.
- [Tests](tests.md): what the suite checks, where the fixtures come from, and what CI runs.
- [Speed](speed.md): CPU, A100 and offload figures.
- [nvfortran defects](nvfortran.md): the nvfortran 25.3 defects the code works around.

## Install

```sh
fpm build --profile release
fpm test
```

or add `tandem_rng = { git = "https://github.com/tandem-rng/tandem-fortran" }` to the
dependencies in your `fpm.toml`. `pixi run test` supplies gfortran and fpm from conda-forge.

Fortran 2018, fpm or any build that compiles `src/tandem_rng.f90` and `src/c/tandem.c`.
Tested with LLVM flang 21 (with clang for the C), gfortran and ifx.

The normal fills use explicit fused multiply-adds, and `tandem.c` picks the hardware `fma` at run
time on x86. Build it with `--c-flag -ffp-contract=off` in fpm, which keeps every other
expression unfused, so all compilers give the same normals. `pixi run test`, the CI jobs and the Makefiles set it.

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

`fpm install --profile release --prefix <prefix>` installs the library and the module files. The
`packaging/` directory holds a Spack recipe (`spack/package.py`) and a conda-forge style recipe
(`conda/recipe.yaml`) for the CPU module. Neither is submitted to Spack or conda-forge yet, and both
build from the `main` branch.

### Vendored sources

`src/c/tandem.c` and `src/c/tandem.h` come from
[tandem-c](https://github.com/tandem-rng/tandem-c), `src/c/tandem.cuh` and
`src/c/tandem/core.hpp` from
[tandem-cuda](https://github.com/tandem-rng/tandem-cuda), unchanged. `tools/sync_c.sh`
copies them and the dumps from the tandem-c and tandem-cuda commits pinned in it, and CI fails
when any of them differ. `test/conformance` holds copies of the specification's conformance
fixtures at tandem-spec 2a4bd08, and CI fails when they differ. `tandem.c` calls libm, so link with `-lm`; fpm does
this through `fpm.toml`.

## AI assistance

This port was written with the help of large language models under human
direction. The design and the specification are human work, as is much of the
Julia implementation. The code is tested bit for bit against every vector of
the specification and against long stream dumps from the Julia implementation,
and every value must match. The output does not depend on who or what wrote the
code.
