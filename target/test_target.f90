! The OpenMP target and do concurrent fills against the CPU fills of the same generator, the
! reference stream dumps of test/data and the conformance fixtures, at many chunk lengths, start
! positions and lengths.
! variant 1 is the target fill and variant 2 the do concurrent fill.
program test_target
    use, intrinsic :: iso_fortran_env, only: int8, int32, int64, real32, real64
    use tandem_rng
    use tandem_rng_target
    use tandem_conformance
    implicit none

    integer :: failures = 0, checks = 0

    call dumps()
    call against_cpu()
    call bounded_against_cpu()
    call bounded_cut()
    call conformance_cases()
    call stream_hashes()

    if (failures > 0) then
        print '(i0, " of ", i0, " checks failed")', failures, checks
        error stop 1
    end if
    print '("target: ", i0, " checks ok")', checks

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

    subroutine fill32(v, rng, x)
        integer, intent(in) :: v
        type(tandem_t), intent(inout) :: rng
        integer(int32), intent(out) :: x(:)
        if (v == 1) then
            call tandem_fill_target(rng, x)
        else
            call tandem_fill_stdpar(rng, x)
        end if
    end subroutine

    subroutine fill64(v, rng, x)
        integer, intent(in) :: v
        type(tandem_t), intent(inout) :: rng
        integer(int64), intent(out) :: x(:)
        if (v == 1) then
            call tandem_fill_target(rng, x)
        else
            call tandem_fill_stdpar(rng, x)
        end if
    end subroutine

    subroutine fillf32(v, rng, x)
        integer, intent(in) :: v
        type(tandem_t), intent(inout) :: rng
        real(real32), intent(out) :: x(:)
        if (v == 1) then
            call tandem_fill_target(rng, x)
        else
            call tandem_fill_stdpar(rng, x)
        end if
    end subroutine

    subroutine fillf64(v, rng, x)
        integer, intent(in) :: v
        type(tandem_t), intent(inout) :: rng
        real(real64), intent(out) :: x(:)
        if (v == 1) then
            call tandem_fill_target(rng, x)
        else
            call tandem_fill_stdpar(rng, x)
        end if
    end subroutine

    subroutine dumps()
        type(tandem_t) :: rng
        integer(int32), allocatable :: w32(:), g32(:)
        integer(int64), allocatable :: w64(:), g64(:)
        real(real32), allocatable :: gf32(:)
        real(real64), allocatable :: gf64(:)
        integer :: v
        integer(int32), parameter :: KEY1234(4) = [1, 2, 3, 4]

        do v = 1, 2
            w32 = transfer(dump("k1234_K32_u32.bin"), 0_int32, size(dump("k1234_K32_u32.bin")) / 4)
            allocate (g32(size(w32)))
            rng = tandem_from_key(KEY1234, K=32)
            call fill32(v, rng, g32)
            call check(all(g32 == w32), "k1234_K32_u32")
            deallocate (g32)
            w32 = transfer(dump("k1234_K8_u32.bin"), 0_int32, size(dump("k1234_K8_u32.bin")) / 4)
            allocate (g32(size(w32)))
            rng = tandem_from_key(KEY1234, K=8)
            call fill32(v, rng, g32)
            call check(all(g32 == w32), "k1234_K8_u32")
            deallocate (g32)
            w64 = transfer(dump("k1234_K32_u64.bin"), 0_int64, size(dump("k1234_K32_u64.bin")) / 8)
            allocate (g64(size(w64)))
            rng = tandem_from_key(KEY1234, K=32)
            call fill64(v, rng, g64)
            call check(all(g64 == w64), "k1234_K32_u64")
            deallocate (g64)
            w64 = transfer(dump("seed42_K32_f64.bin"), 0_int64, size(dump("seed42_K32_f64.bin")) / 8)
            allocate (gf64(size(w64)))
            rng = tandem_new(42_int64)
            call fillf64(v, rng, gf64)
            call check(all(transfer(gf64, 0_int64, size(w64)) == w64), "seed42_K32_f64")
            deallocate (gf64)
            w32 = transfer(dump("seed42_K32_f32.bin"), 0_int32, size(dump("seed42_K32_f32.bin")) / 4)
            allocate (gf32(size(w32)))
            rng = tandem_new(42_int64)
            call fillf32(v, rng, gf32)
            call check(all(transfer(gf32, 0_int32, size(w32)) == w32), "seed42_K32_f32")
            deallocate (gf32)
        end do
    end subroutine

    ! Both layouts of the kernel (K = 1 and large K), starts inside a row and off alignment,
    ! short and long fills. The position must match the CPU fill's.
    subroutine against_cpu()
        integer(int32), parameter :: ks(5) = [1, 2, 8, 32, 256]
        integer(int64), parameter :: starts(6) = [integer(int64) :: 0, 1, 40, 999, 1024 * 37 + 5, &
            2_int64**40 + 77]
        integer(int64), parameter :: lengths(5) = [integer(int64) :: 0, 1, 7, 1001, 60000]
        type(tandem_t) :: base, cpu, gpu
        integer(int32), allocatable :: c32(:), g32(:)
        integer(int64), allocatable :: c64(:), g64(:)
        real(real32), allocatable :: f32(:), h32(:)
        real(real64), allocatable :: f64(:), h64(:)
        integer :: v, a, b, c
        integer(int64) :: n
        character(80) :: what

        do v = 1, 2
            do a = 1, size(ks)
                base = tandem_new(int(a, int64), 99_int64, ks(a))
                do b = 1, size(starts)
                    call base%set_position(starts(b))
                    do c = 1, size(lengths)
                        n = lengths(c)
                        write (what, '(" variant=", i0, " K=", i0, " start=", i0, " n=", i0)') &
                            v, ks(a), starts(b), n
                        allocate (c32(n), g32(n), c64(n), g64(n), f32(n), h32(n), f64(n), h64(n))
                        cpu = base
                        gpu = base
                        call cpu%fill(c32)
                        call fill32(v, gpu, g32)
                        call check(all(g32 == c32) .and. cpu%position() == gpu%position(), "int32"//what)
                        cpu = base
                        gpu = base
                        call cpu%fill(c64)
                        call fill64(v, gpu, g64)
                        call check(all(g64 == c64) .and. cpu%position() == gpu%position(), "int64"//what)
                        cpu = base
                        gpu = base
                        call cpu%fill(f32)
                        call fillf32(v, gpu, h32)
                        call check(all(transfer(h32, 0_int32, int(n)) == transfer(f32, 0_int32, int(n))) &
                            .and. cpu%position() == gpu%position(), "real32"//what)
                        cpu = base
                        gpu = base
                        call cpu%fill(f64)
                        call fillf64(v, gpu, h64)
                        call check(all(transfer(h64, 0_int64, int(n)) == transfer(f64, 0_int64, int(n))) &
                            .and. cpu%position() == gpu%position(), "real64"//what)
                        deallocate (c32, g32, c64, g64, f32, h32, f64, h64)
                    end do
                end do
            end do
        end do
    end subroutine

    ! The bounds with a large range reject a quarter of the draws, so the fallback generator
    ! runs. The values and the position equal the host fill_below.
    subroutine bounded_against_cpu()
        integer(int32), parameter :: bounds32(5) = [1, 6, 1000, -1073741823, 0]
        integer(int64), parameter :: bounds64(5) = [1_int64, 3_int64, 1000000000000_int64, &
            -4611686018427387903_int64, 0_int64]
        ! The last start is bit 2^63 + 77, where a signed draw index would turn negative.
        integer(int64), parameter :: starts(4) = [integer(int64) :: 0, 5, 2_int64**40 + 77, &
            -huge(1_int64) + 76]
        integer(int64), parameter :: lengths(3) = [integer(int64) :: 0, 1001, 60000]
        type(tandem_t) :: base, cpu, gpu
        integer(int32), allocatable :: c32(:), g32(:)
        integer(int64), allocatable :: c64(:), g64(:)
        integer :: v, a, b, c
        integer(int64) :: n
        character(80) :: what

        do v = 1, 2
            do a = 1, size(bounds32)
                base = tandem_new(int(a, int64), 3_int64)
                do b = 1, size(starts)
                    ! set_position refuses a start past 2^63, so build the generator there.
                    base = tandem_from_key(base%key(), starts(b), base%chunk_length())
                    do c = 1, size(lengths)
                        n = lengths(c)
                        write (what, '(" variant=", i0, " bound=", i0, " start=", i0, " n=", i0)') &
                            v, bounds32(a), starts(b), n
                        allocate (c32(n), g32(n), c64(n), g64(n))
                        cpu = base
                        gpu = base
                        call cpu%fill_below(c32, bounds32(a))
                        if (v == 1) then
                            call tandem_fill_below_target(gpu, g32, bounds32(a))
                        else
                            call tandem_fill_below_stdpar(gpu, g32, bounds32(a))
                        end if
                        call check(all(g32 == c32) .and. cpu%position() == gpu%position(), &
                            "below int32"//what)
                        cpu = base
                        gpu = base
                        call cpu%fill_below(c64, bounds64(a))
                        if (v == 1) then
                            call tandem_fill_below_target(gpu, g64, bounds64(a))
                        else
                            call tandem_fill_below_stdpar(gpu, g64, bounds64(a))
                        end if
                        call check(all(g64 == c64) .and. cpu%position() == gpu%position(), &
                            "below int64"//what)
                        deallocate (c32, g32, c64, g64)
                    end do
                end do
            end do
        end do
    end subroutine

    ! A bounded fill cut at an arbitrary element boundary equals the whole fill, rejected draws
    ! included, and both equal the host fill.
    subroutine bounded_cut()
        integer, parameter :: n = 1000, cuts(3) = [1, 337, 999]
        type(tandem_t) :: base, whole, part, cpu
        integer(int32) :: w32(n), p32(n), c32(n)
        integer(int64) :: w64(n), p64(n), c64(n)
        integer :: v, j, m
        base = tandem_new(8_int64, 2_int64)
        call base%set_position(5_int64)
        do v = 1, 2
            do j = 1, size(cuts)
                m = cuts(j)
                whole = base
                part = base
                cpu = base
                call cpu%fill_below(c32, -1073741823_int32)
                if (v == 1) then
                    call tandem_fill_below_target(whole, w32, -1073741823_int32)
                    call tandem_fill_below_target(part, p32(:m), -1073741823_int32)
                    call tandem_fill_below_target(part, p32(m + 1:), -1073741823_int32)
                else
                    call tandem_fill_below_stdpar(whole, w32, -1073741823_int32)
                    call tandem_fill_below_stdpar(part, p32(:m), -1073741823_int32)
                    call tandem_fill_below_stdpar(part, p32(m + 1:), -1073741823_int32)
                end if
                call check(all(w32 == p32) .and. all(w32 == c32) .and. &
                    whole%position() == part%position(), "below int32 cut")
                whole = base
                part = base
                cpu = base
                call cpu%fill_below(c64, -4611686018427387903_int64)
                if (v == 1) then
                    call tandem_fill_below_target(whole, w64, -4611686018427387903_int64)
                    call tandem_fill_below_target(part, p64(:m), -4611686018427387903_int64)
                    call tandem_fill_below_target(part, p64(m + 1:), -4611686018427387903_int64)
                else
                    call tandem_fill_below_stdpar(whole, w64, -4611686018427387903_int64)
                    call tandem_fill_below_stdpar(part, p64(:m), -4611686018427387903_int64)
                    call tandem_fill_below_stdpar(part, p64(m + 1:), -4611686018427387903_int64)
                end if
                call check(all(w64 == p64) .and. all(w64 == c64) .and. &
                    whole%position() == part%position(), "below int64 cut")
            end do
        end do
    end subroutine

    ! m elements of the bounded fill of case c by variant v, as unsigned bit patterns.
    function below_case(v, c, g, m) result(bits)
        integer, intent(in) :: v, m
        type(conformance_case), intent(in) :: c
        type(tandem_t), intent(inout) :: g
        integer(int64) :: bits(m)
        integer(int32) :: x32(m)
        integer(int64) :: x64(m)
        if (c%kind == "fill_below_u32") then
            if (v == 1) then
                call tandem_fill_below_target(g, x32, as_int32(c%range))
            else
                call tandem_fill_below_stdpar(g, x32, as_int32(c%range))
            end if
            bits = iand(int(x32, int64), 4294967295_int64)
        else
            if (v == 1) then
                call tandem_fill_below_target(g, x64, c%range)
            else
                call tandem_fill_below_stdpar(g, x64, c%range)
            end if
            bits = x64
        end if
    end function

    ! Every case of fill_below.json, whole and cut at elements 1, 7, 20, 21 and n - 1.
    subroutine conformance_cases()
        type(conformance_case), allocatable :: cases(:)
        type(tandem_t) :: g
        integer(int64), allocatable :: got(:)
        integer :: cut(5), v, i, j, m, n
        cases = read_cases("fill_below.json")
        do v = 1, 2
            do i = 1, size(cases)
                associate (c => cases(i))
                    n = int(c%n)
                    g = tandem_from_key(c%key, c%start, c%K)
                    got = below_case(v, c, g, n)
                    call check(all(got == c%values), c%id//": values")
                    if (c%end >= 0) call check(g%position() == c%end, c%id//": end")
                    cut = [1, 7, 20, 21, n - 1]
                    do j = 1, size(cut)
                        m = cut(j)
                        if (m < 1 .or. m >= n) cycle
                        g = tandem_from_key(c%key, c%start, c%K)
                        got(:m) = below_case(v, c, g, m)
                        got(m + 1:) = below_case(v, c, g, n - m)
                        call check(all(got == c%values), c%id//": cut fill values")
                        if (c%end >= 0) call check(g%position() == c%end, c%id//": cut fill end")
                    end do
                end associate
            end do
        end do
    end subroutine

    ! The SHA-256 of hashes.json for the stream types these fills make.
    subroutine stream_hashes()
        type(stream_case), allocatable :: s(:)
        type(tandem_t) :: g
        integer(int32), allocatable :: x32(:)
        integer(int64), allocatable :: x64(:)
        real(real32), allocatable :: f32(:)
        real(real64), allocatable :: f64(:)
        integer(int8), allocatable :: bytes(:)
        integer :: v, i, n, done
        s = read_streams()
        do v = 1, 2
            done = 0
            do i = 1, size(s)
                g = tandem_from_key(s(i)%key, s(i)%start, s(i)%K)
                n = int(s(i)%n)
                select case (s(i)%type)
                case ("UInt32")
                    allocate (x32(n))
                    call fill32(v, g, x32)
                    bytes = transfer(x32, bytes)
                    deallocate (x32)
                case ("UInt64")
                    allocate (x64(n))
                    call fill64(v, g, x64)
                    bytes = transfer(x64, bytes)
                    deallocate (x64)
                case ("Float32")
                    allocate (f32(n))
                    call fillf32(v, g, f32)
                    bytes = transfer(f32, bytes)
                    deallocate (f32)
                case ("Float64")
                    allocate (f64(n))
                    call fillf64(v, g, f64)
                    bytes = transfer(f64, bytes)
                    deallocate (f64)
                case default
                    cycle
                end select
                done = done + 1
                call check(sha256_hex(bytes) == s(i)%sha256, s(i)%file//": sha256")
            end do
            call check(done == 5, "five streams")
        end do
    end subroutine

end program test_target
