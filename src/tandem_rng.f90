! Tandem8x32 for Fortran: bindings to the reference C implementation vendored in src/c.
! Copyright 2026 Jessica Cox. Apache License 2.0, see LICENSE.
module tandem_rng
    use, intrinsic :: iso_c_binding, only: c_bool, c_double, c_double_complex, c_float, &
        c_f_pointer, c_float_complex, c_int16_t, c_int32_t, c_int64_t, c_int8_t, c_loc, c_null_ptr, &
        c_ptr, c_size_t, c_sizeof
    use, intrinsic :: iso_fortran_env, only: compiler_version, int8, int16, int32, int64, real32, &
        real64
    implicit none
    private

    public :: tandem_t, tandem_choice_t, tandem_new, tandem_from_key, tandem_random_number
    public :: tandem_apply_T, tandem_apply_F, tandem_F_keyed, tandem_block, tandem_layout_matches

    integer(int32), parameter, public :: TANDEM_DEFAULT_K = 32

    logical, parameter :: NVFORTRAN = index(compiler_version(), "nvfortran") > 0

    ! Field-for-field mirror of the C struct tandem_rng, so C can take it by reference and
    ! return it by value with the C layout. o(i, slot) is C's o[slot][i], h(lane, word) is
    ! C's h[word][lane].
    type, bind(C) :: rng_state
        integer(c_int32_t) :: key(4) = 0
        integer(c_int64_t) :: pos = 0
        integer(c_int32_t) :: K = TANDEM_DEFAULT_K
        integer(c_int32_t) :: cached = 0
        integer(c_int64_t) :: ahead = 0
        ! The row before pos, as tandem_from_key sets it: the C inline draws skip the refill
        ! whenever pos - base is inside one row, so base = 0 would read the empty cache.
        integer(c_int64_t) :: base = -1024
        integer(c_int32_t) :: o(32, 2) = 0
        integer(c_int32_t) :: h(8, 4) = 0
    end type

    type, bind(C) :: u128
        integer(c_int64_t) :: lo, hi
    end type

    ! Mirror of the C struct tandem_choice_table, rebuilt for each call from tandem_choice_t,
    ! whose arrays a copy of the table may move.
    type, bind(C) :: choice_table
        integer(c_int64_t) :: capacity = 0
        type(c_ptr) :: cut = c_null_ptr, alias = c_null_ptr
        integer(c_int32_t) :: m = 0
    end type

    ! A generator. It is a plain value: assignment copies the whole state, and the copy draws
    ! the same stream as the original. The C struct sits in a private component because
    ! bind(C) types cannot carry type-bound procedures.
    type :: tandem_t
        private
        type(rng_state) :: s
    contains
        procedure :: next_real64, next_real32, next_int64, next_int32, next_int16, next_int8
        procedure :: next_logical, next_complex64, next_complex32, next_int128
        procedure :: next_real16_bits, next_char
        procedure :: next_normal64, next_normal32, next_normal_pair32
        procedure :: next_exponential64, next_exponential32
        procedure, private :: below32, below64
        procedure :: choice, fill_choice
        generic :: below => below32, below64
        procedure :: at_real64, at_real32, at_int64, at_int32
        procedure, private :: fill_real64, fill_real32, fill_int64, fill_int32, fill_int16, &
            fill_int8, fill_logical, fill_c_bool, fill_complex64, fill_complex32
        generic :: fill => fill_real64, fill_real32, fill_int64, fill_int32, fill_int16, &
            fill_int8, fill_logical, fill_c_bool, fill_complex64, fill_complex32
        procedure :: fill_int128, fill_real16_bits, fill_char
        procedure, private :: fill_below32, fill_below64, fill_normal64, fill_normal32
        procedure, private :: fill_exponential64, fill_exponential32
        generic :: fill_below => fill_below32, fill_below64
        generic :: fill_normal => fill_normal64, fill_normal32
        generic :: fill_exponential => fill_exponential64, fill_exponential32
        procedure :: split, sub, fork
        procedure :: key, position, chunk_length, set_position, advance_to
    end type

    ! A weighted choice table, Appendix C of the specification: index i in [0, m) with probability
    ! proportional to weight i. The table holds exact integers, so tables and draws agree across
    ! ports.
    type :: tandem_choice_t
        private
        integer(int64) :: s = 0
        integer(int64), allocatable :: cuts(:)
        integer(int32), allocatable :: aliases(:)
    contains
        procedure :: build => choice_build
        procedure :: capacity => choice_capacity
        procedure :: cut => choice_cut
        procedure :: alias => choice_alias
    end type

    interface tandem_new
        module procedure new_seed64, new_seed128
    end interface

    ! Like the intrinsic random_number: uniform reals in [0, 1), any rank, scalars included.
    interface tandem_random_number
        module procedure fill_real64, fill_real32
    end interface

    ! Unsigned C integers map to signed Fortran integers of the same width: the bit
    ! pattern passes unchanged.
    interface
        function c_layout(offsets) result(size) bind(C, name="tandem_layout")
            import :: c_size_t
            integer(c_size_t), intent(out) :: offsets(8)
            integer(c_size_t) :: size
        end function
        function c_from_key(key, pos, K) result(r) bind(C, name="tandem_from_key")
            import :: rng_state, c_int32_t, c_int64_t
            integer(c_int32_t), intent(in) :: key(4)
            integer(c_int64_t), value :: pos
            integer(c_int32_t), value :: K
            type(rng_state) :: r
        end function
        function c_seed(seed_lo, seed_hi, K) result(r) bind(C, name="tandem_seed")
            import :: rng_state, c_int32_t, c_int64_t
            integer(c_int64_t), value :: seed_lo, seed_hi
            integer(c_int32_t), value :: K
            type(rng_state) :: r
        end function
        pure subroutine c_key(rng, key) bind(C, name="tandem_key")
            import :: rng_state, c_int32_t
            type(rng_state), intent(in) :: rng
            integer(c_int32_t), intent(out) :: key(4)
        end subroutine
        pure function c_position(rng) result(r) bind(C, name="tandem_position")
            import :: rng_state, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t) :: r
        end function
        pure function c_chunk_length(rng) result(r) bind(C, name="tandem_chunk_length")
            import :: rng_state, c_int32_t
            type(rng_state), intent(in) :: rng
            integer(c_int32_t) :: r
        end function
        function c_set_position(rng, pos) result(ok) bind(C, name="tandem_set_position")
            import :: rng_state, c_bool, c_int64_t
            type(rng_state), intent(inout) :: rng
            integer(c_int64_t), value :: pos
            logical(c_bool) :: ok
        end function

        function c_next_bool(rng) result(r) bind(C, name="tandem_next_bool")
            import :: rng_state, c_bool
            type(rng_state), intent(inout) :: rng
            logical(c_bool) :: r
        end function
        function c_next_u8(rng) result(r) bind(C, name="tandem_next_u8")
            import :: rng_state, c_int8_t
            type(rng_state), intent(inout) :: rng
            integer(c_int8_t) :: r
        end function
        function c_next_u16(rng) result(r) bind(C, name="tandem_next_u16")
            import :: rng_state, c_int16_t
            type(rng_state), intent(inout) :: rng
            integer(c_int16_t) :: r
        end function
        function c_next_u32(rng) result(r) bind(C, name="tandem_next_u32")
            import :: rng_state, c_int32_t
            type(rng_state), intent(inout) :: rng
            integer(c_int32_t) :: r
        end function
        function c_next_u64(rng) result(r) bind(C, name="tandem_next_u64")
            import :: rng_state, c_int64_t
            type(rng_state), intent(inout) :: rng
            integer(c_int64_t) :: r
        end function
        function c_next_u128(rng) result(r) bind(C, name="tandem_next_u128")
            import :: rng_state, u128
            type(rng_state), intent(inout) :: rng
            type(u128) :: r
        end function
        function c_next_f32(rng) result(r) bind(C, name="tandem_next_f32")
            import :: rng_state, c_float
            type(rng_state), intent(inout) :: rng
            real(c_float) :: r
        end function
        function c_next_f64(rng) result(r) bind(C, name="tandem_next_f64")
            import :: rng_state, c_double
            type(rng_state), intent(inout) :: rng
            real(c_double) :: r
        end function
        function c_next_f16_bits(rng) result(r) bind(C, name="tandem_next_f16_bits")
            import :: rng_state, c_int16_t
            type(rng_state), intent(inout) :: rng
            integer(c_int16_t) :: r
        end function
        function c_next_char(rng) result(r) bind(C, name="tandem_next_char")
            import :: rng_state, c_int32_t
            type(rng_state), intent(inout) :: rng
            integer(c_int32_t) :: r
        end function
        subroutine c_next_c32(rng, out) bind(C, name="tandem_next_c32")
            import :: rng_state, c_float
            type(rng_state), intent(inout) :: rng
            real(c_float), intent(out) :: out(2)
        end subroutine
        subroutine c_next_c64(rng, out) bind(C, name="tandem_next_c64")
            import :: rng_state, c_double
            type(rng_state), intent(inout) :: rng
            real(c_double), intent(out) :: out(2)
        end subroutine

        function c_u32_below(rng, n) result(r) bind(C, name="tandem_u32_below")
            import :: rng_state, c_int32_t
            type(rng_state), intent(inout) :: rng
            integer(c_int32_t), value :: n
            integer(c_int32_t) :: r
        end function
        function c_u64_below(rng, n) result(r) bind(C, name="tandem_u64_below")
            import :: rng_state, c_int64_t
            type(rng_state), intent(inout) :: rng
            integer(c_int64_t), value :: n
            integer(c_int64_t) :: r
        end function
        function c_choice_build(table, weights, m, cut, alias) result(ok) &
                bind(C, name="tandem_choice_build")
            import :: choice_table, c_bool, c_double, c_ptr, c_size_t
            type(choice_table), intent(out) :: table
            real(c_double), intent(in) :: weights(*)
            integer(c_size_t), value :: m
            type(c_ptr), value :: cut, alias
            logical(c_bool) :: ok
        end function
        function c_choice(rng, table) result(r) bind(C, name="tandem_choice")
            import :: rng_state, choice_table, c_int32_t
            type(rng_state), intent(inout) :: rng
            type(choice_table), intent(in) :: table
            integer(c_int32_t) :: r
        end function
        subroutine c_fill_choice(rng, out, n, table) bind(C, name="tandem_fill_choice")
            import :: rng_state, choice_table, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
            type(choice_table), intent(in) :: table
        end subroutine
        subroutine c_normal2_f32(rng, out) bind(C, name="tandem_normal2_f32")
            import :: rng_state, c_float
            type(rng_state), intent(inout) :: rng
            real(c_float), intent(out) :: out(2)
        end subroutine
        function c_normal_f64(rng) result(r) bind(C, name="tandem_normal_f64")
            import :: rng_state, c_double
            type(rng_state), intent(inout) :: rng
            real(c_double) :: r
        end function
        function c_normal_f32(rng) result(r) bind(C, name="tandem_normal_f32")
            import :: rng_state, c_float
            type(rng_state), intent(inout) :: rng
            real(c_float) :: r
        end function
        function c_exponential_f64(rng) result(r) bind(C, name="tandem_exponential_f64")
            import :: rng_state, c_double
            type(rng_state), intent(inout) :: rng
            real(c_double) :: r
        end function
        function c_exponential_f32(rng) result(r) bind(C, name="tandem_exponential_f32")
            import :: rng_state, c_float
            type(rng_state), intent(inout) :: rng
            real(c_float) :: r
        end function

        ! Every fill takes the output as an address, so one interface serves arrays of any
        ! rank. n counts elements; the complex fills write 2n components.
        subroutine c_fill_bool(rng, out, n) bind(C, name="tandem_fill_bool")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_u8(rng, out, n) bind(C, name="tandem_fill_u8")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_u16(rng, out, n) bind(C, name="tandem_fill_u16")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_u32(rng, out, n) bind(C, name="tandem_fill_u32")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_u64(rng, out, n) bind(C, name="tandem_fill_u64")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_u128(rng, out, n) bind(C, name="tandem_fill_u128")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_f32(rng, out, n) bind(C, name="tandem_fill_f32")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_f64(rng, out, n) bind(C, name="tandem_fill_f64")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_f16_bits(rng, out, n) bind(C, name="tandem_fill_f16_bits")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_char(rng, out, n) bind(C, name="tandem_fill_char")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_c32(rng, out, n) bind(C, name="tandem_fill_c32")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_c64(rng, out, n) bind(C, name="tandem_fill_c64")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine

        subroutine c_fill_u32_below(rng, out, len, n) bind(C, name="tandem_fill_u32_below")
            import :: rng_state, c_ptr, c_size_t, c_int32_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: len
            integer(c_int32_t), value :: n
        end subroutine
        subroutine c_fill_u64_below(rng, out, len, n) bind(C, name="tandem_fill_u64_below")
            import :: rng_state, c_ptr, c_size_t, c_int64_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: len
            integer(c_int64_t), value :: n
        end subroutine
        subroutine c_fill_normal_f64(rng, out, n) bind(C, name="tandem_fill_normal_f64")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_normal_f32(rng, out, n) bind(C, name="tandem_fill_normal_f32")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_exponential_f64(rng, out, n) bind(C, name="tandem_fill_exponential_f64")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine
        subroutine c_fill_exponential_f32(rng, out, n) bind(C, name="tandem_fill_exponential_f32")
            import :: rng_state, c_ptr, c_size_t
            type(rng_state), intent(inout) :: rng
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
        end subroutine

        pure function c_at_u32(rng, i) result(r) bind(C, name="tandem_at_u32")
            import :: rng_state, c_int32_t, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t), value :: i
            integer(c_int32_t) :: r
        end function
        pure function c_at_u64(rng, i) result(r) bind(C, name="tandem_at_u64")
            import :: rng_state, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t), value :: i
            integer(c_int64_t) :: r
        end function
        pure function c_at_f32(rng, i) result(r) bind(C, name="tandem_at_f32")
            import :: rng_state, c_float, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t), value :: i
            real(c_float) :: r
        end function
        pure function c_at_f64(rng, i) result(r) bind(C, name="tandem_at_f64")
            import :: rng_state, c_double, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t), value :: i
            real(c_double) :: r
        end function

        pure function c_split(rng, index) result(r) bind(C, name="tandem_split")
            import :: rng_state, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t), value :: index
            type(rng_state) :: r
        end function
        pure function c_sub(rng, purpose) result(r) bind(C, name="tandem_sub")
            import :: rng_state, c_int64_t
            type(rng_state), intent(in) :: rng
            integer(c_int64_t), value :: purpose
            type(rng_state) :: r
        end function
        subroutine c_fork(parent, children, n) bind(C, name="tandem_fork")
            import :: rng_state, c_int64_t
            type(rng_state), intent(inout) :: parent
            type(rng_state), intent(inout) :: children(*)
            integer(c_int64_t), value :: n
        end subroutine

        ! The specification's building blocks, for conformance tests and ports.
        pure subroutine tandem_apply_T(o, h) bind(C, name="tandem_T")
            import :: c_int32_t
            integer(c_int32_t), intent(inout) :: o(4), h(4)
        end subroutine
        pure subroutine tandem_apply_F(o, h) bind(C, name="tandem_F")
            import :: c_int32_t
            integer(c_int32_t), intent(inout) :: o(4), h(4)
        end subroutine
        pure subroutine tandem_F_keyed(key, counter, domain, aux, o, h) bind(C, name="tandem_F_keyed")
            import :: c_int32_t, c_int64_t
            integer(c_int32_t), intent(in) :: key(4)
            integer(c_int64_t), value :: counter
            integer(c_int32_t), value :: domain, aux
            integer(c_int32_t), intent(out) :: o(4), h(4)
        end subroutine
        pure subroutine tandem_block(key, c, j, out) bind(C, name="tandem_block")
            import :: c_int32_t, c_int64_t
            integer(c_int32_t), intent(in) :: key(4)
            integer(c_int64_t), value :: c
            integer(c_int32_t), value :: j
            integer(c_int32_t), intent(out) :: out(4)
        end subroutine
    end interface

