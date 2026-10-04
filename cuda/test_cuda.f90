! Device fills against the spec vectors, the reference stream dumps, and CPU fills of the same
! generator state at many chunk lengths, start positions, lengths and output offsets.
program test_cuda
    use, intrinsic :: iso_c_binding, only: c_bool, c_loc, c_ptr
    use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
    use tandem_rng
    use tandem_rng_cuda
    use tandem_vectors
    use tandem_cross
    implicit none

    integer(int64), parameter :: capacity = 2_int64**21 ! bytes
    integer(int32), parameter :: KEY1234(4) = [1, 2, 3, 4]
    integer :: failures = 0, checks = 0
    type(c_ptr) :: dev

    dev = tandem_device_alloc(capacity)
    call vectors()
    call dumps()
    call against_cpu()
    call small_types_against_cpu()
    call bounded_against_cpu()
    call normals_against_cpu()
    call device_fixtures()
    call interleave()
    call tandem_device_free(dev)

    if (failures > 0) then
        print '(i0, " of ", i0, " checks failed")', failures, checks
        error stop 1
    end if
    print '("cuda: ", i0, " checks ok")', checks

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

    function offset(p, nbytes) result(q)
        type(c_ptr), intent(in) :: p
        integer(int64), intent(in) :: nbytes
        type(c_ptr) :: q
        q = transfer(transfer(p, 0_int64) + nbytes, p)
    end function

    ! Device fills of each type into dev + off, copied back to the host.
    function gpu_int32(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int32), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_int32(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 4 * n)
    end function

    function gpu_int64(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int64), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_int64(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 8 * n)
    end function

    function gpu_real32(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        real(real32), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_real32(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 4 * n)
    end function

    function gpu_real64(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        real(real64), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_real64(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 8 * n)
    end function

    function gpu_int16(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int16), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_int16(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 2 * n)
    end function

    function gpu_int8(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int8), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_int8(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), n)
    end function

    function gpu_logical(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        logical(c_bool), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_logical(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), n)
    end function

    function gpu_real16_bits(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int16), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_real16_bits(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 2 * n)
    end function

    function gpu_complex64(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        complex(real64), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_complex64(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 16 * n)
    end function

    function gpu_complex32(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        complex(real32), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_complex32(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 8 * n)
    end function

    function gpu_below32(rng, n, off, bound) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int32), intent(in) :: bound
        integer(int32), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_below_int32(rng, offset(dev, off), n, bound)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 4 * n)
    end function

    function gpu_below64(rng, n, off, bound) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        integer(int64), intent(in) :: bound
        integer(int64), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_below_int64(rng, offset(dev, off), n, bound)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 8 * n)
    end function

    function gpu_normal64(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        real(real64), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_normal_real64(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 8 * n)
    end function

    function gpu_normal32(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        real(real32), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_normal_real32(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 4 * n)
    end function

    function dump(name) result(bytes)
        character(*), intent(in) :: name
        integer(int8), allocatable :: bytes(:)
        integer :: u
        integer(int64) :: n
        open (newunit=u, file="test/data/"//name, access="stream", form="unformatted", &
            status="old", action="read")
        inquire (unit=u, size=n)
        allocate (bytes(n))
        read (u) bytes
        close (u)
    end function

    subroutine vectors()
        type(tandem_t) :: rng
        integer(int32), allocatable :: w(:)
        real(real64), allocatable :: x(:)
        real(real32), allocatable :: f(:)
        integer :: i
        integer(int64) :: w0

        rng = tandem_from_key(VEC_KEY, 0_int64, VEC_K)
        w = gpu_int32(rng, 64_int64, 0_int64)
        do i = 1, size(VEC_STREAM)
            w0 = VEC_STREAM(i)%first_word
            call check(all(w(w0 + 1:w0 + 4) == VEC_STREAM(i)%words), "vector stream words")
        end do
        call check(rng%position() == 64 * 32, "vector fill position")

        rng = tandem_from_key(VEC_KEY, 0_int64, VEC_K)
        x = gpu_real64(rng, 32_int64, 0_int64)
        do i = 1, size(VEC_REAL64)
            call check(transfer(x(VEC_REAL64(i)%index + 1), 0_int64) == &
                transfer(VEC_REAL64(i)%value, 0_int64), "vector real64")
        end do
        rng = tandem_from_key(VEC_KEY, 0_int64, VEC_K)
        f = gpu_real32(rng, 32_int64, 0_int64)
        do i = 1, size(VEC_REAL32)
            call check(transfer(f(VEC_REAL32(i)%index + 1), 0_int32) == &
                transfer(VEC_REAL32(i)%value, 0_int32), "vector real32")
        end do

        rng = tandem_new(VEC_SEED)
        x = gpu_real64(rng, 32_int64, 0_int64)
        do i = 1, size(VEC_SEED_REAL64)
            call check(transfer(x(VEC_SEED_REAL64(i)%index + 1), 0_int64) == &
                transfer(VEC_SEED_REAL64(i)%value, 0_int64), "vector seed real64")
        end do
        rng = tandem_new(VEC_SEED)
        w = gpu_int32(rng, 32_int64, 0_int64)
        do i = 1, size(VEC_SEED_INT32)
            call check(w(VEC_SEED_INT32(i)%index + 1) == VEC_SEED_INT32(i)%value, &
                "vector seed int32")
        end do
    end subroutine

    subroutine dumps()
        type(tandem_t) :: rng
        integer(int32), allocatable :: w32(:)
        integer(int64), allocatable :: w64(:)

        w32 = transfer(dump("k1234_K32_u32.bin"), 0_int32, size(dump("k1234_K32_u32.bin")) / 4)
        rng = tandem_from_key(KEY1234, K=32)
        call check(all(gpu_int32(rng, size(w32, kind=int64), 0_int64) == w32), "k1234_K32_u32")
        w32 = transfer(dump("k1234_K8_u32.bin"), 0_int32, size(dump("k1234_K8_u32.bin")) / 4)
        rng = tandem_from_key(KEY1234, K=8)
        call check(all(gpu_int32(rng, size(w32, kind=int64), 0_int64) == w32), "k1234_K8_u32")
        w64 = transfer(dump("k1234_K32_u64.bin"), 0_int64, size(dump("k1234_K32_u64.bin")) / 8)
        rng = tandem_from_key(KEY1234, K=32)
        call check(all(gpu_int64(rng, size(w64, kind=int64), 0_int64) == w64), "k1234_K32_u64")
        w64 = transfer(dump("seed42_K32_f64.bin"), 0_int64, size(dump("seed42_K32_f64.bin")) / 8)
        rng = tandem_new(42_int64)
        call check(all(transfer(gpu_real64(rng, size(w64, kind=int64), 0_int64), 0_int64, &
            size(w64)) == w64), "seed42_K32_f64")
        w32 = transfer(dump("seed42_K32_f32.bin"), 0_int32, size(dump("seed42_K32_f32.bin")) / 4)
        rng = tandem_new(42_int64)
        call check(all(transfer(gpu_real32(rng, size(w32, kind=int64), 0_int64), 0_int32, &
            size(w32)) == w32), "seed42_K32_f32")
    end subroutine

    ! Both kernels (K < 8 and K >= 8), starts inside a row and off alignment, short and long
    ! fills, and outputs at every 4-byte offset of a 16-byte vector.
    subroutine against_cpu()
        integer(int32), parameter :: ks(6) = [1, 2, 4, 8, 32, 256]
        integer(int64), parameter :: starts(6) = [integer(int64) :: 0, 1, 40, 999, 1024 * 37 + 5, &
            2_int64**40 + 77]
        integer(int64), parameter :: lengths(5) = [integer(int64) :: 0, 1, 7, 1001, 60000]
        integer(int64), parameter :: offs(4) = [integer(int64) :: 0, 4, 8, 12]
        type(tandem_t) :: base, cpu, gpu
        integer(int32), allocatable :: c32(:), g32(:)
        integer(int64), allocatable :: c64(:), g64(:)
        real(real32), allocatable :: f32(:), h32(:)
        real(real64), allocatable :: f64(:), h64(:)
        integer :: a, b, c, d
        integer(int64) :: n, off
        character(80) :: what

        do a = 1, size(ks)
            base = tandem_new(int(a, int64), 99_int64, ks(a))
            do b = 1, size(starts)
                call base%set_position(starts(b))
                do c = 1, size(lengths)
                    n = lengths(c)
                    do d = 1, size(offs)
                        off = offs(d)
                        write (what, '("K=", i0, " start=", i0, " n=", i0, " offset=", i0)') &
                            ks(a), starts(b), n, off
                        allocate (c32(n), c64(n), f32(n), f64(n))

                        cpu = base
                        gpu = base
                        call cpu%fill(c32)
                        g32 = gpu_int32(gpu, n, off)
                        call check(all(g32 == c32) .and. cpu%position() == gpu%position(), &
                            "int32 "//trim(what))
                        cpu = base
                        gpu = base
                        call cpu%fill(f32)
                        h32 = gpu_real32(gpu, n, off)
                        call check(all(transfer(h32, 0_int32, n) == transfer(f32, 0_int32, n)) &
                            .and. cpu%position() == gpu%position(), "real32 "//trim(what))
                        if (mod(off, 8_int64) == 0) then
                            cpu = base
                            gpu = base
                            call cpu%fill(c64)
                            g64 = gpu_int64(gpu, n, off)
                            call check(all(g64 == c64) .and. cpu%position() == gpu%position(), &
                                "int64 "//trim(what))
                            cpu = base
                            gpu = base
                            call cpu%fill(f64)
                            h64 = gpu_real64(gpu, n, off)
                            call check(all(transfer(h64, 0_int64, n) == transfer(f64, 0_int64, n)) &
                                .and. cpu%position() == gpu%position(), "real64 "//trim(what))
                        end if
                        deallocate (c32, c64, f32, f64)
                    end do
                end do
            end do
        end do
    end subroutine

    ! The narrow types store 1 to 4 bytes per element, so they run at every output offset the
    ! element size allows, with the same chunk lengths, starts and lengths as above. Complex
    ! elements are pairs of reals, and the bit comparison covers both parts.
    subroutine small_types_against_cpu()
        integer(int32), parameter :: ks(3) = [1, 8, 32]
        integer(int64), parameter :: starts(4) = [integer(int64) :: 0, 3, 999, 2_int64**40 + 77]
        integer(int64), parameter :: lengths(4) = [integer(int64) :: 0, 7, 1001, 60000]
        integer(int64), parameter :: offs(5) = [integer(int64) :: 0, 1, 2, 3, 8]
        type(tandem_t) :: base, cpu, gpu
        integer(int16), allocatable :: c16(:), f16(:)
        integer(int8), allocatable :: c8(:)
        logical(c_bool), allocatable :: cb(:), gb(:)
        complex(real64), allocatable :: z64(:), w64(:)
        complex(real32), allocatable :: z32(:), w32(:)
        integer :: a, b, c, d
        integer(int64) :: n, off
        character(80) :: what

        do a = 1, size(ks)
            base = tandem_new(int(a, int64), 7_int64, ks(a))
            do b = 1, size(starts)
                call base%set_position(starts(b))
                do c = 1, size(lengths)
                    n = lengths(c)
                    do d = 1, size(offs)
                        off = offs(d)
                        write (what, '("K=", i0, " start=", i0, " n=", i0, " offset=", i0)') &
                            ks(a), starts(b), n, off
                        if (mod(off, 2_int64) == 0) then
                            allocate (c16(n))
                            cpu = base
                            gpu = base
                            call cpu%fill(c16)
                            f16 = gpu_int16(gpu, n, off)
                            call check(all(f16 == c16) .and. cpu%position() == gpu%position(), &
                                "int16 "//trim(what))
                            cpu = base
                            gpu = base
                            call cpu%fill_real16_bits(c16)
                            f16 = gpu_real16_bits(gpu, n, off)
                            call check(all(f16 == c16) .and. cpu%position() == gpu%position(), &
                                "real16 bits "//trim(what))
                            deallocate (c16)
                        end if
                        allocate (c8(n), cb(n))
                        cpu = base
                        gpu = base
                        call cpu%fill(c8)
                        call check(all(gpu_int8(gpu, n, off) == c8) .and. &
                            cpu%position() == gpu%position(), "int8 "//trim(what))
                        cpu = base
                        gpu = base
                        call cpu%fill(cb)
                        gb = gpu_logical(gpu, n, off)
                        call check(all(transfer(gb, 0_int8, n) == transfer(cb, 0_int8, n)) .and. &
                            cpu%position() == gpu%position(), "logical "//trim(what))
                        deallocate (c8, cb)
                        if (mod(off, 8_int64) == 0) then
                            allocate (z64(n), z32(n))
                            cpu = base
                            gpu = base
                            call cpu%fill(z64)
                            w64 = gpu_complex64(gpu, n, off)
                            call check(all(transfer(w64, 0_int64, 2 * n) == &
                                transfer(z64, 0_int64, 2 * n)) .and. &
                                cpu%position() == gpu%position(), "complex64 "//trim(what))
                            cpu = base
                            gpu = base
                            call cpu%fill(z32)
                            w32 = gpu_complex32(gpu, n, off)
                            call check(all(transfer(w32, 0_int32, 2 * n) == &
                                transfer(z32, 0_int32, 2 * n)) .and. &
                                cpu%position() == gpu%position(), "complex32 "//trim(what))
                            deallocate (z64, z32)
                        end if
                    end do
                end do
            end do
        end do
    end subroutine

    ! The device fill is the host fill, rejected draws included: same values, same position.
    ! The fixtures of tandem-c's cross_fill_below.h pin the host side to core.hpp.
    subroutine bounded_against_cpu()
        integer(int32), parameter :: bounds32(5) = [1, 6, 1000, -1073741823, -1]
        integer(int64), parameter :: bounds64(5) = [1_int64, 3_int64, 1000000000000_int64, &
            -4611686018427387903_int64, -1_int64]
        integer(int64), parameter :: starts(3) = [integer(int64) :: 0, 5, 2_int64**40 + 77]
        integer(int64), parameter :: lengths(3) = [integer(int64) :: 0, 1001, 60000]
        type(tandem_t) :: base, cpu, gpu
        integer(int32), allocatable :: c32(:)
        integer(int64), allocatable :: c64(:)
        integer(int32) :: g32(CROSS_COUNT)
        integer(int64) :: g64(CROSS_COUNT)
        integer :: a, b, c, d
        integer(int64) :: n
        logical :: skip
        character(80) :: what

        do a = 1, size(CROSS_FILL_BELOW32_N)
            gpu = tandem_new(42_int64)
            skip = gpu%next_logical()
            g32 = gpu_below32(gpu, int(CROSS_COUNT, int64), 0_int64, CROSS_FILL_BELOW32_N(a))
            call check(all(g32 == CROSS_FILL_BELOW32_WANT(:, a)) .and. &
                gpu%position() == CROSS_FILL_BELOW32_END(a), "below int32 fixture")
        end do
        do a = 1, size(CROSS_FILL_BELOW64_N)
            gpu = tandem_new(42_int64)
            skip = gpu%next_logical()
            g64 = gpu_below64(gpu, int(CROSS_COUNT, int64), 0_int64, CROSS_FILL_BELOW64_N(a))
            call check(all(g64 == CROSS_FILL_BELOW64_WANT(:, a)) .and. &
                gpu%position() == CROSS_FILL_BELOW64_END(a), "below int64 fixture")
        end do

        do a = 1, size(bounds32)
            base = tandem_new(int(a, int64), 3_int64)
            do b = 1, size(starts)
                call base%set_position(starts(b))
                do c = 1, size(lengths)
                    n = lengths(c)
                    do d = 0, 4, 4
                        write (what, '("bound=", i0, " start=", i0, " n=", i0, " offset=", i0)') &
                            bounds32(a), starts(b), n, d
                        allocate (c32(n), c64(n))
                        cpu = base
                        gpu = base
                        call cpu%fill_below(c32, bounds32(a))
                        call check(all(gpu_below32(gpu, n, int(d, int64), bounds32(a)) == c32) .and. &
                            cpu%position() == gpu%position(), "below int32 "//trim(what))
                        write (what, '("bound=", i0, " start=", i0, " n=", i0, " offset=", i0)') &
                            bounds64(a), starts(b), n, 8 * (d / 4)
                        cpu = base
                        gpu = base
                        call cpu%fill_below(c64, bounds64(a))
                        call check(all(gpu_below64(gpu, n, int(8 * (d / 4), int64), bounds64(a)) == &
                            c64) .and. cpu%position() == gpu%position(), "below int64 "//trim(what))
                        deallocate (c32, c64)
                    end do
                end do
            end do
        end do
    end subroutine

    ! Device log, cos and sin differ from the host's in the last bits, so values match to 1e-12
    ! relative for doubles and 16 ulps for floats, with an absolute floor near the zeros of cos
    ! and sin. A fill is the flattened Box-Muller pairs, and odd lengths drop the last sin half.
    ! Positions are exact: the draws consumed do not depend on the libm.
    subroutine normals_against_cpu()
        integer(int32), parameter :: ks(3) = [1, 8, 32]
        integer(int64), parameter :: starts(3) = [integer(int64) :: 0, 3, 999]
        integer(int64), parameter :: lengths(4) = [integer(int64) :: 0, 7, 1001, 60000]
        type(tandem_t) :: base, cpu, gpu
        real(real64), allocatable :: x64(:), y64(:)
        real(real32), allocatable :: x32(:), y32(:)
        integer :: a, b, c
        integer(int64) :: n
        character(80) :: what

        do a = 1, size(ks)
            base = tandem_new(int(a, int64), 11_int64, ks(a))
            do b = 1, size(starts)
                call base%set_position(starts(b))
                do c = 1, size(lengths)
                    n = lengths(c)
                    write (what, '("K=", i0, " start=", i0, " n=", i0)') ks(a), starts(b), n
                    allocate (x64(n), x32(n))
                    cpu = base
                    gpu = base
                    call cpu%fill_normal(x64)
                    y64 = gpu_normal64(gpu, n, 0_int64)
                    call check(all(abs(y64 - x64) <= 1e-12_real64 * abs(x64) + 1e-14_real64) .and. &
                        cpu%position() == gpu%position(), "normal real64 "//trim(what))
                    cpu = base
                    gpu = base
                    call cpu%fill_normal(x32)
                    y32 = gpu_normal32(gpu, n, 0_int64)
                    call check(all(abs(y32 - x32) <= 16 * epsilon(1.0_real32) * abs(x32) + &
                        1e-6_real32) .and. cpu%position() == gpu%position(), &
                        "normal real32 "//trim(what))
                    deallocate (x64, x32)
                end do
            end do
        end do
    end subroutine

    ! The fills tandem-cuda derives on the device, from tandem-c's cuda_fill_*.h: bounded values
    ! are exact, normals match to 1e-12 relative (doubles) and 16 ulps (floats) with a floor.
    subroutine device_fixtures()
        type(tandem_t) :: gpu
        integer(int32) :: g32(64)
        integer(int64) :: g64(64)
        real(real64) :: z64(64)
        real(real32) :: z32(64)
        integer :: c, n
        do c = 1, size(CROSS_DEVICE_BELOW32_HEAD)
            gpu = tandem_from_key(CROSS_DEVICE_KEY, 0_int64, 32)
            g32 = gpu_below32(gpu, 64_int64, 0_int64, CROSS_DEVICE_BELOW32_HEAD(c))
            call check(all(g32 == CROSS_DEVICE_BELOW32_OUT(:, c)), "device fixture below int32")
        end do
        do c = 1, size(CROSS_DEVICE_BELOW64_HEAD)
            gpu = tandem_from_key(CROSS_DEVICE_KEY, 0_int64, 32)
            g64 = gpu_below64(gpu, 64_int64, 0_int64, CROSS_DEVICE_BELOW64_HEAD(c))
            call check(all(g64 == CROSS_DEVICE_BELOW64_OUT(:, c)), "device fixture below int64")
        end do
        do c = 1, size(CROSS_DEVICE_NORMAL64_HEAD)
            n = CROSS_DEVICE_NORMAL64_N(c)
            gpu = tandem_from_key(CROSS_DEVICE_KEY, CROSS_DEVICE_NORMAL64_HEAD(c), 32)
            z64(:n) = gpu_normal64(gpu, int(n, int64), 0_int64)
            call check(all(abs(z64(:n) - CROSS_DEVICE_NORMAL64_OUT(:n, c)) <= &
                1e-12_real64 * abs(CROSS_DEVICE_NORMAL64_OUT(:n, c))), "device fixture normal real64")
        end do
        do c = 1, size(CROSS_DEVICE_NORMAL32_HEAD)
            n = CROSS_DEVICE_NORMAL32_N(c)
            gpu = tandem_from_key(CROSS_DEVICE_KEY, CROSS_DEVICE_NORMAL32_HEAD(c), 32)
            z32(:n) = gpu_normal32(gpu, int(n, int64), 0_int64)
            call check(all(abs(z32(:n) - CROSS_DEVICE_NORMAL32_OUT(:n, c)) <= &
                16 * epsilon(1.0_real32) * abs(CROSS_DEVICE_NORMAL32_OUT(:n, c)) + 1e-6_real32), &
                "device fixture normal real32")
        end do
    end subroutine

    ! CPU draws and device fills share one stream.
    subroutine interleave()
        type(tandem_t) :: cpu, mixed
        real(real64), allocatable :: x(:), y(:)
        integer(int32), allocatable :: w(:), v(:)
        integer(int8) :: b1, b2
        integer(int64) :: d1, d2
        cpu = tandem_new(5_int64)
        mixed = cpu
        allocate (x(1000), w(10))
        b1 = cpu%next_int8()
        call cpu%fill(x)
        d1 = cpu%next_int64()
        call cpu%fill(w)
        b2 = mixed%next_int8()
        y = gpu_real64(mixed, 1000_int64, 0_int64)
        d2 = mixed%next_int64()
        v = gpu_int32(mixed, 10_int64, 0_int64)
        call check(b1 == b2 .and. d1 == d2 .and. all(transfer(x, 0_int64, 1000) == &
            transfer(y, 0_int64, 1000)) .and. all(w == v), "interleaved CPU draws and device fills")
        call check(cpu%position() == mixed%position(), "interleaved position")
        call check(transfer(cpu%next_real64(), 0_int64) == transfer(mixed%next_real64(), 0_int64), &
            "draw after interleaving")
    end subroutine

end program test_cuda
