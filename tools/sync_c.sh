#!/bin/sh
# Copy the vendored sources, the stream dumps and the cross-check module from the pinned
# commits of tandem-c and tandem-cuda. CI reruns this and fails on any difference, so a repin
# is an edit of the two commits below plus a run of this script.
# Usage: tools/sync_c.sh [path/to/tandem-c] [path/to/tandem-cuda], both git clones.
set -e
C_COMMIT=121db5902d6136c7e5258970c0160121af3ab1d0
CUDA_COMMIT=10c3bd2711f03f4b87988417737c2d904e402ab2
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
git -C "$c" archive "$C_COMMIT" tests | tar -x -C "$tests"
# tandem-c's copy of the device normal fixture predates the ziggurat, so take tandem-cuda's.
git -C "$cuda" show "$CUDA_COMMIT:tests/cross_fill_normal.h" > "$tests/tests/cuda_fill_normal.h"
cp "$tests"/tests/data/*.bin "$root/test/data/"
python3 "$root/tools/gen_cross.py" "$tests/tests" > "$root/test/cross.f90"
