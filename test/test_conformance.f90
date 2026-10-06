! The specification's conformance fixtures (test/conformance/*.json), one subroutine per section
! of tandem-spec's conformance/CHECKLIST.md. The host fills come from the vendored C library,
! so every value matches bit for bit, the Float32 normals and exponentials included.
program test_conformance
    use, intrinsic :: iso_c_binding, only: c_bool
    use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
    use, intrinsic :: ieee_arithmetic, only: ieee_positive_inf, ieee_quiet_nan, ieee_value
    use tandem_rng
    use tandem_conformance
    implicit none

    integer(int64), parameter :: MASK32 = 4294967295_int64
    integer, parameter :: CUTS(4) = [1, 7, 20, 21]
    integer :: failures = 0, checks = 0
    type(conformance_case), allocatable :: below(:), fill_below(:), normal(:), exponential(:), &
        choice(:)

    below = read_cases("below.json")
    fill_below = read_cases("fill_below.json")
    normal = read_cases("normal.json")
    exponential = read_cases("exponential.json")
    choice = read_cases("choice.json")

    call every_case()
    call fallback_by_draw_index()
    call width_from_range()
    call empty_fills()
    call odd_n()
    call pair_rule()
    call weighted_choice()
    call scalar_draws()
    call stream_hashes()
    call dump_hashes()
    call block_boundaries()

    if (failures > 0) then
        print '(i0, " of ", i0, " checks failed")', failures, checks
        error stop 1
    end if
    print '("conformance: ", i0, " checks ok")', checks

