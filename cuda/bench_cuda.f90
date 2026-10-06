! Device fill throughput: GiB/s written, minimum of 21 cudaEvent timings per row of 2^28
! elements, after a half-second warm-up, for the tandem fills and for cuRAND Philox4x32-10 with
! the same output type. cuRAND has no 64-bit integer output for Philox, so curandGenerate writes
! the int64 row's bytes as 32-bit words. Run with `make -f cuda/Makefile bench`.
program bench_cuda
    use, intrinsic :: iso_c_binding, only: c_float, c_int, c_long_long, c_ptr, c_size_t
    use, intrinsic :: iso_fortran_env, only: int64, real64
    use tandem_rng
    use tandem_rng_cuda
    implicit none

    interface
        function cuda_event_create(e) result(err) bind(C, name="cudaEventCreate")
            import :: c_int, c_ptr
            type(c_ptr), intent(out) :: e
            integer(c_int) :: err
        end function
        function cuda_event_record(e, stream) result(err) bind(C, name="cudaEventRecord")
            import :: c_int, c_ptr
            type(c_ptr), value :: e, stream
            integer(c_int) :: err
        end function
        function cuda_event_synchronize(e) result(err) bind(C, name="cudaEventSynchronize")
            import :: c_int, c_ptr
            type(c_ptr), value :: e
            integer(c_int) :: err
        end function
        function cuda_event_elapsed_time(ms, e0, e1) result(err) &
            bind(C, name="cudaEventElapsedTime")
            import :: c_float, c_int, c_ptr
            real(c_float), intent(out) :: ms
            type(c_ptr), value :: e0, e1
            integer(c_int) :: err
        end function
        function curand_create_generator(g, kind) result(err) bind(C, name="curandCreateGenerator")
            import :: c_int, c_ptr
            type(c_ptr), intent(out) :: g
            integer(c_int), value :: kind
            integer(c_int) :: err
        end function
        function curand_set_seed(g, seed) result(err) &
            bind(C, name="curandSetPseudoRandomGeneratorSeed")
            import :: c_int, c_long_long, c_ptr
            type(c_ptr), value :: g
            integer(c_long_long), value :: seed
            integer(c_int) :: err
        end function
        function curand_generate(g, out, num) result(err) bind(C, name="curandGenerate")
            import :: c_int, c_ptr, c_size_t
            type(c_ptr), value :: g, out
            integer(c_size_t), value :: num
            integer(c_int) :: err
        end function
        function curand_generate_uniform(g, out, num) result(err) &
            bind(C, name="curandGenerateUniform")
            import :: c_int, c_ptr, c_size_t
            type(c_ptr), value :: g, out
            integer(c_size_t), value :: num
            integer(c_int) :: err
        end function
        function curand_generate_uniform_double(g, out, num) result(err) &
            bind(C, name="curandGenerateUniformDouble")
            import :: c_int, c_ptr, c_size_t
            type(c_ptr), value :: g, out
            integer(c_size_t), value :: num
            integer(c_int) :: err
        end function
    end interface
    integer(c_int), parameter :: CURAND_RNG_PSEUDO_PHILOX4_32_10 = 161

    integer(int64), parameter :: n = 2_int64**28
    integer, parameter :: runs = 21
    character(48), parameter :: labels(8) = [character(48) :: &
        "tandem_device_fill_real64", "tandem_device_fill_real32", &
        "tandem_device_fill_int64", "tandem_device_fill_int32", &
        "curandGenerateUniformDouble real64", "curandGenerateUniform real32", &
        "curandGenerate int64 (as int32 words)", "curandGenerate int32"]
    integer(int64), parameter :: sizes(8) = [8, 4, 8, 4, 8, 4, 8, 4]
    type(tandem_t) :: rng
    type(c_ptr) :: x, e0, e1, default_stream, g
    real(c_float) :: ms
    real(real64) :: best
    integer(int64) :: t0, t1, rate
    integer :: which, r

    x = tandem_device_alloc(8 * n)
    rng = tandem_new(42_int64)
    default_stream = transfer(0_int64, default_stream)
    call ok(cuda_event_create(e0))
    call ok(cuda_event_create(e1))
    call ok(curand_create_generator(g, CURAND_RNG_PSEUDO_PHILOX4_32_10))
    call ok(curand_set_seed(g, 42_c_long_long))

    call system_clock(t0, rate)
    t1 = t0
    do while (t1 - t0 < rate / 2)
        call tandem_device_fill_real64(rng, x, n)
        call tandem_device_synchronize()
        call system_clock(t1)
    end do

    print '("n = 2^28 elements, minimum of ", i0, " runs")', runs
    do which = 1, size(labels)
        best = huge(best)
        do r = 1, runs
            call ok(cuda_event_record(e0, default_stream))
            select case (which)
            case (1)
                call tandem_device_fill_real64(rng, x, n)
            case (2)
                call tandem_device_fill_real32(rng, x, n)
            case (3)
                call tandem_device_fill_int64(rng, x, n)
            case (4)
                call tandem_device_fill_int32(rng, x, n)
            case (5)
                call ok(curand_generate_uniform_double(g, x, int(n, c_size_t)))
            case (6)
                call ok(curand_generate_uniform(g, x, int(n, c_size_t)))
            case (7)
                call ok(curand_generate(g, x, int(2 * n, c_size_t)))
            case (8)
                call ok(curand_generate(g, x, int(n, c_size_t)))
            end select
            call ok(cuda_event_record(e1, default_stream))
            call ok(cuda_event_synchronize(e1))
            call ok(cuda_event_elapsed_time(ms, e0, e1))
            best = min(best, real(ms, real64) / 1000)
        end do
        print '(a40, f10.1, " GiB/s")', labels(which), &
            real(n * sizes(which), real64) / best / 2.0_real64**30
    end do
    call tandem_device_free(x)

contains

    subroutine ok(err)
        integer(c_int), intent(in) :: err
        if (err /= 0) error stop "CUDA event or cuRAND call failed"
    end subroutine

end program bench_cuda
