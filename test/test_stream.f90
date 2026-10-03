! Long-stream agreement with TandemRNG.jl, plus fill properties. The dumps in test/data are raw
! little-endian fills produced by the Julia reference, copied from tandem-c. Each is compared
! against a fill, against scalar draws, and at sampled indices against random access.
program test_stream
    use, intrinsic :: iso_c_binding, only: c_bool
    use, intrinsic :: iso_fortran_env, only: int8, int16, int32, int64, real32, real64
    use tandem_rng
    implicit none

    integer(int32), parameter :: KEY1234(4) = [1, 2, 3, 4]
    integer :: failures = 0, checks = 0

    call stream_int32("k1234_K32_u32.bin", tandem_from_key(KEY1234, K=32))
    call stream_int32("k1234_K8_u32.bin", tandem_from_key(KEY1234, K=8))
    call stream_int64()
    call stream_real64()
    call stream_real32()
    call stream_small()
    call stream_complex()
    call stream_logical()
    call stream_int128()
    call offsets()
    call mixed_widths()
    call shapes()

    if (failures > 0) then
        print '(i0, " of ", i0, " checks failed")', failures, checks
        error stop 1
    end if
    print '("streams: ", i0, " checks ok")', checks

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

    function seed42() result(rng)
        type(tandem_t) :: rng
        rng = tandem_new(42_int64)
    end function

    subroutine stream_int32(name, start)
        character(*), intent(in) :: name
        type(tandem_t), intent(in) :: start
        integer(int32), allocatable :: want(:), got(:), draws(:)
        type(tandem_t) :: a, b
        integer(int64) :: i
        want = transfer(dump(name), 0_int32, size(dump(name)) / 4)
        allocate (got(size(want)), draws(size(want)))
        a = start
        b = start
        call a%fill(got)
        do i = 1, size(want)
            draws(i) = b%next_int32()
        end do
        call check(all(got == want), name//": fill")
        call check(all(draws == want), name//": scalar draws")
        call check(a%position() == b%position(), name//": fill and draws end together")
        call check(all([(start%at_int32(i - 1) == want(i), i = 1, size(want), 97)]), &
            name//": random access")
    end subroutine

    subroutine stream_int64()
        integer(int64), allocatable :: want(:), got(:), draws(:)
        type(tandem_t) :: a, b, start
        integer(int64) :: i
        want = transfer(dump("k1234_K32_u64.bin"), 0_int64, size(dump("k1234_K32_u64.bin")) / 8)
        allocate (got(size(want)), draws(size(want)))
        start = tandem_from_key(KEY1234)
        a = start
        b = start
        call a%fill(got)
        do i = 1, size(want)
            draws(i) = b%next_int64()
        end do
        call check(all(got == want), "int64: fill")
        call check(all(draws == want), "int64: scalar draws")
        call check(all([(start%at_int64(i - 1) == want(i), i = 1, size(want), 97)]), &
            "int64: random access")
    end subroutine

    subroutine stream_real64()
        integer(int64), allocatable :: want(:)
        real(real64), allocatable :: got(:), draws(:), viaat(:)
        type(tandem_t) :: a, b, start
        integer(int64) :: i
        want = transfer(dump("seed42_K32_f64.bin"), 0_int64, size(dump("seed42_K32_f64.bin")) / 8)
        allocate (got(size(want)), draws(size(want)))
        start = seed42()
        a = start
        b = start
        call a%fill(got)
        do i = 1, size(want)
            draws(i) = b%next_real64()
        end do
        viaat = [(start%at_real64(i - 1), i = 1, size(want))]
        call check(all(transfer(got, 0_int64, size(got)) == want), "real64: fill")
        call check(all(transfer(draws, 0_int64, size(got)) == want), "real64: scalar draws")
        call check(all(transfer(viaat, 0_int64, size(got)) == want), "real64: random access")
        call check(a%position() == b%position(), "real64: fill and draws end together")
        a = start
        call tandem_random_number(a, got)
        call check(all(transfer(got, 0_int64, size(got)) == want), "real64: tandem_random_number")
    end subroutine

    subroutine stream_real32()
        integer(int32), allocatable :: want(:)
        real(real32), allocatable :: got(:), draws(:), viaat(:)
        type(tandem_t) :: a, b, start
        integer(int64) :: i
        want = transfer(dump("seed42_K32_f32.bin"), 0_int32, size(dump("seed42_K32_f32.bin")) / 4)
        allocate (got(size(want)), draws(size(want)))
        start = seed42()
        a = start
        b = start
        call a%fill(got)
        do i = 1, size(want)
            draws(i) = b%next_real32()
        end do
        viaat = [(start%at_real32(i - 1), i = 1, size(want))]
        call check(all(transfer(got, 0_int32, size(got)) == want), "real32: fill")
        call check(all(transfer(draws, 0_int32, size(got)) == want), "real32: scalar draws")
        call check(all(transfer(viaat, 0_int32, size(got)) == want), "real32: random access")
        a = start
        call tandem_random_number(a, got)
        call check(all(transfer(got, 0_int32, size(got)) == want), "real32: tandem_random_number")
    end subroutine

    ! Bytes, half-precision bit patterns, and code points.
    subroutine stream_small()
        integer(int8), allocatable :: want8(:), got8(:)
        integer(int16), allocatable :: want16(:), got16(:)
        integer(int32), allocatable :: wantc(:), gotc(:)
        type(tandem_t) :: a, b
        integer(int64) :: i
        logical :: ok

        want8 = dump("seed42_K32_u8.bin")
        allocate (got8(size(want8)))
        a = seed42()
        b = seed42()
        call a%fill(got8)
        call check(all(got8 == want8), "int8: fill")
        ok = .true.
        do i = 1, size(want8)
            ok = ok .and. b%next_int8() == want8(i)
        end do
        call check(ok, "int8: scalar draws")

        want16 = transfer(dump("seed42_K32_f16bits.bin"), 0_int16, &
            size(dump("seed42_K32_f16bits.bin")) / 2)
        allocate (got16(size(want16)))
        a = seed42()
        b = seed42()
        call a%fill_real16_bits(got16)
        call check(all(got16 == want16), "real16 bits: fill")
        ok = .true.
        do i = 1, size(want16)
            ok = ok .and. b%next_real16_bits() == want16(i)
        end do
        call check(ok, "real16 bits: scalar draws")

        wantc = transfer(dump("seed42_K32_char.bin"), 0_int32, size(dump("seed42_K32_char.bin")) / 4)
        allocate (gotc(size(wantc)))
        a = seed42()
        b = seed42()
        call a%fill_char(gotc)
        call check(all(gotc == wantc), "char: fill")
        ok = .true.
        do i = 1, size(wantc)
            ok = ok .and. b%next_char() == wantc(i)
        end do
        call check(ok, "char: scalar draws")
    end subroutine

    subroutine stream_complex()
        integer(int64), allocatable :: want64(:)
        integer(int32), allocatable :: want32(:)
        complex(real64), allocatable :: z64(:), d64(:)
        complex(real32), allocatable :: z32(:), d32(:)
        type(tandem_t) :: a, b
        integer :: i

        want64 = transfer(dump("seed42_K32_c64.bin"), 0_int64, size(dump("seed42_K32_c64.bin")) / 8)
        allocate (z64(size(want64) / 2), d64(size(want64) / 2))
        a = seed42()
        b = seed42()
        call a%fill(z64)
        do i = 1, size(d64)
            d64(i) = b%next_complex64()
        end do
        call check(all(transfer(z64, 0_int64, size(want64)) == want64), "complex64: fill")
        call check(all(transfer(d64, 0_int64, size(want64)) == want64), "complex64: scalar draws")

        want32 = transfer(dump("seed42_K32_c32.bin"), 0_int32, size(dump("seed42_K32_c32.bin")) / 4)
        allocate (z32(size(want32) / 2), d32(size(want32) / 2))
        a = seed42()
        b = seed42()
        call a%fill(z32)
        do i = 1, size(d32)
            d32(i) = b%next_complex32()
        end do
        call check(all(transfer(z32, 0_int32, size(want32)) == want32), "complex32: fill")
        call check(all(transfer(d32, 0_int32, size(want32)) == want32), "complex32: scalar draws")
    end subroutine

    ! The dump holds one byte, 0 or 1, per draw; each draw takes one stream bit.
    subroutine stream_logical()
        integer(int8), allocatable :: want(:)
        logical(c_bool), allocatable :: cb(:)
        logical, allocatable :: fl(:), draws(:)
        type(tandem_t) :: a, b, c
        integer :: i
        want = dump("seed42_K32_bool.bin")
        allocate (cb(size(want)), fl(size(want)), draws(size(want)))
        a = seed42()
        b = seed42()
        c = seed42()
        call a%fill(cb)
        call b%fill(fl)
        do i = 1, size(want)
            draws(i) = c%next_logical()
        end do
        call check(all(transfer(cb, 0_int8, size(cb)) == want), "logical(c_bool): fill")
        call check(all(fl .eqv. want == 1), "logical: fill")
        call check(all(draws .eqv. want == 1), "logical: scalar draws")
        call check(a%position() == size(want), "logical(c_bool): position")
        call check(b%position() == size(want), "logical: position")
    end subroutine

    subroutine stream_int128()
        integer(int64), allocatable :: want(:), got(:, :)
        type(tandem_t) :: a, b
        integer :: j
        logical :: ok
        want = transfer(dump("seed42_K32_u128.bin"), 0_int64, size(dump("seed42_K32_u128.bin")) / 8)
        allocate (got(2, size(want) / 2))
        a = seed42()
        b = seed42()
        call a%fill_int128(got)
        call check(all(reshape(got, [size(want)]) == want), "int128: fill")
        ok = .true.
        do j = 1, size(got, 2)
            ok = ok .and. all(b%next_int128() == want(2 * j - 1:2 * j))
        end do
        call check(ok, "int128: scalar draws")
    end subroutine

    ! Float fills that start inside a row agree with one whole fill at every offset.
    subroutine offsets()
        integer, parameter :: n = 3000
        integer(int64), parameter :: starts(11) = [0, 1, 5, 15, 16, 17, 31, 32, 33, 500, 1024]
        real(real64) :: whole(n), part(n)
        real(real32) :: wholef(n), partf(n)
        integer(int32) :: wholei(n), parti(n)
        type(tandem_t) :: r, base
        integer :: s, start
        integer(int8) :: byte
        character(64) :: what

        base = tandem_new(7_int64)
        r = base
        call r%fill(whole)
        r = base
        call r%fill(wholef)
        r = base
        call r%fill(wholei)
        do s = 1, size(starts)
            start = int(starts(s))
            write (what, '("from element ", i0)') start
            r = tandem_from_key(base%key(), 64 * starts(s))
            call r%fill(part(:n - start))
            call check(all(transfer(part(:n - start), 0_int64, n - start) == &
                transfer(whole(start + 1:), 0_int64, n - start)), "real64 fill "//trim(what))
            r = base
            call r%set_position(32 * starts(s))
            call r%fill(partf(:n - start))
            call check(all(transfer(partf(:n - start), 0_int32, n - start) == &
                transfer(wholef(start + 1:), 0_int32, n - start)), "real32 fill "//trim(what))
            r = base
            call r%set_position(32 * starts(s))
            call r%fill(parti(:n - start))
            call check(all(parti(:n - start) == wholei(start + 1:)), "int32 fill "//trim(what))
        end do

        r = base
        byte = r%next_int8()
        call r%fill(part(:40))
        call check(all(transfer(part(:40), 0_int64, 40) == transfer(whole(2:41), 0_int64, 40)), &
            "real64 fill after a byte draw")
        call check(r%position() == 64 * 41, "position after a byte draw and a fill")
    end subroutine

    ! Each draw aligns to its own width. The words come from the key-1234 int32 dump.
    subroutine mixed_widths()
        integer(int32), allocatable :: w(:)
        integer(int64), allocatable :: d(:)
        real(real32) :: f(3)
        type(tandem_t) :: r
        integer(int8) :: byte
        logical :: bit
        integer(int64) :: x64
        integer(int32) :: x32

        w = transfer(dump("k1234_K32_u32.bin"), 0_int32, 64)
        d = transfer(w, 0_int64, 32)
        r = tandem_from_key(KEY1234)
        byte = r%next_int8()
        call check(iand(int(byte, int32), 255) == iand(w(1), 255) .and. r%position() == 8, &
            "int8 at bit 0")
        x32 = r%next_int32()
        call check(x32 == w(2) .and. r%position() == 64, "int32 aligns to bit 32")
        bit = r%next_logical()
        call check((bit .eqv. btest(w(3), 0)) .and. r%position() == 65, "logical at bit 64")
        x64 = r%next_int64()
        call check(x64 == d(3) .and. r%position() == 192, "int64 aligns to bit 128")
        call r%fill(f)
        call check(all(transfer(f, 0_int32, 3) == transfer(real(ishft(w(7:9), -8), real32) * &
            2.0_real32**(-24), 0_int32, 3)) .and. r%position() == 288, "real32 fill at bit 192")
        call check(all(r%next_int128() == d(7:8)) .and. r%position() == 512, &
            "int128 aligns to bit 384")
    end subroutine

    ! Fills of any rank, scalars, and noncontiguous sections follow array element order.
    subroutine shapes()
        real(real64) :: flat(60), grid(3, 4, 5), one, strided(120)
        type(tandem_t) :: a, b
        integer(int32) :: counter
        a = seed42()
        b = seed42()
        call a%fill(flat)
        call b%fill(grid)
        call check(all(transfer(reshape(grid, [60]), 0_int64, 60) == transfer(flat, 0_int64, 60)), &
            "rank-3 fill")
        call check(a%position() == b%position(), "rank-3 fill position")
        a = seed42()
        b = seed42()
        call a%fill(one)
        call check(transfer(one, 0_int64) == transfer(b%next_real64(), 0_int64), "scalar fill")
        a = seed42()
        strided = -1.0_real64
        call a%fill(strided(1::2))
        call check(all(transfer(strided(1::2), 0_int64, 60) == transfer(flat, 0_int64, 60)), &
            "strided fill")
        call check(all(strided(2::2) < 0), "strided fill leaves the gaps")
        a = seed42()
        b = a
        counter = a%next_int32()
        call check(counter == b%next_int32(), "copies draw the same stream")
    end subroutine

end program test_stream