contains

    subroutine check(ok, what)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        checks = checks + 1
        if (.not. ok) then
            failures = failures + 1
            print '("FAIL ", a)', what
        end if
    end subroutine

    function start(c) result(g)
        type(conformance_case), intent(in) :: c
        type(tandem_t) :: g
        g = tandem_from_key(c%key, c%start, c%K)
    end function

    function table_of(c) result(t)
        type(conformance_case), intent(in) :: c
        type(tandem_choice_t) :: t
        call t%build(transfer(c%weights, 0.0_real64, size(c%weights)))
    end function

    ! m elements of the fill of case c on g, as unsigned bit patterns.
    function fill(c, g, m) result(bits)
        type(conformance_case), intent(in) :: c
        type(tandem_t), intent(inout) :: g
        integer, intent(in) :: m
        integer(int64) :: bits(m)
        integer(int32) :: x32(m)
        integer(int64) :: x64(m)
        real(real64) :: r64(m)
        real(real32) :: r32(m)
        select case (c%kind)
        case ("fill_below_u32")
            call g%fill_below(x32, as_int32(c%range))
            bits = iand(int(x32, int64), MASK32)
        case ("fill_below_u64")
            call g%fill_below(x64, c%range)
            bits = x64
        case ("fill_normal_f64")
            call g%fill_normal(r64)
            bits = transfer(r64, 0_int64, m)
        case ("fill_normal_f32")
            call g%fill_normal(r32)
            bits = iand(int(transfer(r32, 0_int32, m), int64), MASK32)
        case ("fill_exponential_f64")
            call g%fill_exponential(r64)
            bits = transfer(r64, 0_int64, m)
        case ("fill_exponential_f32")
            call g%fill_exponential(r32)
            bits = iand(int(transfer(r32, 0_int32, m), int64), MASK32)
        case ("fill_choice")
            call g%fill_choice(x32, table_of(c))
            bits = int(x32, int64)
        case default
            error stop "conformance: unknown kind "//c%kind
        end select
    end function

    ! The end the source pins, or for a Float32 normal fill align(start, 32) + 64 ceil(n / 2).
    function end_of(c) result(e)
        type(conformance_case), intent(in) :: c
        integer(int64) :: e
        e = c%end
        if (e < 0 .and. c%kind == "fill_normal_f32") &
            e = (c%start + 31) / 32 * 32 + 64 * ((c%n + 1) / 2)
    end function

    ! Values and end of every fill case, whole and cut at elements 1, 7, 20, 21 and n - 1 into
    ! pieces filled in order on one generator. A Float32 normal fill is cut between pairs only,
    ! since an odd piece consumes its whole last pair.
    subroutine every_case()
        integer :: i
        do i = 1, size(fill_below)
            call whole_and_cut(fill_below(i))
        end do
        do i = 1, size(normal)
            call whole_and_cut(normal(i))
        end do
        do i = 1, size(exponential)
            call whole_and_cut(exponential(i))
        end do
        do i = 1, size(choice)
            call whole_and_cut(choice(i))
        end do
    end subroutine

    subroutine whole_and_cut(c)
        type(conformance_case), intent(in) :: c
        type(tandem_t) :: g
        integer(int64) :: got(c%n)
        integer :: cut(size(CUTS) + 1), j, m, n
        n = int(c%n)
        cut = [CUTS, n - 1]
        g = start(c)
        got = fill(c, g, n)
        call check(all(got == c%values), c%id//": values")
        if (end_of(c) >= 0) call check(g%position() == end_of(c), c%id//": end")
        if (n < 2) return
        do j = 1, size(cut)
            m = cut(j)
            if (m >= n .or. (c%kind == "fill_normal_f32" .and. mod(m, 2) == 1)) cycle
            g = start(c)
            got(:m) = fill(c, g, m)
            got(m + 1:) = fill(c, g, n - m)
            call check(all(got == c%values), c%id//": cut fill values")
            if (end_of(c) >= 0) call check(g%position() == end_of(c), c%id//": cut fill end")
        end do
    end subroutine

    ! A start one 32-bit draw later shifts a bounded fill by one element, rejected draws
    ! included, and a start one 64-bit draw later shifts a ziggurat fill, misses included.
    subroutine fallback_by_draw_index()
        call shifted(find_case(fill_below, "CROSS_BELOW32_AT[4]"), find_case(fill_below, "CROSS_BELOW32[4]"), 1)
        call shifted(find_case(fill_below, "CROSS_BELOW64_AT[6]"), find_case(fill_below, "CROSS_BELOW64[6]"), 1)
        call shifted(find_case(normal, "CROSS_NORMAL[1]"), find_case(normal, "CROSS_NORMAL[0]"), 1)
        call check(rejects(find_case(fill_below, "CROSS_BELOW32[4]")) .and. &
            rejects(find_case(fill_below, "CROSS_BELOW64_AT[6]")), "the shifted cases reject")
    end subroutine

    pure logical function rejects(c)
        type(conformance_case), intent(in) :: c
        rejects = c%rejected > 0
    end function


    ! Element i of the fill of later equals element i + by of the fill of base.
    subroutine shifted(later, base, by)
        type(conformance_case), intent(in) :: later, base
        integer, intent(in) :: by
        type(tandem_t) :: g
        integer(int64) :: a(later%n), b(base%n)
        g = start(later)
        a = fill(later, g, int(later%n))
        g = start(base)
        b = fill(base, g, int(base%n))
        call check(all(a(:size(a) - by) == b(1 + by:)), later%id//" shifts "//base%id)
    end subroutine

    ! Fortran's bounded draws take the width from the integer kind, so every interface names the
    ! width. The kind int64 draws 64 bits even for range 1000.
    subroutine width_from_range()
        type(conformance_case) :: c32, c64
        type(tandem_t) :: g
        integer(int32) :: x32(64)
        integer(int64) :: x64(64)
        c32 = find_case(fill_below, "CROSS_BELOW32[3]")
        c64 = find_case(fill_below, "CROSS_BELOW64[3]")
        g = start(c32)
        call g%fill_below(x32, 1000_int32)
        call check(all(iand(int(x32, int64), MASK32) == c32%values), "int32 range 1000")
        g = start(c64)
        call g%fill_below(x64, 1000_int64)
        call check(all(x64 == c64%values), "int64 range 1000 draws 64 bits")
        g = tandem_new(1_int64, 2_int64)
        x32(1) = g%below(0_int32)
        call check(x32(1) == 0 .and. g%position() == 32, "range 0 int32 returns 0 and draws 32 bits")
        x64(1) = g%below(0_int64)
        call check(x64(1) == 0 .and. g%position() == 128, "range 0 int64 returns 0 and draws 64 bits")
    end subroutine

    ! every_case ran these: a uniform, Float64 normal or choice fill aligns, the others keep the
    ! position.
    subroutine empty_fills()
        type(tandem_t) :: g
        real(real64) :: x(0)
        integer :: i, n
        n = 0
        do i = 1, size(fill_below)
            if (fill_below(i)%n == 0) n = n + 1
        end do
        do i = 1, size(normal)
            if (normal(i)%n == 0) n = n + 1
        end do
        do i = 1, size(exponential)
            if (exponential(i)%n == 0) n = n + 1
        end do
        do i = 1, size(choice)
            if (choice(i)%n == 0) n = n + 1
        end do
        call check(n == 7, "seven n = 0 cases")
        g = tandem_new(42_int64)
        call g%set_position(33_int64)
        call g%fill(x)
        call check(g%position() == 64, "an empty uniform fill aligns")
    end subroutine

    subroutine odd_n()
        integer :: i
        do i = 0, 4
            associate (c => find_case(normal, "CROSS_NORMAL32["//achar(48 + i)//"]"))
                call check(c%n == 33, c%id//": odd n")
            end associate
        end do
        call check(end_of(find_case(normal, "CROSS_NORMAL32[0]")) == 1088, "odd n end 1088")
    end subroutine

    ! Element 2j is the cos half and 2j + 1 the sin half of uniforms 2j and 2j + 1.
    subroutine pair_rule()
        type(conformance_case) :: pairs, odd
        type(tandem_t) :: a, b
        integer(int64) :: x(128), y(33)
        real(real32) :: z(2), cos_half
        pairs = find_case(normal, "CROSS_NORMALF")
        odd = find_case(normal, "CROSS_NORMAL32[1]")
        a = start(pairs)
        x = fill(pairs, a, 128)
        a = start(odd)
        y = fill(odd, a, 33)
        call check(all(x(:33) == y), "the first 33 values of CROSS_NORMALF are CROSS_NORMAL32[1]")
        call shifted(find_case(normal, "CROSS_NORMAL32[2]"), find_case(normal, "CROSS_NORMAL32[0]"), 2)
        a = start(pairs)
        b = a
        z = a%next_normal_pair32()
        cos_half = b%next_normal32()
        call check(transfer(cos_half, 0_int32) == transfer(z(1), 0_int32) .and. &
            iand(int(transfer(z(1), 0_int32), int64), MASK32) == pairs%values(1), &
            "a scalar real32 normal is the cos half")
        call check(b%position() == 96, "a scalar real32 normal draws two uniforms")
    end subroutine

    subroutine weighted_choice()
        type(tandem_choice_t) :: t
        type(conformance_case) :: c
        type(tandem_t) :: a, b
        integer(int32) :: x(16), k
        real(real64) :: inf, nan
        logical :: ok
        integer :: i
        do i = 1, size(choice)
            c = choice(i)
            if (size(c%cut) == 0) cycle
            t = table_of(c)
            call check(t%capacity() == c%capacity, c%id//": capacity")
            call check(all(t%cut() == c%cut), c%id//": cut")
            call check(all(iand(int(t%alias(), int64), MASK32) == c%alias), c%id//": alias")
        end do
        call shifted(find_case(choice, "CROSS_CHOICE[1]"), find_case(choice, "CROSS_CHOICE[0]"), 1)
        c = find_case(choice, "CROSS_CHOICE[6]")
        t = table_of(c)
        a = start(c)
        b = a
        call a%fill_choice(x, t)
        k = b%choice(t)
        call check(k == x(1) .and. b%position() == 64, "a scalar choice is element 0 and draws 64 bits")
        call t%build([2.5_real64])
        a = tandem_new(42_int64)
        call check(all([(a%choice(t), i = 1, 16)] == 0), "m = 1 returns 0")
        inf = ieee_value(inf, ieee_positive_inf)
        nan = ieee_value(nan, ieee_quiet_nan)
        call t%build([1.0_real64, -1.0_real64], ok)
        call check(.not. ok, "a negative weight builds no table")
        call t%build([1.0_real64, inf], ok)
        call check(.not. ok, "an infinite weight builds no table")
        call t%build([nan, 1.0_real64], ok)
        call check(.not. ok, "a NaN weight builds no table")
        call t%build([0.0_real64, 0.0_real64], ok)
        call check(.not. ok, "zero weights build no table")
        call t%build([real(real64) ::], ok)
        call check(.not. ok, "no weights build no table")
    end subroutine

    ! n scalar draws equal each scalar bounded case, each Float64 normal and each exponential
    ! fill case, and each choice case, values and end.
    subroutine scalar_draws()
        integer :: i
        do i = 1, size(below)
            call scalars(below(i))
        end do
        do i = 1, size(normal)
            if (normal(i)%kind == "fill_normal_f64" .and. normal(i)%n > 0) call scalars(normal(i))
        end do
        do i = 1, size(exponential)
            if (exponential(i)%n > 0) call scalars(exponential(i))
        end do
        do i = 1, size(choice)
            if (choice(i)%n > 0) call scalars(choice(i))
        end do
    end subroutine

    ! One draw per statement: a function reference must not affect another in the same statement.
    subroutine scalars(c)
        type(conformance_case), intent(in) :: c
        type(tandem_t) :: g
        type(tandem_choice_t) :: t
        integer(int64) :: got(c%n)
        integer :: i
        g = start(c)
        if (c%kind == "fill_choice") t = table_of(c)
        do i = 1, int(c%n)
            select case (c%kind)
            case ("below_u32")
                got(i) = iand(int(g%below(as_int32(c%range)), int64), MASK32)
            case ("below_u64")
                got(i) = g%below(c%range)
            case ("fill_normal_f64")
                got(i) = transfer(g%next_normal64(), 0_int64)
            case ("fill_exponential_f64")
                got(i) = transfer(g%next_exponential64(), 0_int64)
            case ("fill_exponential_f32")
                got(i) = iand(int(transfer(g%next_exponential32(), 0_int32), int64), MASK32)
            case default
                got(i) = g%choice(t)
            end select
        end do
        call check(all(got == c%values), c%id//": scalar draws")
        if (c%end >= 0) call check(g%position() == c%end, c%id//": scalar draws end")
    end subroutine

    ! The SHA-256 of each uniform fill of hashes.json, from the fill itself, not the dump.
    subroutine stream_hashes()
        type(stream_case), allocatable :: s(:)
        type(tandem_t) :: g
        integer(int8), allocatable :: bytes(:)
        integer :: i, n
        s = read_streams()
        call check(size(s) == 12, "twelve streams")
        do i = 1, size(s)
            g = tandem_from_key(s(i)%key, s(i)%start, s(i)%K)
            n = int(s(i)%n)
            bytes = stream_bytes(g, s(i)%type, n)
            call check(size(bytes) == s(i)%bytes, s(i)%file//": bytes")
            call check(sha256_hex(bytes) == s(i)%sha256, s(i)%file//": sha256")
        end do
    end subroutine

    function stream_bytes(g, type, n) result(bytes)
        type(tandem_t), intent(inout) :: g
        character(*), intent(in) :: type
        integer, intent(in) :: n
        integer(int8), allocatable :: bytes(:)
        integer(int8), allocatable :: u8(:)
        integer(int16), allocatable :: u16(:)
        integer(int32), allocatable :: u32(:)
        integer(int64), allocatable :: u64(:), u128(:, :)
        real(real32), allocatable :: f32(:)
        real(real64), allocatable :: f64(:)
        complex(real32), allocatable :: c32(:)
        complex(real64), allocatable :: c64(:)
        logical(c_bool), allocatable :: b(:)
        select case (type)
        case ("UInt32", "Char")
            allocate (u32(n))
            if (type == "Char") then
                call g%fill_char(u32)
            else
                call g%fill(u32)
            end if
            bytes = transfer(u32, bytes)
        case ("UInt64")
            allocate (u64(n))
            call g%fill(u64)
            bytes = transfer(u64, bytes)
        case ("UInt128")
            allocate (u128(2, n))
            call g%fill_int128(u128)
            bytes = transfer(u128, bytes)
        case ("UInt8")
            allocate (u8(n))
            call g%fill(u8)
            bytes = u8
        case ("Float16")
            allocate (u16(n))
            call g%fill_real16_bits(u16)
            bytes = transfer(u16, bytes)
        case ("Float32")
            allocate (f32(n))
            call g%fill(f32)
            bytes = transfer(f32, bytes)
        case ("Float64")
            allocate (f64(n))
            call g%fill(f64)
            bytes = transfer(f64, bytes)
        case ("ComplexF32")
            allocate (c32(n))
            call g%fill(c32)
            bytes = transfer(c32, bytes)
        case ("ComplexF64")
            allocate (c64(n))
            call g%fill(c64)
            bytes = transfer(c64, bytes)
        case ("Bool")
            allocate (b(n))
            call g%fill(b)
            bytes = transfer(b, bytes)
        case default
            error stop "conformance: unknown stream type "//type
        end select
    end function

    ! FNV-1a of the long normal and exponential outputs, and the end where the source pins it.
    subroutine dump_hashes()
        type(dump_case), allocatable :: d(:)
        type(tandem_t) :: g
        real(real64), allocatable :: f64(:)
        real(real32), allocatable :: f32(:)
        integer(int64) :: h(2), nbytes
        integer :: i, j, k, n
        d = read_dumps()
        do i = 1, size(d)
            h = fnv1a_init()
            nbytes = 0
            do j = 1, size(d(i)%starts)
                g = tandem_from_key(d(i)%key, d(i)%starts(j), d(i)%K)
                do k = 1, size(d(i)%draws)
                    n = int(d(i)%counts(k))
                    select case (d(i)%draws(k))
                    case ("fill_normal_f64", "fill_exponential_f64")
                        allocate (f64(n))
                        if (d(i)%draws(k) == "fill_normal_f64") then
                            call g%fill_normal(f64)
                        else
                            call g%fill_exponential(f64)
                        end if
                        call fnv1a_update(h, transfer(f64, [0_int8], 8 * n))
                        deallocate (f64)
                        nbytes = nbytes + 8 * n
                    case default
                        allocate (f32(n))
                        if (d(i)%draws(k) == "fill_normal_f32") then
                            call g%fill_normal(f32)
                        else
                            call g%fill_exponential(f32)
                        end if
                        call fnv1a_update(h, transfer(f32, [0_int8], 4 * n))
                        deallocate (f32)
                        nbytes = nbytes + 4 * n
                    end select
                end do
            end do
            call check(nbytes == d(i)%bytes, d(i)%id//": bytes")
            call check(fnv1a_digest(h) == d(i)%fnv1a, d(i)%id//": fnv1a")
            if (d(i)%end >= 0) call check(g%position() == d(i)%end, d(i)%id//": end")
        end do
    end subroutine

    ! test_stream checks random access against the dumps across blocks, rows and chunks.
    subroutine block_boundaries()
        integer(int64), parameter :: LAST = huge(0_int64), TOP = -huge(0_int64) - 1
        type(tandem_t) :: a, b, before
        complex(real64) :: z64
        complex(real32) :: z32
        real(real64) :: re64, im64
        real(real32) :: re32, im32
        integer(int64) :: x, y
        logical :: ok
        a = tandem_new(42_int64)
        call a%set_position(64_int64)
        b = a
        z64 = a%next_complex64()
        re64 = b%next_real64()
        im64 = b%next_real64()
        call check(all(transfer(z64, 0_int64, 2) == transfer([re64, im64], 0_int64, 2)), &
            "complex64 across a block boundary")
        call a%set_position(96_int64)
        b = a
        z32 = a%next_complex32()
        re32 = b%next_real32()
        im32 = b%next_real32()
        call check(all(transfer(z32, 0_int32, 2) == transfer([re32, im32], 0_int32, 2)), &
            "complex32 across a block boundary")
        call a%set_position(LAST, ok)
        call check(ok .and. a%position() == LAST, "start 2^63 - 1 is accepted")
        before = a
        call a%set_position(TOP, ok)
        call check(.not. ok .and. a%position() == LAST, "start 2^63 is rejected")
        call a%set_position(-1_int64, ok)
        call check(.not. ok .and. a%position() == LAST, "start 2^64 - 1 is rejected")
        x = a%next_int64()
        y = before%next_int64()
        call check(x == y, "a rejected start changes nothing")
        call check(a%position() == TOP + 64, "a 64-bit draw at 2^63 - 1 ends at 2^63 + 64")
    end subroutine

end program
