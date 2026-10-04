! Each thread fills an element range whose ends fall anywhere, not on block edges, to show that
! any cut of a fill gives the same values. Threads then share the blocks for the normals.
program omp_example
    use, intrinsic :: iso_fortran_env, only: int64, real64
    use omp_lib
    use tandem_rng
    use parallel_example
    implicit none
    type(tandem_t) :: field, noise, mine
    real(real64), allocatable :: x(:)
    integer(int64) :: h(blocks), a, e, t, nt, b

    call field_and_noise(field, noise)
    allocate (x(n))

    !$omp parallel private(mine, a, e, t, nt)
    t = omp_get_thread_num()
    nt = omp_get_num_threads()
    a = n * t / nt
    e = n * (t + 1) / nt
    mine = field
    call mine%set_position(64 * a)
    call mine%fill(x(a + 1:e))
    !$omp barrier
    !$omp do schedule(dynamic)
    do b = 0, blocks - 1
        h(b + 1) = block_hash(noise, b, x(b * block + 1:(b + 1) * block))
    end do
    !$omp end do
    !$omp end parallel

    write (*, '(z8.8)') combine(h)
end program
