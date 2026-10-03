#!/bin/sh
# Copy the vendored sources from checkouts of tandem-c and tandem-cuda.
# Usage: tools/sync_c.sh [path/to/tandem-c] [path/to/tandem-cuda]
set -e
c=${1:-../tandem-c}
cuda=${2:-../tandem-cuda}
dst="$(dirname "$0")/../src/c/"
cp "$c/tandem.c" "$c/tandem.h" "$dst"
mkdir -p "$dst/tandem"
cp "$cuda/tandem.cuh" "$dst"
cp "$cuda/include/tandem/core.hpp" "$dst/tandem/"
