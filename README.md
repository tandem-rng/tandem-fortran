<p align="center"><img src="assets/lockup.png" width="560" alt="tandem rng .f90"></p>

# tandem-fortran

[![CI](https://github.com/tandem-rng/tandem-fortran/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/tandem-rng/tandem-fortran/actions/workflows/ci.yml)
[![Docs](https://img.shields.io/badge/docs-tandem--rng.github.io-7fb3ee.svg)](https://tandem-rng.github.io/tandem-fortran/)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache_2.0-blue.svg)](LICENSE)

Fortran bindings for [Tandem8x32](https://github.com/tandem-rng/spec), a noncryptographic
random number generator. The module `tandem_rng` wraps tandem-c and writes the specification's
stream bit for bit. CUDA, CUDA Fortran, OpenMP target and `do concurrent` modules write the same
stream on GPUs.

It needs Fortran 2018. `src/c` vendors tandem-c ef67bd7 and tandem-cuda fd8f2ff.

```sh
fpm build --profile release --c-flag -ffp-contract=off   # or tandem_rng as an fpm git dependency
```

```fortran
use tandem_rng

type(tandem_t) :: rng, worker
real(real64) :: grid(100, 100)

rng = tandem_new(42_int64)                  ! 128-bit seed: tandem_new(lo, hi), K optional
call rng%fill(grid)                         ! any rank, in array element order
worker = rng%split(7_int64)                 ! by index, from the key alone
call worker%fill_normal(grid)               ! normals, bit identical to tandem-c
```

See the [documentation](https://tandem-rng.github.io/tandem-fortran/) for the API, GPU modules,
tests and speed.

Portions of the code were generated with the assistance of LLMs.

[Documentation](https://tandem-rng.github.io/tandem-fortran/) · [Apache 2.0 license](LICENSE)