contains

    ! True when rng_state has the size and field offsets of the C struct tandem_rng. The
    ! mirror is written by hand, so a change to tandem.h shows up here before it corrupts draws.
    function tandem_layout_matches() result(ok)
        logical :: ok
        type(rng_state), target :: s
        integer(c_size_t) :: offsets(8), want(8), base, size
        size = c_layout(offsets) ! before the comparison: operands evaluate in any order
        base = transfer(c_loc(s), base)
        want = [transfer(c_loc(s%key), base), transfer(c_loc(s%pos), base), &
            transfer(c_loc(s%K), base), transfer(c_loc(s%cached), base), &
            transfer(c_loc(s%ahead), base), transfer(c_loc(s%base), base), &
            transfer(c_loc(s%o), base), transfer(c_loc(s%h), base)] - base
        ok = size == c_sizeof(s) .and. all(offsets == want)
    end function

    ! ---- Construction and transport -------------------------------------------------------

    ! The 64-bit seed is the low half of the 128-bit seed; the high half is zero.
    function new_seed64(seed, K) result(rng)
        integer(int64), intent(in) :: seed
        integer(int32), intent(in), optional :: K
        type(tandem_t) :: rng
        rng%s = c_seed(seed, 0_int64, chunk_or_default(K))
    end function

    function new_seed128(seed_lo, seed_hi, K) result(rng)
        integer(int64), intent(in) :: seed_lo, seed_hi
        integer(int32), intent(in), optional :: K
        type(tandem_t) :: rng
        rng%s = c_seed(seed_lo, seed_hi, chunk_or_default(K))
    end function

    ! K is a power of two in [1, 65536].
    function tandem_from_key(key, pos, K) result(rng)
        integer(int32), intent(in) :: key(4)
        integer(int64), intent(in), optional :: pos
        integer(int32), intent(in), optional :: K
        type(tandem_t) :: rng
        integer(int64) :: p
        p = 0
        if (present(pos)) p = pos
        rng%s = c_from_key(key, p, chunk_or_default(K))
    end function

    pure function chunk_or_default(K) result(r)
        integer(int32), intent(in), optional :: K
        integer(int32) :: r
        r = TANDEM_DEFAULT_K
        if (present(K)) r = K
    end function

    pure function key(rng)
        class(tandem_t), intent(in) :: rng
        integer(int32) :: key(4)
        call c_key(rng%s, key)
    end function

    ! Stream position in bits.
    pure function position(rng)
        class(tandem_t), intent(in) :: rng
        integer(int64) :: position
        position = c_position(rng%s)
    end function

    pure function chunk_length(rng)
        class(tandem_t), intent(in) :: rng
        integer(int32) :: chunk_length
        chunk_length = c_chunk_length(rng%s)
    end function

    ! A start position is below 2^63, so pos is not negative. A rejected position changes
    ! nothing and sets ok to false, or stops the program when ok is absent.
    subroutine set_position(rng, pos, ok)
        class(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: pos
        logical, intent(out), optional :: ok
        logical :: done
        done = c_set_position(rng%s, pos)
        if (present(ok)) then
            ok = done
        else if (.not. done) then
            error stop "tandem set_position: the position must be below 2^63"
        end if
    end subroutine

    ! Moves to the end pos of draws or a fill made from this generator, unchecked, as
    ! Rng::advance_to of tandem-cuda: an end may lie at or past 2^63. For fills that run
    ! elsewhere, such as on a device.
    subroutine advance_to(rng, pos)
        class(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: pos
        rng%s = c_from_key(rng%s%key, pos, rng%s%K)
    end subroutine

    ! ---- Scalar draws ----------------------------------------------------------------------

    function next_real64(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real64) :: r
        r = c_next_f64(rng%s)
    end function

    function next_real32(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real32) :: r
        r = c_next_f32(rng%s)
    end function

    function next_int64(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int64) :: r
        r = c_next_u64(rng%s)
    end function

    function next_int32(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int32) :: r
        r = c_next_u32(rng%s)
    end function

    function next_int16(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int16) :: r
        r = c_next_u16(rng%s)
    end function

    function next_int8(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int8) :: r
        r = c_next_u8(rng%s)
    end function

    function next_logical(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        logical :: r
        r = c_next_bool(rng%s)
    end function

    function next_complex64(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        complex(real64) :: r
        real(c_double) :: z(2)
        call c_next_c64(rng%s, z)
        r = cmplx(z(1), z(2), real64)
    end function

    function next_complex32(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        complex(real32) :: r
        real(c_float) :: z(2)
        call c_next_c32(rng%s, z)
        r = cmplx(z(1), z(2), real32)
    end function

    ! A 128-bit word as (low, high) 64-bit halves.
    function next_int128(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int64) :: r(2)
        type(u128) :: w
        w = c_next_u128(rng%s)
        r = [w%lo, w%hi]
    end function

    ! IEEE binary16 bit pattern of a uniform draw in [0, 1).
    function next_real16_bits(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int16) :: r
        r = c_next_f16_bits(rng%s)
    end function

    ! A uniform Unicode scalar value, as its code point.
    function next_char(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int32) :: r
        r = c_next_char(rng%s)
    end function

    ! ---- Bounded integers and normals: not in the specification, they follow Rng::urand(range)
    ! and Rng::normal of tandem-cuda -------------------------------------------------------

    ! Uniform on [0, n) by Lemire's method. n is an unsigned bit pattern like every integer
    ! here, and a rejected draw is discarded, so the position advances by a varying amount.
    function below32(rng, n) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int32), intent(in) :: n
        integer(int32) :: r
        r = c_u32_below(rng%s, n)
    end function

    function below64(rng, n) result(r)
        class(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n
        integer(int64) :: r
        r = c_u64_below(rng%s, n)
    end function

    ! The 1024-layer ziggurat from one 64-bit draw. A draw that misses the fast path (0.43 %)
    ! continues on its own fallback generator, which leaves the position alone.
    function next_normal64(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real64) :: r
        r = c_normal_f64(rng%s)
    end function

    ! Box-Muller in single precision from two 32-bit float draws.
    function next_normal32(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real32) :: r
        r = c_normal_f32(rng%s)
    end function

    ! Both halves of one single-precision Box-Muller step, the cos half first: the pairs that
    ! make up a real32 normal fill.
    function next_normal_pair32(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real32) :: r(2)
        call c_normal2_f32(rng%s, r)
    end function

    ! Standard exponential -log(1 - u) of one uniform draw of the same kind.
    function next_exponential64(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real64) :: r
        r = c_exponential_f64(rng%s)
    end function

    function next_exponential32(rng) result(r)
        class(tandem_t), intent(inout) :: rng
        real(real32) :: r
        r = c_exponential_f32(rng%s)
    end function

    ! ---- Random access: element i (from 0) of the fill that would start here ---------------

    elemental function at_real64(rng, i) result(r)
        class(tandem_t), intent(in) :: rng
        integer(int64), intent(in) :: i
        real(real64) :: r
        r = c_at_f64(rng%s, i)
    end function

    elemental function at_real32(rng, i) result(r)
        class(tandem_t), intent(in) :: rng
        integer(int64), intent(in) :: i
        real(real32) :: r
        r = c_at_f32(rng%s, i)
    end function

    elemental function at_int64(rng, i) result(r)
        class(tandem_t), intent(in) :: rng
        integer(int64), intent(in) :: i
        integer(int64) :: r
        r = c_at_u64(rng%s, i)
    end function

    elemental function at_int32(rng, i) result(r)
        class(tandem_t), intent(in) :: rng
        integer(int64), intent(in) :: i
        integer(int32) :: r
        r = c_at_u32(rng%s, i)
    end function

    ! ---- Fills: the same values as size(x) scalar draws, in array element order -----------

    ! The first element of a contiguous array. nvfortran 25.3 returns c_loc of an assumed-rank
    ! array of rank 2 and up at index zero in every dimension. A C descriptor gives the right
    ! address only without its GPU flags, so the fill stops rather than write out of bounds.
    function address(x) result(p)
        type(*), intent(in), target :: x(..)
        type(c_ptr) :: p
        if (NVFORTRAN .and. rank(x) > 1) error stop &
            "tandem fill: nvfortran gets the address of rank 2 and up wrong, fill a rank 1 pointer to the array"
        p = c_loc(x)
    end function

    subroutine fill_real64(rng, x)
        class(tandem_t), intent(inout) :: rng
        real(real64), intent(out), target, contiguous :: x(..)
        call c_fill_f64(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_real32(rng, x)
        class(tandem_t), intent(inout) :: rng
        real(real32), intent(out), target, contiguous :: x(..)
        call c_fill_f32(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_int64(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), target, contiguous :: x(..)
        call c_fill_u64(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_int32(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), target, contiguous :: x(..)
        call c_fill_u32(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_int16(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int16), intent(out), target, contiguous :: x(..)
        call c_fill_u16(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_int8(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int8), intent(out), target, contiguous :: x(..)
        call c_fill_u8(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_c_bool(rng, x)
        class(tandem_t), intent(inout) :: rng
        logical(c_bool), intent(out), target, contiguous :: x(..)
        call c_fill_bool(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    ! Default logical is wider than C's bool, so draw through a C bool buffer.
    subroutine fill_logical(rng, x)
        class(tandem_t), intent(inout) :: rng
        logical, intent(out), target, contiguous :: x(..)
        integer, parameter :: chunk = 4096
        logical(c_bool), target :: buf(chunk)
        logical, pointer :: flat(:)
        integer(int64) :: i, m, n
        n = size(x, kind=int64)
        call c_f_pointer(address(x), flat, [n])
        do i = 1, n, chunk
            m = min(int(chunk, int64), n - i + 1)
            call c_fill_bool(rng%s, c_loc(buf), int(m, c_size_t))
            flat(i:i + m - 1) = logical(buf(:m))
        end do
    end subroutine

    subroutine fill_complex64(rng, x)
        class(tandem_t), intent(inout) :: rng
        complex(c_double_complex), intent(out), target, contiguous :: x(..)
        call c_fill_c64(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_complex32(rng, x)
        class(tandem_t), intent(inout) :: rng
        complex(c_float_complex), intent(out), target, contiguous :: x(..)
        call c_fill_c32(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    ! 128-bit words as (low, high) pairs: x(1, j), x(2, j) hold word j.
    subroutine fill_int128(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), target, contiguous :: x(:, :)
        if (size(x, 1) /= 2) error stop "tandem fill_int128: the first dimension must be 2"
        call c_fill_u128(rng%s, c_loc(x), size(x, 2, kind=c_size_t))
    end subroutine

    subroutine fill_real16_bits(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int16), intent(out), target, contiguous :: x(..)
        call c_fill_f16_bits(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_char(rng, x)
        class(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), target, contiguous :: x(..)
        call c_fill_char(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    ! Element i takes draw i of the plain fill. A rejected draw is retried on a fallback
    ! generator, so the values differ from size(x) calls of below where a rejection happens.
    subroutine fill_below32(rng, x, n)
        class(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), target, contiguous :: x(..)
        integer(int32), intent(in) :: n
        call c_fill_u32_below(rng%s, address(x), size(x, kind=c_size_t), n)
    end subroutine

    subroutine fill_below64(rng, x, n)
        class(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), target, contiguous :: x(..)
        integer(int64), intent(in) :: n
        call c_fill_u64_below(rng%s, address(x), size(x, kind=c_size_t), n)
    end subroutine

    ! real64: element i is the ziggurat of 64-bit draw i, the sequence of next_normal64 calls. An
    ! empty fill aligns the position to 64 bits.
    ! real32: the flattened next_normal_pair32 pairs, element 2j and 2j + 1 from uniforms 2j and
    ! 2j + 1. An odd size keeps the cos half of the last pair and still consumes both uniforms.
    subroutine fill_normal64(rng, x)
        class(tandem_t), intent(inout) :: rng
        real(real64), intent(out), target, contiguous :: x(..)
        call c_fill_normal_f64(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_normal32(rng, x)
        class(tandem_t), intent(inout) :: rng
        real(real32), intent(out), target, contiguous :: x(..)
        call c_fill_normal_f32(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    ! Element i is next_exponential of draw i, so a fill equals the scalar calls.
    subroutine fill_exponential64(rng, x)
        class(tandem_t), intent(inout) :: rng
        real(real64), intent(out), target, contiguous :: x(..)
        call c_fill_exponential_f64(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    subroutine fill_exponential32(rng, x)
        class(tandem_t), intent(inout) :: rng
        real(real32), intent(out), target, contiguous :: x(..)
        call c_fill_exponential_f32(rng%s, address(x), size(x, kind=c_size_t))
    end subroutine

    ! ---- Weighted choice, Appendix C -------------------------------------------------------

    ! Builds the alias table, with no draw. The weights must be finite, not negative and not all
    ! zero. Otherwise the table stays empty and ok is false, or the program stops when ok is
    ! absent.
    subroutine choice_build(table, weights, ok)
        class(tandem_choice_t), intent(out), target :: table
        real(real64), intent(in) :: weights(:)
        logical, intent(out), optional :: ok
        type(choice_table) :: t
        logical :: done
        done = .false.
        if (size(weights) > 0) then
            allocate (table%cuts(size(weights)), table%aliases(size(weights)))
            done = c_choice_build(t, weights, size(weights, kind=c_size_t), c_loc(table%cuts), &
                c_loc(table%aliases))
            if (done) then
                table%s = t%capacity
            else
                deallocate (table%cuts, table%aliases)
            end if
        end if
        if (present(ok)) then
            ok = done
        else if (.not. done) then
            error stop "tandem choice build: the weights must be finite, not negative and not all zero"
        end if
    end subroutine

    ! The column capacity S, an unsigned bit pattern.
    pure function choice_capacity(table) result(s)
        class(tandem_choice_t), intent(in) :: table
        integer(int64) :: s
        s = table%s
    end function

    pure function choice_cut(table) result(cut)
        class(tandem_choice_t), intent(in) :: table
        integer(int64), allocatable :: cut(:)
        cut = table%cuts
    end function

    pure function choice_alias(table) result(alias)
        class(tandem_choice_t), intent(in) :: table
        integer(int32), allocatable :: alias(:)
        alias = table%aliases
    end function

    function c_table(table) result(t)
        class(tandem_choice_t), intent(in), target :: table
        type(choice_table) :: t
        if (.not. allocated(table%cuts)) error stop "tandem choice: the table is not built"
        t = choice_table(table%s, c_loc(table%cuts), c_loc(table%aliases), size(table%cuts))
    end function

    ! An index in [0, m), from one 64-bit draw.
    function choice(rng, table) result(r)
        class(tandem_t), intent(inout) :: rng
        class(tandem_choice_t), intent(in), target :: table
        integer(int32) :: r
        r = c_choice(rng%s, c_table(table))
    end function

    ! Element i maps 64-bit draw i, so a fill equals size(x) choice calls. An empty fill aligns
    ! the position to 64 bits.
    subroutine fill_choice(rng, x, table)
        class(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), target, contiguous :: x(..)
        class(tandem_choice_t), intent(in), target :: table
        call c_fill_choice(rng%s, address(x), size(x, kind=c_size_t), c_table(table))
    end subroutine

    ! ---- Derived generators: position 0, the parent's K ------------------------------------

    ! Child by index, from the key alone.
    elemental function split(rng, index) result(child)
        class(tandem_t), intent(in) :: rng
        integer(int64), intent(in) :: index
        type(tandem_t) :: child
        child%s = c_split(rng%s, index)
    end function

    ! Child for a purpose, from the key alone.
    elemental function sub(rng, purpose) result(child)
        class(tandem_t), intent(in) :: rng
        integer(int64), intent(in) :: purpose
        type(tandem_t) :: child
        child%s = c_sub(rng%s, purpose)
    end function

    ! size(children) children from the current block; the parent moves past the block.
    subroutine fork(rng, children)
        class(tandem_t), intent(inout) :: rng
        type(tandem_t), intent(out) :: children(:)
        type(rng_state), allocatable :: kids(:)
        allocate (kids(size(children)))
        call c_fork(rng%s, kids, size(children, kind=c_int64_t))
        children%s = kids
    end subroutine

end module tandem_rng
