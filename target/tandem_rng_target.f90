! Tandem8x32 fills on GPUs through OpenMP target offload and do concurrent, in plain Fortran.
! Copyright 2026 Jessica Cox. Apache License 2.0, see LICENSE.
!
! Each fill writes what the CPU fill of the same generator writes, bit for bit, and moves the
! generator past it. One iteration owns one chunk: it seeds the chunk, steps it K times, and
! stores the blocks that fall inside the fill, as the direct kernel of tandem.cuh does. The
! `_target` fills use `!$omp target teams distribute parallel do` (nvfortran -mp=gpu,
! flang -fopenmp --offload-arch, gfortran -fopenmp offloads or falls back to the host) and the
! `_stdpar` fills use `do concurrent` (nvfortran -stdpar=gpu). The array is mapped for the call
! unless the caller already holds it on the device with `!$omp target enter data`, and under
! -stdpar=gpu it lives in managed memory.
!
! Fortran has no unsigned integers, so each 32-bit word lives in an int64 in [0, 2^32), as in
! tandem_rng_device. Normals are not offered: matching the host bit for bit needs tandem.c's
! ziggurat and its fallback generators, which this module does not port.
module tandem_rng_target
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use tandem_rng, only: tandem_t, tandem_from_key
    implicit none
    private

    public :: tandem_fill_target, tandem_fill_stdpar
    public :: tandem_fill_below_target, tandem_fill_below_stdpar

    integer(int64), parameter :: M32 = int(z'ffffffff', int64)
    integer(int64), parameter :: SIGN = -huge(1_int64) - 1_int64
    integer(int64), parameter :: CLOCK_WEYL = int(z'9e3779b9', int64)
    integer(int64), parameter :: DOMAIN_STREAM = int(z'9e3779b9', int64)
    integer(int64), parameter :: DOMAIN_SPLIT = int(z'bb67ae85', int64)
    integer(int64), parameter :: DOMAIN_FOLD = int(z'cd9e8d57', int64)
    integer(int64), parameter :: AUX_STREAM = int(z'94d049bb', int64)
    integer(int64), parameter :: PURPOSE_BELOW32 = int(z'424c573332', int64)
    integer(int64), parameter :: PURPOSE_BELOW64 = int(z'424c573634', int64)

    interface tandem_fill_target
        module procedure target_int32, target_int64, target_real32, target_real64
    end interface
    interface tandem_fill_stdpar
        module procedure stdpar_int32, stdpar_int64, stdpar_real32, stdpar_real64
    end interface
    interface tandem_fill_below_target
        module procedure below_target_int32, below_target_int64
    end interface
    interface tandem_fill_below_stdpar
        module procedure below_stdpar_int32, below_stdpar_int64
    end interface

