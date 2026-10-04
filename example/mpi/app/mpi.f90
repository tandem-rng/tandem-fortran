! Each rank owns a contiguous range of blocks. It fills its part of the field from the position
! where that part starts in the global fill, and draws each block's normals from split(block).
program mpi_example
    use, intrinsic :: iso_fortran_env, only: int64, real64
    use mpi_f08
    use tandem_rng
    use parallel_example
    implicit none
    type(tandem_t) :: field, noise, mine
    real(real64), allocatable :: x(:)
    integer(int64) :: h(blocks), all(blocks), lo, hi, b
    integer :: rank, ranks

    call MPI_Init()
    call MPI_Comm_rank(MPI_COMM_WORLD, rank)
    call MPI_Comm_size(MPI_COMM_WORLD, ranks)

    call field_and_noise(field, noise)
    lo = blocks * int(rank, int64) / ranks
    hi = blocks * int(rank + 1, int64) / ranks
    allocate (x((hi - lo) * block))

    ! Element i of the field, counted from 0, is draw i at bit 64 i.
    mine = field
    call mine%set_position(64 * lo * block)
    call mine%fill(x)

    h = 0
    do b = lo, hi - 1
        h(b + 1) = block_hash(noise, b, x((b - lo) * block + 1:(b - lo + 1) * block))
    end do
    call MPI_Reduce(h, all, blocks, MPI_INTEGER8, MPI_BXOR, 0, MPI_COMM_WORLD)
    if (rank == 0) write (*, '(z8.8)') combine(all)

    call MPI_Finalize()
end program
