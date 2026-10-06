! Throughput on one thread: GiB/s written, minimum time of seven runs after a warm-up, for Tandem
! and for the intrinsic random_number (gfortran's xoshiro256**) on the same row.
! Run with `fpm run --example bench --profile release`.
program bench
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use tandem_rng
    implicit none

    integer(int64), parameter :: n = 2_int64**24
    integer, parameter :: runs = 7, rows = 7
    real(real64), parameter :: two_pi = 6.283185307179586_real64
    real(real64), allocatable :: x64(:)
    real(real32), allocatable :: x32(:)
    integer(int32), allocatable :: i32(:)
    integer(int64), allocatable :: i64(:)
    type(tandem_t) :: rng
    integer :: k
    integer(int64) :: t0, t1, rate
    real(real64) :: sink

    allocate (x64(n), x32(n), i32(n), i64(n))
    rng = tandem_new(42_int64)
    call system_clock(count_rate=rate)
    x64 = 0
    x32 = 0
    i32 = 0
    i64 = 0
    print '("n = 2^24 elements, minimum of ", i0, " runs, GiB/s")', runs
    print '(a40, 2a10)', "", "Tandem", "random_number"
    sink = 0
    ! Run for half a second so the clock has ramped up.
    call system_clock(t0)
    t1 = t0
    do while (t1 - t0 < rate / 2)
        call rng%fill(i32)
        call system_clock(t1)
    end do
    do k = 1, rows
        print '(a40, 2f10.2)', label(k), gibs(k, .true.), gibs(k, .false.)
    end do
    if (sink < 0) print *, sink

contains

    ! GiB/s of row k, by Tandem when `ours`, else by random_number.
    function gibs(k, ours)
        integer, intent(in) :: k
        logical, intent(in) :: ours
        real(real64) :: gibs, best
        integer :: r
        best = huge(best)
        do r = 0, runs
            call system_clock(t0)
            if (ours) then
                call tandem_row(k)
            else
                call intrinsic_row(k)
            end if
            call system_clock(t1)
            if (r > 0) best = min(best, real(t1 - t0, real64) / real(rate, real64))
        end do
        sink = sink + x64(n / 2) + x32(n / 2) + i32(n / 2) + i64(n / 2)
        gibs = real(n * bytes(k), real64) / best / 2.0_real64**30
    end function

    subroutine tandem_row(k)
        integer, intent(in) :: k
        integer(int64) :: i
        select case (k)
        case (1)
            call rng%fill(x64)
        case (2)
            call rng%fill(x32)
        case (3)
            call rng%fill(i32)
        case (4)
            call rng%fill(i64)
        case (5)
            do i = 1, n
                x64(i) = rng%next_real64()
            end do
        case (6)
            call rng%fill_normal(x64)
        case (7)
            call rng%fill_normal(x32)
        end select
    end subroutine

    ! The fastest intrinsic route to each row. random_number gives reals only, so the integers
    ! scale a real64 draw: all 32 bits for int32, 53 of the 64 for int64. The normals are
    ! Box-Muller pairs from one array of uniforms, computed in the row's precision.
    subroutine intrinsic_row(k)
        integer, intent(in) :: k
        integer(int64) :: i, h
        real(real64) :: r
        real(real32) :: s
        h = n / 2
        select case (k)
        case (1)
            call random_number(x64)
        case (2)
            call random_number(x32)
        case (3)
            call random_number(x64)
            i32 = int(x64 * 4294967296.0_real64 - 2147483648.0_real64, int32)
        case (4)
            call random_number(x64)
            i64 = int(x64 * 9223372036854775808.0_real64, int64)
        case (5)
            do i = 1, n
                call random_number(x64(i))
            end do
        case (6)
            call random_number(x64)
            do i = 1, h
                r = sqrt(-2 * log(1 - x64(i)))
                x64(h + i) = two_pi * x64(h + i)
                x64(i) = r * cos(x64(h + i))
                x64(h + i) = r * sin(x64(h + i))
            end do
        case (7)
            call random_number(x32)
            do i = 1, h
                s = sqrt(-2 * log(1 - x32(i)))
                x32(h + i) = real(two_pi, real32) * x32(h + i)
                x32(i) = s * cos(x32(h + i))
                x32(h + i) = s * sin(x32(h + i))
            end do
        end select
    end subroutine

    function label(k)
        integer, intent(in) :: k
        character(40) :: label
        character(40), parameter :: labels(rows) = [character(40) :: &
            "fill(real64 array)", "fill(real32 array)", "fill(int32 array)", &
            "fill(int64 array)", "next_real64() in a loop", &
            "fill_normal(real64 array)", "fill_normal(real32 array)"]
        label = labels(k)
    end function

    function bytes(k)
        integer, intent(in) :: k
        integer(int64) :: bytes
        integer(int64), parameter :: sizes(rows) = [8, 4, 4, 8, 8, 8, 4]
        bytes = sizes(k)
    end function

end program bench