contains

    pure function round_constant(r) result(c)
        integer, intent(in) :: r
        integer(int64) :: c
        !$omp declare target
        select case (r)
        case (1)
            c = int(z'd17cc1b7', int64)
        case (2)
            c = int(z'a7220a94', int64)
        case (3)
            c = int(z'fe13abe8', int64)
        case (4)
            c = int(z'fa9a6ee0', int64)
        case (5)
            c = int(z'edb14acc', int64)
        case (6)
            c = int(z'9e21c820', int64)
        case (7)
            c = int(z'ff28b1d5', int64)
        case default
            c = int(z'ef5de2b0', int64)
        end select
    end function

    pure function rotl(x, r) result(y)
        integer(int64), intent(in) :: x
        integer, intent(in) :: r
        integer(int64) :: y
        !$omp declare target
        y = iand(ior(ishft(x, r), ishft(x, r - 32)), M32)
    end function

    ! The 64-bit product of two 32-bit words as low and high words, from 16-bit halves of b so
    ! that every intermediate fits a signed int64.
    pure subroutine mul32(a, b, lo, hi)
        integer(int64), intent(in) :: a, b
        integer(int64), intent(out) :: lo, hi
        integer(int64) :: p0, p1, t
        !$omp declare target
        p0 = a * iand(b, int(z'ffff', int64))
        p1 = a * ishft(b, -16)
        t = iand(p0, M32) + ishft(iand(p1, int(z'ffff', int64)), 16)
        lo = iand(t, M32)
        hi = iand(ishft(p0, -32) + ishft(p1, -16) + ishft(t, -32), M32)
    end subroutine

    ! Scalars rather than array elements: nvfortran 25.3 -O2 miscompiles the array form in
    ! offloaded code.
    pure subroutine apply_T(o, h)
        integer(int64), intent(inout) :: o(4), h(4)
        integer(int64) :: lo0, hi0, lo1, hi1, n0, n1, n2, n3, h1, h2, h3, h4
        !$omp declare target
        call mul32(o(1), ior(h(1), 1_int64), lo0, hi0)
        call mul32(o(3), ior(h(2), 1_int64), lo1, hi1)
        n0 = ieor(ieor(o(2), hi1), lo1)
        n1 = ieor(rotl(lo1, 16), h(3))
        n2 = ieor(ieor(o(4), hi0), lo0)
        n3 = ieor(rotl(lo0, 16), h(4))
        h1 = ieor(h(1), rotl(h(2), 7))
        h2 = ieor(h(2), rotl(h(3), 13))
        h3 = ieor(h(3), rotl(h(4), 22))
        h4 = ieor(h(4), rotl(h1, 3))
        h(1) = ieor(iand(h1 + CLOCK_WEYL, M32), n0)
        h(2) = h2
        h(3) = h3
        h(4) = h4
        o(1) = n0
        o(2) = n1
        o(3) = n2
        o(4) = n3
    end subroutine

    pure subroutine f_keyed(key, counter, domain, aux, o, h)
        integer(int64), intent(in) :: key(4), counter, domain, aux
        integer(int64), intent(out) :: o(4), h(4)
        integer(int64) :: t(4)
        integer :: r
        !$omp declare target
        o(1) = iand(counter, M32)
        o(2) = ishft(counter, -32)
        o(3) = domain
        o(4) = aux
        h = key
        do r = 1, 8
            call apply_T(o, h)
            o(1) = ieor(o(1), round_constant(r))
            t = o
            o = h
            h = t
        end do
    end subroutine

    ! trailz is not available in device code.
    pure function log2k(K) result(s)
        integer(int64), intent(in) :: K
        integer :: s
        !$omp declare target
        s = 0
        do while (ishft(K, -s) > 1)
            s = s + 1
        end do
    end function

    ! The exposed half of the block that holds stream bit p, and its offset in words.
    pure subroutine block_at(key, K, p, o, k4)
        integer(int64), intent(in) :: key(4), K, p
        integer(int64), intent(out) :: o(4)
        integer, intent(out) :: k4
        integer(int64) :: h(4), row, j
        !$omp declare target
        row = ishft(p, -10)
        call f_keyed(key, 8 * ishft(row, -log2k(K)) + iand(ishft(p, -7), 7_int64), &
            DOMAIN_STREAM, AUX_STREAM, o, h)
        do j = 0, iand(row, K - 1)
            call apply_T(o, h)
        end do
        k4 = int(iand(ishft(p, -5), 3_int64))
    end subroutine

    pure function bits32(w) result(x)
        integer(int64), intent(in) :: w
        integer(int32) :: x
        !$omp declare target
        x = int(w - 2 * iand(w, 2_int64**31), int32)
    end function


    ! Chunk c of the fill of n int32 elements that starts at the aligned bit p0.
    pure subroutine chunk_int32(key, K, c, p0, n, x)
        integer(int64), intent(in) :: key(4), K, c, p0, n
        integer(int32), intent(inout) :: x(*)
        integer(int64) :: o(4), h(4), g, lane, r0, r1, row, b, idx
        integer :: j, k4
        !$omp declare target
        g = ishft(c, -3)
        lane = iand(c, 7_int64)
        r0 = ishft(p0, -10)
        r1 = ishft(p0 + 32 * n - 1, -10)
        call f_keyed(key, c, DOMAIN_STREAM, AUX_STREAM, o, h)
        do j = 0, int(K) - 1
            row = g * K + j
            if (row > r1) exit
            call apply_T(o, h)
            if (row < r0) cycle
            b = row * 1024 + lane * 128
            do k4 = 0, 3
                idx = ishft(b + 32 * k4 - p0, -5)
                if (b + 32 * k4 >= p0 .and. idx < n) x(idx + 1) = bits32(o(k4 + 1))
            end do
        end do
    end subroutine


    ! Chunk c of the fill of n int64 elements that starts at the aligned bit p0.
    pure subroutine chunk_int64(key, K, c, p0, n, x)
        integer(int64), intent(in) :: key(4), K, c, p0, n
        integer(int64), intent(inout) :: x(*)
        integer(int64) :: o(4), h(4), g, lane, r0, r1, row, b, idx
        integer :: j, k4
        !$omp declare target
        g = ishft(c, -3)
        lane = iand(c, 7_int64)
        r0 = ishft(p0, -10)
        r1 = ishft(p0 + 64 * n - 1, -10)
        call f_keyed(key, c, DOMAIN_STREAM, AUX_STREAM, o, h)
        do j = 0, int(K) - 1
            row = g * K + j
            if (row > r1) exit
            call apply_T(o, h)
            if (row < r0) cycle
            b = row * 1024 + lane * 128
            do k4 = 0, 1
                idx = ishft(b + 64 * k4 - p0, -6)
                if (b + 64 * k4 >= p0 .and. idx < n) &
                    x(idx + 1) = ior(o(2 * k4 + 1), ishft(o(2 * k4 + 2), 32))
            end do
        end do
    end subroutine


    ! Chunk c of the fill of n real32 elements that starts at the aligned bit p0.
    pure subroutine chunk_real32(key, K, c, p0, n, x)
        integer(int64), intent(in) :: key(4), K, c, p0, n
        real(real32), intent(inout) :: x(*)
        integer(int64) :: o(4), h(4), g, lane, r0, r1, row, b, idx
        integer :: j, k4
        !$omp declare target
        g = ishft(c, -3)
        lane = iand(c, 7_int64)
        r0 = ishft(p0, -10)
        r1 = ishft(p0 + 32 * n - 1, -10)
        call f_keyed(key, c, DOMAIN_STREAM, AUX_STREAM, o, h)
        do j = 0, int(K) - 1
            row = g * K + j
            if (row > r1) exit
            call apply_T(o, h)
            if (row < r0) cycle
            b = row * 1024 + lane * 128
            do k4 = 0, 3
                idx = ishft(b + 32 * k4 - p0, -5)
                if (b + 32 * k4 >= p0 .and. idx < n) x(idx + 1) = real(ishft(o(k4 + 1), -8), real32) * 2.0_real32**(-24)
            end do
        end do
    end subroutine


    ! Chunk c of the fill of n real64 elements that starts at the aligned bit p0.
    pure subroutine chunk_real64(key, K, c, p0, n, x)
        integer(int64), intent(in) :: key(4), K, c, p0, n
        real(real64), intent(inout) :: x(*)
        integer(int64) :: o(4), h(4), g, lane, r0, r1, row, b, idx
        integer :: j, k4
        !$omp declare target
        g = ishft(c, -3)
        lane = iand(c, 7_int64)
        r0 = ishft(p0, -10)
        r1 = ishft(p0 + 64 * n - 1, -10)
        call f_keyed(key, c, DOMAIN_STREAM, AUX_STREAM, o, h)
        do j = 0, int(K) - 1
            row = g * K + j
            if (row > r1) exit
            call apply_T(o, h)
            if (row < r0) cycle
            b = row * 1024 + lane * 128
            do k4 = 0, 1
                idx = ishft(b + 64 * k4 - p0, -6)
                if (b + 64 * k4 >= p0 .and. idx < n) &
                    x(idx + 1) = real(ishft(ior(o(2 * k4 + 1), ishft(o(2 * k4 + 2), 32)), -11), real64) * 2.0_real64**(-53)
            end do
        end do
    end subroutine


    ! The 128-bit product of two 64-bit words as low and high words.
    pure subroutine mul64(a, b, lo, hi)
        integer(int64), intent(in) :: a, b
        integer(int64), intent(out) :: lo, hi
        integer(int64) :: ll0, ll1, lh0, lh1, hl0, hl1, hh0, hh1, mid, up
        !$omp declare target
        call mul32(iand(a, M32), iand(b, M32), ll0, ll1)
        call mul32(iand(a, M32), iand(ishft(b, -32), M32), lh0, lh1)
        call mul32(iand(ishft(a, -32), M32), iand(b, M32), hl0, hl1)
        call mul32(iand(ishft(a, -32), M32), iand(ishft(b, -32), M32), hh0, hh1)
        mid = ll1 + lh0 + hl0
        up = hh0 + lh1 + hl1 + ishft(mid, -32)
        lo = ior(ll0, ishft(iand(mid, M32), 32))
        hi = ior(iand(up, M32), ishft(iand(hh1 + ishft(up, -32), M32), 32))
    end subroutine

    pure function unsigned_less(a, b) result(r)
        integer(int64), intent(in) :: a, b
        logical :: r
        !$omp declare target
        r = ieor(a, SIGN) < ieor(b, SIGN)
    end function

    ! (2^64 - n) mod n for n > 0, by shift and subtract: it runs only after a rejected draw.
    pure function threshold64(n) result(t)
        integer(int64), intent(in) :: n
        integer(int64) :: t, a
        integer :: i
        logical :: top
        !$omp declare target
        a = not(n)
        t = 0
        do i = 63, 0, -1
            top = btest(t, 63)
            t = ior(ishft(t, 1), iand(ishft(a, -i), 1_int64))
            if (top .or. .not. unsigned_less(t, n)) t = t - n
        end do
        t = t + 1
        if (t == n) t = 0
    end function

    ! The key of split(i) of sub(purpose), the fallback generator of a rejected element.
    pure function fallback_key(key, purpose, i) result(k2)
        integer(int64), intent(in) :: key(4), purpose, i
        integer(int64) :: k2(4), o(4), h(4), sub(4)
        !$omp declare target
        call f_keyed(key, purpose, DOMAIN_FOLD, 0_int64, o, h)
        sub = o
        call f_keyed(sub, ishft(i, -1), DOMAIN_SPLIT, 0_int64, o, h)
        if (btest(i, 0)) then
            k2 = h
        else
            k2 = o
        end if
    end function

    pure function retry32(key, K, r, t, i) result(hi)
        integer(int64), intent(in) :: key(4), K, r, t, i
        integer(int64) :: hi, lo, k2(4), o(4), d
        integer :: k4
        !$omp declare target
        k2 = fallback_key(key, PURPOSE_BELOW32, i)
        d = 0
        do
            call block_at(k2, K, 32 * d, o, k4)
            call mul32(o(k4 + 1), r, lo, hi)
            if (lo >= t) exit
            d = d + 1
        end do
    end function

    pure function retry64(key, K, r, t, i) result(hi)
        integer(int64), intent(in) :: key(4), K, r, t, i
        integer(int64) :: hi, lo, k2(4), o(4), d
        integer :: k4
        !$omp declare target
        k2 = fallback_key(key, PURPOSE_BELOW64, i)
        d = 0
        do
            call block_at(k2, K, 64 * d, o, k4)
            call mul64(ior(o(k4 + 1), ishft(o(k4 + 2), 32)), r, lo, hi)
            if (.not. unsigned_less(lo, t)) exit
            d = d + 1
        end do
    end function

    ! The draw v of global draw index i (the start position over the width, plus the element index) is
    ! rejected into the fallback generator keyed by i.
    pure function below32(key, K, v, r, i) result(x)
        integer(int64), intent(in) :: key(4), K, r, i
        integer(int32), intent(in) :: v
        integer(int32) :: x
        integer(int64) :: lo, hi, t
        !$omp declare target
        call mul32(iand(int(v, int64), M32), r, lo, hi)
        if (lo < r) then
            t = mod(M32 + 1 - r, r)
            if (lo < t) hi = retry32(key, K, r, t, i)
        end if
        x = bits32(hi)
    end function

    pure function below64(key, K, v, r, i) result(x)
        integer(int64), intent(in) :: key(4), K, v, r, i
        integer(int64) :: x, lo, t
        !$omp declare target
        call mul64(v, r, lo, x)
        if (unsigned_less(lo, r)) then
            t = threshold64(r)
            if (unsigned_less(lo, t)) x = retry64(key, K, r, t, i)
        end if
    end function

    ! The aligned start, the first chunk and the number of chunks of a fill of n elements of
    ! width w bits.
    ! A fill may end at or past 2^63, where set_position refuses a start.
    subroutine move_to(rng, pos)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: pos
        rng = tandem_from_key(rng%key(), pos, rng%chunk_length())
    end subroutine

    subroutine plan(rng, w, n, key, K, p0, c0, nchunks)
        type(tandem_t), intent(in) :: rng
        integer, intent(in) :: w
        integer(int64), intent(in) :: n
        integer(int64), intent(out) :: key(4), K, p0, c0, nchunks
        integer(int64) :: r0, r1
        key = iand(int(rng%key(), int64), M32)
        K = rng%chunk_length()
        p0 = iand(rng%position() + (w - 1), not(int(w - 1, int64)))
        r0 = ishft(p0, -10)
        r1 = ishft(p0 + w * n - 1, -10)
        c0 = 8 * (r0 / K)
        nchunks = 8 * (r1 / K - r0 / K + 1)
    end subroutine


    subroutine target_int32(rng, x)
        type(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 32, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_target_int32(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 32 * n)
    end subroutine

    subroutine run_target_int32(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        integer(int32), intent(inout) :: x(n)
        integer(int64) :: t
        !$omp target teams distribute parallel do map(from: x)
        do t = 0, nchunks - 1
            call chunk_int32(key, K, c0 + t, p0, n, x)
        end do
        !$omp end target teams distribute parallel do
    end subroutine


    subroutine target_int64(rng, x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 64, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_target_int64(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 64 * n)
    end subroutine

    subroutine run_target_int64(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        integer(int64), intent(inout) :: x(n)
        integer(int64) :: t
        !$omp target teams distribute parallel do map(from: x)
        do t = 0, nchunks - 1
            call chunk_int64(key, K, c0 + t, p0, n, x)
        end do
        !$omp end target teams distribute parallel do
    end subroutine


    subroutine target_real32(rng, x)
        type(tandem_t), intent(inout) :: rng
        real(real32), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 32, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_target_real32(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 32 * n)
    end subroutine

    subroutine run_target_real32(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        real(real32), intent(inout) :: x(n)
        integer(int64) :: t
        !$omp target teams distribute parallel do map(from: x)
        do t = 0, nchunks - 1
            call chunk_real32(key, K, c0 + t, p0, n, x)
        end do
        !$omp end target teams distribute parallel do
    end subroutine


    subroutine target_real64(rng, x)
        type(tandem_t), intent(inout) :: rng
        real(real64), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 64, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_target_real64(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 64 * n)
    end subroutine

    subroutine run_target_real64(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        real(real64), intent(inout) :: x(n)
        integer(int64) :: t
        !$omp target teams distribute parallel do map(from: x)
        do t = 0, nchunks - 1
            call chunk_real64(key, K, c0 + t, p0, n, x)
        end do
        !$omp end target teams distribute parallel do
    end subroutine


    ! Uniform on [0, bound) as the host fill_below: an element takes the draw of the plain fill, and a
    ! rejected draw retries on the fallback keyed by its global draw index.
    subroutine below_target_int32(rng, x, bound)
        type(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), contiguous :: x(:)
        integer(int32), intent(in) :: bound
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        if (n == 0) return
        call plan(rng, 32, n, key, K, p0, c0, nchunks)
        call run_target_int32(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 32 * n)
        call run_below_target_int32(key, K, ishft(p0, -5), n, iand(int(bound, int64), M32), x)
    end subroutine

    subroutine run_below_target_int32(key, K, g0, n, r, x)
        integer(int64), intent(in) :: key(4), K, g0, n, r
        integer(int32), intent(inout) :: x(n)
        integer(int64) :: i
        !$omp target teams distribute parallel do map(tofrom: x)
        do i = 1, n
            x(i) = below32(key, K, x(i), r, g0 + i - 1)
        end do
        !$omp end target teams distribute parallel do
    end subroutine


    ! Uniform on [0, bound) as the host fill_below: an element takes the draw of the plain fill, and a
    ! rejected draw retries on the fallback keyed by its global draw index.
    subroutine below_target_int64(rng, x, bound)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), contiguous :: x(:)
        integer(int64), intent(in) :: bound
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        if (n == 0) return
        call plan(rng, 64, n, key, K, p0, c0, nchunks)
        call run_target_int64(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 64 * n)
        call run_below_target_int64(key, K, ishft(p0, -6), n, bound, x)
    end subroutine

    subroutine run_below_target_int64(key, K, g0, n, r, x)
        integer(int64), intent(in) :: key(4), K, g0, n, r
        integer(int64), intent(inout) :: x(n)
        integer(int64) :: i
        !$omp target teams distribute parallel do map(tofrom: x)
        do i = 1, n
            x(i) = below64(key, K, x(i), r, g0 + i - 1)
        end do
        !$omp end target teams distribute parallel do
    end subroutine


    subroutine stdpar_int32(rng, x)
        type(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 32, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_stdpar_int32(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 32 * n)
    end subroutine

    subroutine run_stdpar_int32(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        integer(int32), intent(inout) :: x(n)
        integer(int64) :: t
        do concurrent (t = 0:nchunks - 1)
            call chunk_int32(key, K, c0 + t, p0, n, x)
        end do
    end subroutine


    subroutine stdpar_int64(rng, x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 64, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_stdpar_int64(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 64 * n)
    end subroutine

    subroutine run_stdpar_int64(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        integer(int64), intent(inout) :: x(n)
        integer(int64) :: t
        do concurrent (t = 0:nchunks - 1)
            call chunk_int64(key, K, c0 + t, p0, n, x)
        end do
    end subroutine


    subroutine stdpar_real32(rng, x)
        type(tandem_t), intent(inout) :: rng
        real(real32), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 32, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_stdpar_real32(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 32 * n)
    end subroutine

    subroutine run_stdpar_real32(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        real(real32), intent(inout) :: x(n)
        integer(int64) :: t
        do concurrent (t = 0:nchunks - 1)
            call chunk_real32(key, K, c0 + t, p0, n, x)
        end do
    end subroutine


    subroutine stdpar_real64(rng, x)
        type(tandem_t), intent(inout) :: rng
        real(real64), intent(out), contiguous :: x(:)
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        call plan(rng, 64, n, key, K, p0, c0, nchunks)
        if (n > 0) call run_stdpar_real64(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 64 * n)
    end subroutine

    subroutine run_stdpar_real64(key, K, p0, c0, nchunks, n, x)
        integer(int64), intent(in) :: key(4), K, p0, c0, nchunks, n
        real(real64), intent(inout) :: x(n)
        integer(int64) :: t
        do concurrent (t = 0:nchunks - 1)
            call chunk_real64(key, K, c0 + t, p0, n, x)
        end do
    end subroutine


    ! Uniform on [0, bound) as the host fill_below: an element takes the draw of the plain fill, and a
    ! rejected draw retries on the fallback keyed by its global draw index.
    subroutine below_stdpar_int32(rng, x, bound)
        type(tandem_t), intent(inout) :: rng
        integer(int32), intent(out), contiguous :: x(:)
        integer(int32), intent(in) :: bound
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        if (n == 0) return
        call plan(rng, 32, n, key, K, p0, c0, nchunks)
        call run_stdpar_int32(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 32 * n)
        call run_below_stdpar_int32(key, K, ishft(p0, -5), n, iand(int(bound, int64), M32), x)
    end subroutine

    subroutine run_below_stdpar_int32(key, K, g0, n, r, x)
        integer(int64), intent(in) :: key(4), K, g0, n, r
        integer(int32), intent(inout) :: x(n)
        integer(int64) :: i
        do concurrent (i = 1:n)
            x(i) = below32(key, K, x(i), r, g0 + i - 1)
        end do
    end subroutine


    ! Uniform on [0, bound) as the host fill_below: an element takes the draw of the plain fill, and a
    ! rejected draw retries on the fallback keyed by its global draw index.
    subroutine below_stdpar_int64(rng, x, bound)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(out), contiguous :: x(:)
        integer(int64), intent(in) :: bound
        integer(int64) :: key(4), K, p0, c0, nchunks, n
        n = size(x, kind=int64)
        if (n == 0) return
        call plan(rng, 64, n, key, K, p0, c0, nchunks)
        call run_stdpar_int64(key, K, p0, c0, nchunks, n, x)
        call move_to(rng, p0 + 64 * n)
        call run_below_stdpar_int64(key, K, ishft(p0, -6), n, bound, x)
    end subroutine

    subroutine run_below_stdpar_int64(key, K, g0, n, r, x)
        integer(int64), intent(in) :: key(4), K, g0, n, r
        integer(int64), intent(inout) :: x(n)
        integer(int64) :: i
        do concurrent (i = 1:n)
            x(i) = below64(key, K, x(i), r, g0 + i - 1)
        end do
    end subroutine


end module tandem_rng_target
