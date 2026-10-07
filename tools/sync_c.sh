#!/bin/sh
# Copy the vendored sources and the stream dumps from the pinned commits of tandem-c and
# tandem-cuda. CI reruns this and fails on any difference, so a repin is an edit of the two
# commits below plus a run of this script.
# Usage: tools/sync_c.sh [path/to/tandem-c] [path/to/tandem-cuda], both git clones.
set -e
C_COMMIT=1c75956c39581836c1f6e190d1072c9a43be6b0d
CUDA_COMMIT=e98daeee1463724e4abfd3495da6b059d7815cc4
c=${1:-../tandem-c}
cuda=${2:-../tandem-cuda}
root=$(cd "$(dirname "$0")/.." && pwd)
git -C "$c" show "$C_COMMIT:tandem.c" > "$root/src/c/tandem.c"
git -C "$c" show "$C_COMMIT:tandem.h" > "$root/src/c/tandem.h"
git -C "$c" show "$C_COMMIT:tandem_normal_tables.h" > "$root/src/c/tandem_normal_tables.h"
git -C "$cuda" show "$CUDA_COMMIT:tandem.cuh" > "$root/src/c/tandem.cuh"
git -C "$cuda" show "$CUDA_COMMIT:include/tandem/core.hpp" > "$root/src/c/tandem/core.hpp"
git -C "$cuda" show "$CUDA_COMMIT:include/tandem/normal_tables.hpp" > "$root/src/c/tandem/normal_tables.hpp"
tests=$(mktemp -d)
trap 'rm -rf "$tests"' EXIT
git -C "$c" archive "$C_COMMIT" tests/data | tar -x -C "$tests"
cp "$tests"/tests/data/*.bin "$root/test/data/"
