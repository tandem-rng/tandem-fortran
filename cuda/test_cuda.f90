! Device fills against the spec vectors, the conformance fixtures, the reference stream dumps,
! and CPU fills of the same generator state at many chunk lengths, start positions, lengths and
! output offsets.
program test_cuda
    use, intrinsic :: iso_c_binding, only: c_bool, c_loc, c_ptr
    use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
    use tandem_rng
    use tandem_rng_cuda
    use tandem_vectors
    use tandem_conformance
    implicit none

    integer(int64), parameter :: capacity = 2_int64**21 ! bytes
    integer(int32), parameter :: KEY1234(4) = [1, 2, 3, 4]
    integer(int64), parameter :: MASK32 = 4294967295_int64
    integer :: failures = 0, checks = 0
    type(c_ptr) :: dev

    dev = tandem_device_alloc(capacity)
    call vectors()
    call dumps()
    call against_cpu()
    call small_types_against_cpu()
    call bounded_against_cpu()
    call normals_against_cpu()
    call exponentials_against_cpu()
    call choice_against_cpu()
    call conformance_cases()
    call stream_hashes()
    call dump_hashes()
    call bounded_cut()
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

    function gpu_exponential64(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        real(real64), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_exponential_real64(rng, offset(dev, off), n)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 8 * n)
    end function

    function gpu_exponential32(rng, n, off) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        real(real32), allocatable, target :: x(:)
        allocate (x(n))
        call tandem_device_fill_exponential_real32(rng, offset(dev, off), n)
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
    subroutine bounded_against_cpu()
        integer(int32), parameter :: bounds32(5) = [1, 6, 1000, -1073741823, -1]
        integer(int64), parameter :: bounds64(5) = [1_int64, 3_int64, 1000000000000_int64, &
            -4611686018427387903_int64, -1_int64]
        ! The last start is bit 2^63 + 77, where a signed draw index would turn negative.
        integer(int64), parameter :: starts(4) = [integer(int64) :: 0, 5, 2_int64**40 + 77, &
            -huge(1_int64) + 76]
        integer(int64), parameter :: lengths(3) = [integer(int64) :: 0, 1001, 60000]
        type(tandem_t) :: base, cpu, gpu
        integer(int32), allocatable :: c32(:)
        integer(int64), allocatable :: c64(:)
        integer :: a, b, c, d
        integer(int64) :: n
        character(80) :: what

        do a = 1, size(bounds32)
            base = tandem_new(int(a, int64), 3_int64)
            do b = 1, size(starts)
                ! set_position refuses a start past 2^63, so build the generator there.
                base = tandem_from_key(base%key(), starts(b), base%chunk_length())
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

    ! Doubles are bit for bit, since the device runs the host's ziggurat, with one kernel below
    ! 2^16 elements and a second one for the misses above. Floats use the device's fast sine and
    ! cosine and match to 16 ulps, with an absolute floor near their zeros. A float fill is the
    ! flattened Box-Muller pairs, and odd lengths drop the last sin half.
    subroutine normals_against_cpu()
        integer(int32), parameter :: ks(3) = [1, 8, 32]
        integer(int64), parameter :: starts(3) = [integer(int64) :: 0, 3, 999]
        integer(int64), parameter :: lengths(5) = [integer(int64) :: 0, 7, 1001, 60000, 200001]
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
                    call check(all(transfer(y64, 0_int64, n) == transfer(x64, 0_int64, n)) .and. &
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

    ! Exponentials are bit exact on the device. The offsets put the output on and off the
    ! 16-byte alignment of the stream, which selects the vector or the element stores.
    subroutine exponentials_against_cpu()
        integer(int32), parameter :: ks(3) = [1, 8, 32]
        integer(int64), parameter :: starts(3) = [integer(int64) :: 0, 3, 999]
        integer(int64), parameter :: lengths(5) = [integer(int64) :: 0, 7, 1001, 60000, 200001]
        integer(int64), parameter :: offs(2) = [integer(int64) :: 0, 8]
        type(tandem_t) :: base, cpu, gpu
        real(real64), allocatable :: x64(:), y64(:)
        real(real32), allocatable :: x32(:), y32(:)
        integer :: a, b, c, d
        integer(int64) :: n
        character(80) :: what

        do a = 1, size(ks)
            base = tandem_new(int(a, int64), 13_int64, ks(a))
            do b = 1, size(starts)
                call base%set_position(starts(b))
                do c = 1, size(lengths)
                    do d = 1, size(offs)
                        n = lengths(c)
                        write (what, '("K=", i0, " start=", i0, " n=", i0, " off=", i0)') &
                            ks(a), starts(b), n, offs(d)
                        allocate (x64(n), x32(n))
                        cpu = base
                        gpu = base
                        call cpu%fill_exponential(x64)
                        y64 = gpu_exponential64(gpu, n, offs(d))
                        call check(all(transfer(y64, 0_int64, n) == transfer(x64, 0_int64, n)) &
                            .and. cpu%position() == gpu%position(), "exponential real64 "//trim(what))
                        cpu = base
                        gpu = base
                        call cpu%fill_exponential(x32)
                        y32 = gpu_exponential32(gpu, n, offs(d) / 2)
                        call check(all(transfer(y32, 0_int32, n) == transfer(x32, 0_int32, n)) &
                            .and. cpu%position() == gpu%position(), "exponential real32 "//trim(what))
                        deallocate (x64, x32)
                    end do
                end do
            end do
        end do
    end subroutine

    ! A bounded device fill cut at an arbitrary element boundary equals the whole fill, rejected
    ! draws included: the fallback of a rejected draw is keyed by its global draw index. The
    ! second part lands right after the first in device memory.
    subroutine bounded_cut()
        integer(int64), parameter :: n = 1000
        integer(int64), parameter :: cuts(3) = [1_int64, 337_int64, 999_int64]
        type(tandem_t) :: base, whole, part
        integer(int32), allocatable :: w32(:), p32(:)
        integer(int64), allocatable :: w64(:), p64(:)
        integer :: j
        integer(int64) :: m
        base = tandem_new(8_int64, 2_int64)
        call base%set_position(5_int64)
        do j = 1, size(cuts)
            m = cuts(j)
            whole = base
            part = base
            w32 = gpu_below32(whole, n, 0_int64, -1073741823_int32)
            p32 = [gpu_below32(part, m, 0_int64, -1073741823_int32), &
                gpu_below32(part, n - m, 0_int64, -1073741823_int32)]
            call check(all(w32 == p32) .and. whole%position() == part%position(), "device below int32 cut")
            whole = base
            part = base
            w64 = gpu_below64(whole, n, 0_int64, -4611686018427387903_int64)
            p64 = [gpu_below64(part, m, 0_int64, -4611686018427387903_int64), &
                gpu_below64(part, n - m, 0_int64, -4611686018427387903_int64)]
            call check(all(w64 == p64) .and. whole%position() == part%position(), "device below int64 cut")
        end do
    end subroutine

    ! Element i maps 64-bit draw i, so the device fill equals the host fill at any K, start and
    ! length, end position included. The weights hold a zero and a subnormal.
    subroutine choice_against_cpu()
        integer(int32), parameter :: ks(3) = [1, 8, 256]
        integer(int64), parameter :: starts(3) = [integer(int64) :: 0, 3, 2_int64**40 + 77]
        integer(int64), parameter :: lengths(4) = [integer(int64) :: 0, 1, 1001, 60000]
        type(tandem_t) :: base, cpu, gpu
        type(tandem_choice_t) :: t
        integer(int32), allocatable :: want(:), got(:)
        integer :: a, b, c
        integer(int64) :: n
        character(80) :: what
        call t%build([3.0_real64, 0.0_real64, 1.0_real64, 5e-324_real64, 0.25_real64, 7.0_real64])
        do a = 1, size(ks)
            base = tandem_new(int(a, int64), 5_int64, ks(a))
            do b = 1, size(starts)
                call base%set_position(starts(b))
                do c = 1, size(lengths)
                    n = lengths(c)
                    write (what, '(" K=", i0, " start=", i0, " n=", i0)') ks(a), starts(b), n
                    allocate (want(n))
                    cpu = base
                    gpu = base
                    call cpu%fill_choice(want, t)
                    got = gpu_choice(gpu, n, 4_int64, t)
                    call check(all(got == want) .and. cpu%position() == gpu%position(), "choice"//trim(what))
                    deallocate (want)
                end do
            end do
        end do
    end subroutine

    ! m elements of the device fill of case c on g at dev + off, as unsigned bit patterns.
    function gpu_case(c, g, m, off) result(bits)
        type(conformance_case), intent(in) :: c
        type(tandem_t), intent(inout) :: g
        integer(int64), intent(in) :: m, off
        integer(int64) :: bits(m)
        select case (c%kind)
        case ("fill_below_u32")
            bits = iand(int(gpu_below32(g, m, off, as_int32(c%range)), int64), MASK32)
        case ("fill_below_u64")
            bits = gpu_below64(g, m, off, c%range)
        case ("fill_normal_f64")
            bits = transfer(gpu_normal64(g, m, off), 0_int64, m)
        case ("fill_normal_f32")
            bits = iand(int(transfer(gpu_normal32(g, m, off), 0_int32, m), int64), MASK32)
        case ("fill_exponential_f64")
            bits = transfer(gpu_exponential64(g, m, off), 0_int64, m)
        case ("fill_exponential_f32")
            bits = iand(int(transfer(gpu_exponential32(g, m, off), 0_int32, m), int64), MASK32)
        case ("fill_choice")
            bits = int(gpu_choice(g, m, off, table_of(c)), int64)
        case default
            error stop "test_cuda: unknown kind "//c%kind
        end select
    end function

    function table_of(c) result(t)
        type(conformance_case), intent(in) :: c
        type(tandem_choice_t) :: t
        call t%build(transfer(c%weights, 0.0_real64, size(c%weights)))
    end function

    function gpu_choice(rng, n, off, table) result(x)
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(in) :: n, off
        type(tandem_choice_t), intent(in) :: table
        integer(int32), allocatable, target :: x(:)
        type(tandem_device_choice_t) :: d
        allocate (x(n))
        call tandem_device_choice_upload(table, d)
        call tandem_device_fill_choice(rng, offset(dev, off), n, d)
        if (n > 0) call tandem_copy_to_host(c_loc(x), offset(dev, off), 4 * n)
        call tandem_device_choice_free(d)
    end function

    ! Bit for bit, except where the fixture gives a tolerance: 16 ulps and an absolute floor.
    logical function agrees(c, bits)
        type(conformance_case), intent(in) :: c
        integer(int64), intent(in) :: bits(:)
        real(real32) :: x(size(bits)), y(size(bits))
        if (.not. c%tol) then
            agrees = all(bits == c%values)
            return
        end if
        x = transfer(as_int32(c%values), 0.0_real32, size(bits))
        y = transfer(as_int32(bits), 0.0_real32, size(bits))
        agrees = all(abs(y - x) <= 16 * epsilon(1.0_real32) * abs(x) + 1e-6_real32)
    end function

    ! The end the source pins, or for a Float32 normal fill align(start, 32) + 64 ceil(n / 2).
    function end_of(c) result(e)
        type(conformance_case), intent(in) :: c
        integer(int64) :: e
        e = c%end
        if (e < 0 .and. c%kind == "fill_normal_f32") &
            e = (c%start + 31) / 32 * 32 + 64 * ((c%n + 1) / 2)
    end function

    ! Every case of fill_below, normal, exponential and choice.json on the device, whole and cut at
    ! elements 1, 7, 20, 21 and n - 1, the second piece right after the first in device memory.
    ! A Float32 normal fill is cut between pairs only.
    subroutine conformance_cases()
        type(conformance_case), allocatable :: cases(:)
        character(16), parameter :: files(4) = [character(16) :: "fill_below.json", &
            "normal.json", "exponential.json", "choice.json"]
        type(tandem_t) :: g
        integer(int64), allocatable :: got(:)
        integer(int64) :: cut(5), m, n, width
        integer :: f, i, j
        do f = 1, size(files)
            cases = read_cases(trim(files(f)))
            do i = 1, size(cases)
                associate (c => cases(i))
                    n = c%n
                    width = 8
                    if (index(c%kind, "32") > 0 .or. c%kind == "fill_choice") width = 4
                    g = tandem_from_key(c%key, c%start, c%K)
                    got = gpu_case(c, g, n, 0_int64)
                    call check(agrees(c, got), "device "//c%id//": values")
                    if (end_of(c) >= 0) call check(g%position() == end_of(c), "device "//c%id//": end")
                    cut = [1_int64, 7_int64, 20_int64, 21_int64, n - 1]
                    do j = 1, size(cut)
                        m = cut(j)
                        if (m < 1 .or. m >= n .or. (c%kind == "fill_normal_f32" .and. mod(m, 2_int64) == 1)) cycle
                        g = tandem_from_key(c%key, c%start, c%K)
                        got(:m) = gpu_case(c, g, m, 0_int64)
                        got(m + 1:) = gpu_case(c, g, n - m, width * m)
                        call check(agrees(c, got), "device "//c%id//": cut fill values")
                        if (end_of(c) >= 0) call check(g%position() == end_of(c), &
                            "device "//c%id//": cut fill end")
                    end do
                end associate
            end do
        end do
    end subroutine

    ! The SHA-256 of hashes.json for each stream type the device fills.
    subroutine stream_hashes()
        type(stream_case), allocatable :: s(:)
        type(tandem_t) :: g
        integer(int8), allocatable :: bytes(:)
        integer(int64) :: n
        integer :: i, done
        s = read_streams()
        done = 0
        do i = 1, size(s)
            g = tandem_from_key(s(i)%key, s(i)%start, s(i)%K)
            n = s(i)%n
            select case (s(i)%type)
            case ("UInt32")
                bytes = transfer(gpu_int32(g, n, 0_int64), bytes)
            case ("UInt64")
                bytes = transfer(gpu_int64(g, n, 0_int64), bytes)
            case ("UInt8")
                bytes = gpu_int8(g, n, 0_int64)
            case ("Bool")
                bytes = transfer(gpu_logical(g, n, 0_int64), bytes)
            case ("Float16")
                bytes = transfer(gpu_real16_bits(g, n, 0_int64), bytes)
            case ("Float32")
                bytes = transfer(gpu_real32(g, n, 0_int64), bytes)
            case ("Float64")
                bytes = transfer(gpu_real64(g, n, 0_int64), bytes)
            case ("ComplexF32")
                bytes = transfer(gpu_complex32(g, n, 0_int64), bytes)
            case ("ComplexF64")
                bytes = transfer(gpu_complex64(g, n, 0_int64), bytes)
            case default
                cycle
            end select
            done = done + 1
            call check(sha256_hex(bytes) == s(i)%sha256, "device "//s(i)%file//": sha256")
        end do
        call check(done == 10, "device fills ten of the twelve streams")
    end subroutine

    ! FNV-1a of the long Float64 normal and the exponential outputs, filled in pieces of 2^18
    ! elements on one generator. Device Float32 normals take the device's log and cos, so their
    ! hash, which holds for the C polynomials only, does not apply.
    subroutine dump_hashes()
        integer(int64), parameter :: PIECE = 2_int64**18
        type(dump_case), allocatable :: d(:)
        type(tandem_t) :: g
        integer(int64) :: h(2), m, left
        integer :: i, j, k
        d = read_dumps()
        do i = 1, size(d)
            if (any(d(i)%draws == "fill_normal_f32")) cycle
            h = fnv1a_init()
            do j = 1, size(d(i)%starts)
                g = tandem_from_key(d(i)%key, d(i)%starts(j), d(i)%K)
                do k = 1, size(d(i)%draws)
                    left = d(i)%counts(k)
                    do while (left > 0)
                        m = min(PIECE, left)
                        select case (d(i)%draws(k))
                        case ("fill_normal_f64")
                            call fnv1a_update(h, transfer(gpu_normal64(g, m, 0_int64), [0_int8], 8 * m))
                        case ("fill_exponential_f64")
                            call fnv1a_update(h, transfer(gpu_exponential64(g, m, 0_int64), [0_int8], 8 * m))
                        case default
                            call fnv1a_update(h, transfer(gpu_exponential32(g, m, 0_int64), [0_int8], 4 * m))
                        end select
                        left = left - m
                    end do
                end do
            end do
            call check(fnv1a_digest(h) == d(i)%fnv1a, "device "//d(i)%id//": fnv1a")
            if (d(i)%end >= 0) call check(g%position() == d(i)%end, "device "//d(i)%id//": end")
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
