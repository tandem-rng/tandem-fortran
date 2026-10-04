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

Normals are Box-Muller from two 64-bit draws, or two 32-bit float draws for `real32`. A step
gives two normals, the cos half and the sin half. `next_normal64` returns the cos half and
drops the other, `next_normal_pair64` returns both, and `fill_normal` is the flattened pairs:
an odd size keeps the cos half of its last pair and still consumes both uniforms. The host
normals are tandem.c's polynomial Box-Muller with explicit fused multiply-adds, the same bits
under every compiler.
