! Bounded integers and normals against the values core.hpp of tandem-cuda produces, as
! captured in tandem-c's cross fixtures (test/cross.f90), plus the fill and rank properties.
program test_sampling
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use tandem_rng
    use tandem_cross
    implicit none

    integer :: failures = 0, checks = 0

    call below_cross()
    call fill_below_cross()
    call below_zero()
    call below_ranks()
    call below_cut()
    call normal_cross()
    call normal_fills()
    call normal_ranks()

    if (failures > 0) then
        print '(i0, " of ", i0, " checks failed")', failures, checks
        error stop 1
    end if
    print '("sampling: ", i0, " checks ok")', checks

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

    ! The fixtures start from seed 42 after one logical draw, which leaves the generator
    ! unaligned.
    function start() result(rng)
        type(tandem_t) :: rng
        logical :: skip
        rng = tandem_new(42_int64)
        skip = rng%next_logical()
    end function

    ! The end position pins the number of rejected draws as well as the values.
    subroutine below_cross()
        type(tandem_t) :: g
        integer(int32) :: got32(CROSS_COUNT)
        integer(int64) :: got64(CROSS_COUNT)
        integer :: c, i
        do c = 1, size(CROSS_BELOW32_N)
            g = start()
            got32 = [(g%below(CROSS_BELOW32_N(c)), i = 1, CROSS_COUNT)]
            call check(all(got32 == CROSS_BELOW32_WANT(:, c)), "below int32 values")
            call check(g%position() == CROSS_BELOW32_END(c), "below int32 position")
        end do
        do c = 1, size(CROSS_BELOW64_N)
            g = start()
            got64 = [(g%below(CROSS_BELOW64_N(c)), i = 1, CROSS_COUNT)]
            call check(all(got64 == CROSS_BELOW64_WANT(:, c)), "below int64 values")
            call check(g%position() == CROSS_BELOW64_END(c), "below int64 position")
        end do
    end subroutine

    ! The large ranges reject often, so these fills run the fallback generator.
    subroutine fill_below_cross()
        type(tandem_t) :: g
        integer(int32) :: got32(CROSS_COUNT)
        integer(int64) :: got64(CROSS_COUNT)
        integer :: c
        do c = 1, size(CROSS_FILL_BELOW32_N)
            g = tandem_new(42_int64)
            call g%set_position(CROSS_FILL_BELOW32_START(c))
            call g%fill_below(got32, CROSS_FILL_BELOW32_N(c))
            call check(all(got32 == CROSS_FILL_BELOW32_WANT(:, c)), "fill_below int32 values")
            call check(g%position() == CROSS_FILL_BELOW32_END(c), "fill_below int32 position")
        end do
        do c = 1, size(CROSS_FILL_BELOW64_N)
            g = tandem_new(42_int64)
            call g%set_position(CROSS_FILL_BELOW64_START(c))
            call g%fill_below(got64, CROSS_FILL_BELOW64_N(c))
            call check(all(got64 == CROSS_FILL_BELOW64_WANT(:, c)), "fill_below int64 values")
            call check(g%position() == CROSS_FILL_BELOW64_END(c), "fill_below int64 position")
        end do
    end subroutine

    ! n = 0 returns 0 and still consumes a draw, as core.hpp does.
    subroutine below_zero()
        type(tandem_t) :: g
        integer(int32) :: k32
        integer(int64) :: k64
        g = tandem_new(1_int64, 2_int64)
        k32 = g%below(0_int32)
        call check(k32 == 0 .and. g%position() == 32, "below int32 n = 0")
        k64 = g%below(0_int64)
        call check(k64 == 0 .and. g%position() == 128, "below int64 n = 0")
    end subroutine

    subroutine below_ranks()
        type(tandem_t) :: a, b
        integer(int32) :: flat(60), grid(3, 4, 5)
        a = start()
        b = a
        call a%fill_below(flat, 1000_int32)
        call b%fill_below(grid, 1000_int32)
        call check(all(reshape(grid, [60]) == flat), "fill_below rank 3 equals rank 1")
    end subroutine

    ! A bounded fill cut at an arbitrary element boundary equals the whole fill, rejected draws
    ! included: the fallback of a rejected draw is keyed by its global draw index. The bounds
    ! reject a quarter of the draws, and the start is unaligned and nonzero.
    subroutine below_cut()
        integer, parameter :: n = 1000, cuts(3) = [1, 337, 999]
        type(tandem_t) :: whole, part
        integer(int32) :: w32(n), p32(n)
        integer(int64) :: w64(n), p64(n)
        integer :: j, m
        do j = 1, size(cuts)
            m = cuts(j)
            whole = start()
            part = whole
            call whole%fill_below(w32, -1073741823_int32)
            call part%fill_below(p32(:m), -1073741823_int32)
            call part%fill_below(p32(m + 1:), -1073741823_int32)
            call check(all(w32 == p32) .and. whole%position() == part%position(), "below int32 cut")
            whole = start()
            part = whole
            call whole%fill_below(w64, -4611686018427387903_int64)
            call part%fill_below(p64(:m), -4611686018427387903_int64)
            call part%fill_below(p64(m + 1:), -4611686018427387903_int64)
            call check(all(w64 == p64) .and. whole%position() == part%position(), "below int64 cut")
        end do
    end subroutine

    ! Bit for bit, since tandem.c's normals use no libm. A pair takes two uniforms. One draw per
    ! statement, because a function reference must not affect another in the same statement.
    subroutine normal_cross()
        type(tandem_t) :: g
        real(real64) :: z64(2 * CROSS_COUNT)
        real(real32) :: z32(2 * CROSS_COUNT)
        integer :: i
        g = start()
        do i = 1, CROSS_COUNT
            z64(2 * i - 1:2 * i) = g%next_normal_pair64()
        end do
        call check(all(transfer(z64, 0_int64, size(z64)) == transfer(CROSS_NORMAL, 0_int64, size(z64))), &
            "normal pair64 values")
        call check(g%position() == CROSS_NORMAL_END, "normal pair64 position")
        g = start()
        do i = 1, CROSS_COUNT
            z32(2 * i - 1:2 * i) = g%next_normal_pair32()
        end do
        call check(all(transfer(z32, 0_int32, size(z32)) == transfer(CROSS_NORMALF, 0_int32, size(z32))), &
            "normal pair32 values")
        call check(g%position() == CROSS_NORMALF_END, "normal pair32 position")
    end subroutine

    ! The scalar normal is the cos half of the pair and consumes both uniforms. A fill is the
    ! flattened pairs, bit for bit, across block boundaries and from an unaligned start, and an
    ! odd size drops the last sin half but still consumes both uniforms.
    subroutine normal_fills()
        integer, parameter :: sizes(6) = [0, 1, 2, 3, 250, 1000]
        type(tandem_t) :: a, b
        real(real64), allocatable :: want64(:), got64(:)
        real(real32), allocatable :: want32(:), got32(:)
        real(real64) :: z64(2)
        real(real32) :: z32(2)
        integer :: i, j, n
        do j = 1, size(sizes)
            n = sizes(j)
            allocate (want64(n), got64(n), want32(n), got32(n))
            a = start()
            b = a
            do i = 1, n, 2
                z64 = a%next_normal_pair64()
                want64(i) = z64(1)
                if (i < n) want64(i + 1) = z64(2)
            end do
            call b%fill_normal(got64)
            call check(all(transfer(got64, 0_int64, n) == transfer(want64, 0_int64, n)), &
                "fill_normal real64 equals pairs")
            call check(a%position() == b%position(), "fill_normal real64 position")
            a = start()
            b = a
            do i = 1, n, 2
                z32 = a%next_normal_pair32()
                want32(i) = z32(1)
                if (i < n) want32(i + 1) = z32(2)
            end do
            call b%fill_normal(got32)
            call check(all(transfer(got32, 0_int32, n) == transfer(want32, 0_int32, n)), &
                "fill_normal real32 equals pairs")
            call check(a%position() == b%position(), "fill_normal real32 position")
            deallocate (want64, got64, want32, got32)
        end do
        a = start()
        b = a
        z64 = a%next_normal_pair64()
        call check(transfer(b%next_normal64(), 0_int64) == transfer(z64(1), 0_int64) .and. &
            a%position() == b%position(), "next_normal64 is the cos half")
        a = start()
        b = a
        z32 = a%next_normal_pair32()
        call check(transfer(b%next_normal32(), 0_int32) == transfer(z32(1), 0_int32) .and. &
            a%position() == b%position(), "next_normal32 is the cos half")
    end subroutine

    subroutine normal_ranks()
        type(tandem_t) :: a, b
        real(real64) :: grid(10, 10, 10), flat(1000)
        a = start()
        b = a
        call a%fill_normal(grid)
        call b%fill_normal(flat)
        call check(all(transfer(grid, 0_int64, 1000) == transfer(flat, 0_int64, 1000)), &
            "fill_normal rank 3 equals rank 1")
    end subroutine

end program
