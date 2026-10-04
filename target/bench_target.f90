! Throughput of the OpenMP target and do concurrent fills: 2^28 elements, the minimum of seven
! timings after two warm-up fills. Arrays are held on the device with `target enter data`, or
! live in managed memory under -stdpar=gpu, so the timings exclude host transfers. Reading one
! element after each fill makes the do concurrent timing wait for the kernel.
program bench_target
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use tandem_rng
    use tandem_rng_target
    implicit none

    integer(int64), parameter :: n = 2_int64**28
    integer, parameter :: runs = 7
    real(real64) :: sink = 0

    call run_real64()
    call run_real32()
    call run_int64()
    call run_int32()
    call run_below32()
    if (sink < 0) print *, sink

contains

    function now() result(t)
        real(real64) :: t
        integer(int64) :: c, r
        call system_clock(c, r)
        t = real(c, real64) / real(r, real64)
    end function

    subroutine report(name, v, bytes, best)
        character(*), intent(in) :: name
        integer, intent(in) :: v
        real(real64), intent(in) :: bytes, best
        character(8) :: label
        label = merge("target  ", "stdpar  ", v == 1)
        print '(a, 1x, a, 1x, f8.1, " GiB/s")', label, name, bytes / best / 2.0_real64**30
    end subroutine

    subroutine run_real64()
        real(real64), allocatable :: x(:)
        type(tandem_t) :: rng
        real(real64) :: t, best
        integer :: v, i
        allocate (x(n))
        !$omp target enter data map(alloc: x)
        do v = 1, 2
            rng = tandem_new(1_int64)
            best = huge(best)
            do i = -1, runs
                t = now()
                if (v == 1) then
                    call tandem_fill_target(rng, x)
                else
                    call tandem_fill_stdpar(rng, x)
                end if
                sink = sink + x(1)
                t = now() - t
                if (i > 0) best = min(best, t)
                call rng%set_position(0_int64)
            end do
            call report("real64", v, 8.0_real64 * n, best)
        end do
        !$omp target exit data map(delete: x)
    end subroutine

    subroutine run_real32()
        real(real32), allocatable :: x(:)
        type(tandem_t) :: rng
        real(real64) :: t, best
        integer :: v, i
        allocate (x(n))
        !$omp target enter data map(alloc: x)
        do v = 1, 2
            rng = tandem_new(1_int64)
            best = huge(best)
            do i = -1, runs
                t = now()
                if (v == 1) then
                    call tandem_fill_target(rng, x)
                else
                    call tandem_fill_stdpar(rng, x)
                end if
                sink = sink + x(1)
                t = now() - t
                if (i > 0) best = min(best, t)
                call rng%set_position(0_int64)
            end do
            call report("real32", v, 4.0_real64 * n, best)
        end do
        !$omp target exit data map(delete: x)
    end subroutine

    subroutine run_int64()
        integer(int64), allocatable :: x(:)
        type(tandem_t) :: rng
        real(real64) :: t, best
        integer :: v, i
        allocate (x(n))
        !$omp target enter data map(alloc: x)
        do v = 1, 2
            rng = tandem_new(1_int64)
            best = huge(best)
            do i = -1, runs
                t = now()
                if (v == 1) then
                    call tandem_fill_target(rng, x)
                else
                    call tandem_fill_stdpar(rng, x)
                end if
                sink = sink + real(x(1), real64)
                t = now() - t
                if (i > 0) best = min(best, t)
                call rng%set_position(0_int64)
            end do
            call report("int64", v, 8.0_real64 * n, best)
        end do
        !$omp target exit data map(delete: x)
    end subroutine

    subroutine run_int32()
        integer(int32), allocatable :: x(:)
        type(tandem_t) :: rng
        real(real64) :: t, best
        integer :: v, i
        allocate (x(n))
        !$omp target enter data map(alloc: x)
        do v = 1, 2
            rng = tandem_new(1_int64)
            best = huge(best)
            do i = -1, runs
                t = now()
                if (v == 1) then
                    call tandem_fill_target(rng, x)
                else
                    call tandem_fill_stdpar(rng, x)
                end if
                sink = sink + real(x(1), real64)
                t = now() - t
                if (i > 0) best = min(best, t)
                call rng%set_position(0_int64)
            end do
            call report("int32", v, 4.0_real64 * n, best)
        end do
        !$omp target exit data map(delete: x)
    end subroutine

    subroutine run_below32()
        integer(int32), allocatable :: x(:)
        type(tandem_t) :: rng
        real(real64) :: t, best
        integer :: v, i
        allocate (x(n))
        !$omp target enter data map(alloc: x)
        do v = 1, 2
            rng = tandem_new(1_int64)
            best = huge(best)
            do i = -1, runs
                t = now()
                if (v == 1) then
                    call tandem_fill_below_target(rng, x, 1000_int32)
                else
                    call tandem_fill_below_stdpar(rng, x, 1000_int32)
                end if
                sink = sink + real(x(1), real64)
                t = now() - t
                if (i > 0) best = min(best, t)
                call rng%set_position(0_int64)
            end do
            call report("below int32", v, 4.0_real64 * n, best)
        end do
        !$omp target exit data map(delete: x)
    end subroutine

end program bench_target
