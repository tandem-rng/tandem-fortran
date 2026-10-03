! Conformance against the specification's test vectors (test/vectors.f90).
program test_vectors
    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64
    use tandem_rng
    use tandem_vectors
    implicit none

    integer(int32), parameter :: DOMAIN_STREAM = int(z'9e3779b9', int32)
    integer(int32), parameter :: AUX_STREAM = int(z'94d049bb', int32)
    integer :: failures = 0, checks = 0
    integer :: i, k
    integer(int64) :: w, w0
    integer(int32) :: o(4), h(4), fill(64)
    type(tandem_t) :: rng, scalar, b, c, kids(2)
    logical :: got

    do i = 1, size(VEC_T)
        o = VEC_T(i)%o
        h = VEC_T(i)%h
        call tandem_apply_T(o, h)
        call check_words("T o", o, VEC_T(i)%o_out)
        call check_words("T h", h, VEC_T(i)%h_out)
    end do

    do i = 1, size(VEC_F)
        call tandem_F_keyed(VEC_KEY, VEC_F(i)%counter, DOMAIN_STREAM, AUX_STREAM, o, h)
        call check_words("F o", o, VEC_F(i)%o)
        call check_words("F h", h, VEC_F(i)%h)
    end do

    ! Stream words by three routes: a long fill, scalar draws, and random access.
    rng = tandem_from_key(VEC_KEY, 0_int64, VEC_K)
    scalar = rng
    call rng%fill(fill)
    do i = 1, size(VEC_STREAM)
        w0 = VEC_STREAM(i)%first_word
        do k = 1, 4
            call check_int("fill int32", w0 + k - 1, int(fill(w0 + k), int64), &
                int(VEC_STREAM(i)%words(k), int64))
            call check_int("at int32", w0 + k - 1, int(scalar%at_int32(w0 + k - 1), int64), &
                int(VEC_STREAM(i)%words(k), int64))
        end do
        call tandem_block(VEC_KEY, w0 / 4, 0, o)
        if (w0 < 32) call check_words("block", o, VEC_STREAM(i)%words)
    end do
    do w = 1, size(fill)
        call check_int("next int32", w - 1, int(scalar%next_int32(), int64), int(fill(w), int64))
    end do
    call check_int("position", 0_int64, scalar%position(), 32_int64 * size(fill))

    rng = tandem_from_key(VEC_KEY, 0_int64, VEC_K)
    do i = 1, size(VEC_REAL64)
        call check_real("real64", VEC_REAL64(i)%index, rng%at_real64(VEC_REAL64(i)%index), &
            VEC_REAL64(i)%value)
    end do
    do i = 1, size(VEC_REAL32)
        call check_real("real32", VEC_REAL32(i)%index, &
            real(rng%at_real32(VEC_REAL32(i)%index), real64), real(VEC_REAL32(i)%value, real64))
    end do
    do i = 1, size(VEC_LOGICAL)
        b = rng
        do w = 0, VEC_LOGICAL(i)%index
            got = b%next_logical()
        end do
        call check(got .eqv. VEC_LOGICAL(i)%value, "logical", VEC_LOGICAL(i)%index)
    end do

    rng = tandem_from_key(VEC_KEY, 0_int64, VEC_K)
    c = rng%split(0_int64)
    call check_words("split 0", c%key(), VEC_SPLIT0)
    c = rng%split(1_int64)
    call check_words("split 1", c%key(), VEC_SPLIT1)
    c = rng%sub(7_int64)
    call check_words("purpose 7", c%key(), VEC_PURPOSE7)
    call check_int("split chunk length", 0_int64, int(c%chunk_length(), int64), int(VEC_K, int64))
    call rng%fork(kids)
    call check_words("fork 0", kids(1)%key(), VEC_FORK0)
    call check_int("fork parent position", 0_int64, rng%position(), 128_int64)
    call check_int("fork child position", 0_int64, kids(2)%position(), 0_int64)

    rng = tandem_new(VEC_SEED)
    call check_words("seed key", rng%key(), VEC_SEED_KEY)
    c = tandem_new(VEC_SEED, 0_int64)
    call check_words("seed key, 128-bit form", c%key(), VEC_SEED_KEY)
    do i = 1, size(VEC_SEED_REAL64)
        call check_real("seed real64", VEC_SEED_REAL64(i)%index, &
            rng%at_real64(VEC_SEED_REAL64(i)%index), VEC_SEED_REAL64(i)%value)
    end do
    do i = 1, size(VEC_SEED_INT32)
        call check_int("seed int32", VEC_SEED_INT32(i)%index, &
            int(rng%at_int32(VEC_SEED_INT32(i)%index), int64), int(VEC_SEED_INT32(i)%value, int64))
    end do

    if (failures > 0) then
        print '(i0, " of ", i0, " checks failed")', failures, checks
        error stop 1
    end if
    print '("vectors: ", i0, " checks ok")', checks

contains

    subroutine check(ok, what, i)
        logical, intent(in) :: ok
        character(*), intent(in) :: what
        integer(int64), intent(in) :: i
        checks = checks + 1
        if (.not. ok) then
            failures = failures + 1
            print '("FAIL ", a, "[", i0, "]")', what, i
        end if
    end subroutine

    subroutine check_words(what, got, want)
        character(*), intent(in) :: what
        integer(int32), intent(in) :: got(4), want(4)
        checks = checks + 1
        if (any(got /= want)) then
            failures = failures + 1
            print '("FAIL ", a, ": got ", 4(z8.8, 1x), "want ", 4(z8.8, 1x))', what, got, want
        end if
    end subroutine

    subroutine check_int(what, i, got, want)
        character(*), intent(in) :: what
        integer(int64), intent(in) :: i, got, want
        checks = checks + 1
        if (got /= want) then
            failures = failures + 1
            print '("FAIL ", a, "[", i0, "]: got ", z16.16, ", want ", z16.16)', what, i, got, want
        end if
    end subroutine

    subroutine check_real(what, i, got, want)
        character(*), intent(in) :: what
        integer(int64), intent(in) :: i
        real(real64), intent(in) :: got, want
        checks = checks + 1
        if (transfer(got, 0_int64) /= transfer(want, 0_int64)) then
            failures = failures + 1
            print '("FAIL ", a, "[", i0, "]: got ", es25.17, ", want ", es25.17)', what, i, got, want
        end if
    end subroutine

end program test_vectors
