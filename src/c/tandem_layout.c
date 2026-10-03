/* The size and field offsets of tandem_rng, for the Fortran module to check its bind(C)
 * mirror against the vendored header. Copyright 2026 Jessica Cox. Apache License 2.0. */
#include "tandem.h"

#include <stddef.h>

size_t tandem_layout(size_t offsets[6]) {
    offsets[0] = offsetof(tandem_rng, key);
    offsets[1] = offsetof(tandem_rng, pos);
    offsets[2] = offsetof(tandem_rng, K);
    offsets[3] = offsetof(tandem_rng, cached);
    offsets[4] = offsetof(tandem_rng, row);
    offsets[5] = offsetof(tandem_rng, o);
    return sizeof(tandem_rng);
}
