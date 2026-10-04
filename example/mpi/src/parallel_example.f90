! The problem shared by the serial, MPI and OpenMP programs: a global field of n uniform doubles
! and one batch of normals per block. Every program must print the same hash, and it equals the
! hash of the C example in tandem-c.
module parallel_example
    use, intrinsic :: iso_fortran_env, only: int32, int64, real64
    use tandem_rng
    implicit none
    private
    public :: n, blocks, block, field_and_noise, block_hash, combine

    integer(int64), parameter :: n = 2_int64**24
    ! The block grid is part of the problem, not of the machine, so it stays fixed for any
    ! number of ranks or threads.
    integer, parameter :: blocks = 64
    integer(int64), parameter :: block = n / blocks
    integer, parameter :: normals = 4096
    ! Purposes give each use of randomness its own stream, so adding one leaves the others alone.
    integer(int64), parameter :: field_purpose = 1, noise_purpose = 2
    integer(int64), parameter :: mask32 = int(z'ffffffff', int64)

contains

    subroutine field_and_noise(field, noise)
        type(tandem_t), intent(out) :: field, noise
        type(tandem_t) :: root
        root = tandem_new(2026_int64)
        field = root%sub(field_purpose)
        noise = root%sub(noise_purpose)
    end subroutine

    ! One FNV-1a step over a 32-bit word. h and w stay below 2^32 in an int64, so the product
    ! cannot overflow.
    pure function step(h, w)
        integer(int64), intent(in) :: h, w
        integer(int64) :: step
        step = iand(ieor(h, w) * 16777619_int64, mask32)
    end function

    pure function fnv(h0, words) result(h)
        integer(int64), intent(in) :: h0
        integer(int32), intent(in) :: words(:)
        integer(int64) :: h
        integer(int64) :: i
        h = h0
        do i = 1, size(words, kind=int64)
            h = step(h, iand(int(words(i), int64), mask32))
        end do
    end function

    ! Hash of block b, counted from 0: its slice x of the field, then its normals from
    ! split(b) of the noise stream.
    function block_hash(noise, b, x) result(h)
        type(tandem_t), intent(in) :: noise
        integer(int64), intent(in) :: b
        real(real64), intent(in) :: x(:)
        integer(int64) :: h
        real(real64) :: z(normals)
        type(tandem_t) :: r
        r = noise%split(b)
        call r%fill_normal(z)
        h = fnv(fnv(2166136261_int64, transfer(x, 0_int32, 2 * size(x))), &
                transfer(z, 0_int32, 2 * normals))
    end function

    function combine(h) result(c)
        integer(int64), intent(in) :: h(blocks)
        integer(int64) :: c
        integer :: b
        c = 2166136261_int64
        do b = 1, blocks
            c = step(c, h(b))
        end do
    end function

end module parallel_example
