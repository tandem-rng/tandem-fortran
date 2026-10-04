#!/usr/bin/env bash
set -euo pipefail

# fpm builds the Fortran module and the vendored C sources, then installs the library and
# the module files.
fpm install --profile release --prefix "${PREFIX}" --compiler "${FC}" --c-compiler "${CC}"
