# Design

## Generator layout

`tandem_t` holds a field-for-field `bind(C)` mirror of the C struct `tandem_rng`, so C reads it
in place and returns it by value with the C layout. The tests compare the mirror's size and
field offsets with the header through `tandem_layout_matches`.

## Bounded integers

`below(n)` is Lemire's multiply and reject over the 32-bit or 64-bit draw, as `Rng::urand`
of tandem-cuda. A rejected draw is discarded, so `below` consumes a varying number of draws,
and `n` is an unsigned bit pattern like every integer here. `fill_below(x, n)` maps draw `i`
of the plain fill to element `i`, and retries a rejected draw on a fallback generator keyed by
the global draw index, the aligned start position over the draw width plus `i`. It consumes
exactly `size(x)` draws, equals the scalar calls except where a draw is rejected, and a fill
cut at any element boundary equals the whole fill.

## Normals

`real64` normals are the 1024-layer ziggurat of Appendix A, one 64-bit draw each.
`next_normal64` and element `i` of a `real64` `fill_normal` take that draw. A draw that misses
the fast path, 0.43 % of them, continues on `split(g)` of `sub(0x4e524d3634)` of the key at
position 0, where `g` is the draw's global index. So a fill equals the scalar calls, and a fill
cut at any element equals the whole fill. An empty fill aligns the position to 64 bits. The
host and the CUDA C fills are tandem.c's and tandem.cuh's own, bit for bit.

The CUDA Fortran generator `tandem_dev_t` ports the ziggurat. Its tables come from the spec's
`tables/normal_f64_zig1024.json` through `tools/gen_zig_tables.py` into
`cuda/tandem_zig_tables.f90`, each Float64 as its bit pattern. The reference logarithm takes
libm's `fma` by `bind(C)`, which nvfortran resolves to the device's in kernels, and keeps
products out of sums, so its bits survive nvfortran's default contraction. nvfortran 25.3 has
no `ieee_fma`. `transfer` in host and device code does not link in the host pass, so the code
splits `x` with `fraction` and `exponent`, which give the same `m` and `k` exactly.

`real32` normals are Box-Muller from two 32-bit float draws. A step gives two normals, the cos
half and the sin half. `next_normal32` returns the cos half and drops the other,
`next_normal_pair32` returns both, and `fill_normal` is the flattened pairs: an odd size keeps
the cos half of its last pair and still consumes both uniforms. The host normals are tandem.c's
polynomial Box-Muller with explicit fused multiply-adds, the same bits under every compiler.
