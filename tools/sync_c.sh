#!/bin/sh
# Copy the vendored sources, the stream dumps and the cross-check module from the pinned
# commits of tandem-c and tandem-cuda. CI reruns this and fails on any difference, so a repin
# is an edit of the two commits below plus a run of this script.
# Usage: tools/sync_c.sh [path/to/tandem-c] [path/to/tandem-cuda], both git clones.
set -e
C_COMMIT=8f1f057d21b58fd97026298eef0b40a55b9e25fe
CUDA_COMMIT=5806e517c0948b32102cf8c1614f85b7bdbdf757
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
