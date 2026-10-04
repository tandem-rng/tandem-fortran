#!/bin/sh
# Copy the vendored sources, the stream dumps and the cross-check module from the pinned
# commits of tandem-c and tandem-cuda. CI reruns this and fails on any difference, so a repin
# is an edit of the two commits below plus a run of this script.
# Usage: tools/sync_c.sh [path/to/tandem-c] [path/to/tandem-cuda], both git clones.
set -e
C_COMMIT=86ea14e640c71746e175836243f5c1fa1c849286
CUDA_COMMIT=5ceb466db1ea353889c1263a9d7ec36d7781a11c
c=${1:-../tandem-c}
cuda=${2:-../tandem-cuda}
root=$(cd "$(dirname "$0")/.." && pwd)
git -C "$c" show "$C_COMMIT:tandem.c" > "$root/src/c/tandem.c"
git -C "$c" show "$C_COMMIT:tandem.h" > "$root/src/c/tandem.h"
git -C "$cuda" show "$CUDA_COMMIT:tandem.cuh" > "$root/src/c/tandem.cuh"
git -C "$cuda" show "$CUDA_COMMIT:include/tandem/core.hpp" > "$root/src/c/tandem/core.hpp"
tests=$(mktemp -d)
trap 'rm -rf "$tests"' EXIT
git -C "$c" archive "$C_COMMIT" tests | tar -x -C "$tests"
cp "$tests"/tests/data/*.bin "$root/test/data/"
python3 "$root/tools/gen_cross.py" "$tests/tests" > "$root/test/cross.f90"
