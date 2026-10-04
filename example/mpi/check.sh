#!/bin/sh
# Every rank and thread count must print the hash of the serial run.
set -eu
cd "$(dirname "$0")"
if ! log=$(fpm install --compiler mpifort --flag "-O2 -fopenmp -Wall" --prefix build/install 2>&1); then
    echo "$log" >&2
    exit 1
fi
bin=build/install/bin
ref=$("$bin/serial")
echo "serial      $ref"
status=0
for p in 1 2 4; do
    h=$(mpiexec -n "$p" "$bin/mpi")
    echo "mpi $p ranks $h"
    [ "$h" = "$ref" ] || status=1
done
for t in 1 4 14; do
    h=$(OMP_NUM_THREADS=$t "$bin/omp")
    echo "omp $t threads $h"
    [ "$h" = "$ref" ] || status=1
done
[ $status -eq 0 ] || echo "hashes differ" >&2
exit $status
