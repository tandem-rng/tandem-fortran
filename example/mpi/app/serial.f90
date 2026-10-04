! The reference: one fill of the whole field on one thread.
program serial
    use, intrinsic :: iso_fortran_env, only: int64, real64
    use tandem_rng
    use parallel_example
    implicit none
    type(tandem_t) :: field, noise
    real(real64), allocatable :: x(:)
    integer(int64) :: h(blocks), b

    call field_and_noise(field, noise)
    allocate (x(n))
    call field%fill(x)
    do b = 0, blocks - 1
        h(b + 1) = block_hash(noise, b, x(b * block + 1:(b + 1) * block))
    end do
    write (*, '(z8.8)') combine(h)
end program
