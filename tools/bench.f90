! Fill throughput on one thread: GiB/s written, minimum time of seven runs after a warm-up.
! Run with `fpm run --example bench --profile release`.
program bench
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use tandem_rng
    implicit none

    integer(int64), parameter :: n = 2_int64**24
    integer, parameter :: runs = 7
    real(real64), allocatable :: x64(:)
    real(real32), allocatable :: x32(:)
    integer(int32), allocatable :: i32(:)
    integer(int64), allocatable :: i64(:)
    type(tandem_t) :: rng
    integer :: r, which
    integer(int64) :: t0, t1, rate
    real(real64) :: best, sink

    allocate (x64(n), x32(n), i32(n), i64(n))
    rng = tandem_new(42_int64)
    call system_clock(count_rate=rate)
    x64 = 0
    x32 = 0
    i32 = 0
    i64 = 0
    print '("n = 2^24 elements, minimum of ", i0, " runs")', runs
    sink = 0
    ! Run for half a second so the clock has ramped up.
    call system_clock(t0)
    t1 = t0
    do while (t1 - t0 < rate / 2)
        call rng%fill(i32)
        call system_clock(t1)
    end do
    do which = 1, 9
        best = huge(best)
        do r = 0, runs
            call system_clock(t0)
            select case (which)
            case (1)
                call rng%fill(x64)
            case (2)
                call rng%fill(x32)
            case (3)
                call rng%fill(i32)
            case (4)
                call rng%fill(i64)
            case (5)
                call scalar_draws()
            case (6)
                call random_number(x64)
            case (7)
                call random_number(x32)
            case (8)
                call rng%fill_normal(x64)
            case (9)
                call rng%fill_normal(x32)
            end select
            call system_clock(t1)
            if (r > 0) best = min(best, real(t1 - t0, real64) / real(rate, real64))
        end do
        sink = sink + x64(n / 2) + x32(n / 2) + i32(n / 2) + i64(n / 2)
        print '(a40, f8.2, " GiB/s")', label(which), &
            real(n * bytes(which), real64) / best / 2.0_real64**30
    end do
    if (sink < 0) print *, sink

contains

    subroutine scalar_draws()
        integer(int64) :: i
        do i = 1, n
            x64(i) = rng%next_real64()
        end do
    end subroutine

    function label(k)
        integer, intent(in) :: k
        character(40) :: label
        character(40), parameter :: labels(9) = [character(40) :: &
            "rng%fill(real64 array)", "rng%fill(real32 array)", "rng%fill(int32 array)", &
            "rng%fill(int64 array)", "rng%next_real64() in a loop", &
            "intrinsic random_number(real64 array)", "intrinsic random_number(real32 array)", &
            "rng%fill_normal(real64 array)", "rng%fill_normal(real32 array)"]
        label = labels(k)
    end function

    function bytes(k)
        integer, intent(in) :: k
        integer(int64) :: bytes
        integer(int64), parameter :: sizes(9) = [8, 4, 4, 8, 8, 8, 4, 8, 4]
        bytes = sizes(k)
    end function

end program bench
