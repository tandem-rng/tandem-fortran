! Tandem8x32 fills of NVIDIA GPU memory, over tandem.cuh (src/c/tandem_cuda_fill.cu).
! Copyright 2026 Jessica Cox. Apache License 2.0, see LICENSE.
!
! A device fill writes the values a CPU fill of the same generator would write, and moves the
! generator past them, so CPU draws and device fills interleave on one stream. Device memory
! is a type(c_ptr): from tandem_device_alloc, or c_devloc(x) for a CUDA Fortran device array.
! Fills run asynchronously on the default stream.
module tandem_rng_cuda
    use, intrinsic :: iso_c_binding, only: c_int, c_int32_t, c_int64_t, c_null_ptr, c_ptr, &
        c_size_t
    use, intrinsic :: iso_fortran_env, only: int32, int64
    use tandem_rng, only: tandem_t
    implicit none
    private

    public :: tandem_device_fill_real64, tandem_device_fill_real32, tandem_device_fill_int64, &
        tandem_device_fill_int32, tandem_device_fill_int16, tandem_device_fill_int8, &
        tandem_device_fill_logical, tandem_device_fill_real16_bits, &
        tandem_device_fill_complex64, tandem_device_fill_complex32
    public :: tandem_device_fill_below_int32, tandem_device_fill_below_int64, &
        tandem_device_fill_normal_real64, tandem_device_fill_normal_real32, &
        tandem_device_fill_exponential_real64, tandem_device_fill_exponential_real32
    public :: tandem_device_alloc, tandem_device_free, tandem_copy_to_host, &
        tandem_copy_to_device, tandem_device_synchronize

    integer, parameter :: F64 = 1, F32 = 2, U64 = 3, U32 = 4, U16 = 5, U8 = 6, BOOL = 7, &
        F16 = 8, NORMAL64 = 9, NORMAL32 = 10, EXP64 = 11, EXP32 = 12

    ! cudaMemcpyKind
    integer(c_int), parameter :: HOST_TO_DEVICE = 1, DEVICE_TO_HOST = 2

    abstract interface
        function launcher(key, pos, K, out, n) result(err) bind(C)
            import :: c_int, c_int32_t, c_int64_t, c_ptr, c_size_t
            integer(c_int32_t), intent(in) :: key(4)
            integer(c_int64_t), intent(inout) :: pos
            integer(c_int32_t), value :: K
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
            integer(c_int) :: err
        end function

        function launcher_below32(key, pos, K, bound, out, n) result(err) bind(C)
            import :: c_int, c_int32_t, c_int64_t, c_ptr, c_size_t
            integer(c_int32_t), intent(in) :: key(4)
            integer(c_int64_t), intent(inout) :: pos
            integer(c_int32_t), value :: K
            integer(c_int32_t), value :: bound
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
            integer(c_int) :: err
        end function
        function launcher_below64(key, pos, K, bound, out, n) result(err) bind(C)
            import :: c_int, c_int32_t, c_int64_t, c_ptr, c_size_t
            integer(c_int32_t), intent(in) :: key(4)
            integer(c_int64_t), intent(inout) :: pos
            integer(c_int32_t), value :: K
            integer(c_int64_t), value :: bound
            type(c_ptr), value :: out
            integer(c_size_t), value :: n
            integer(c_int) :: err
        end function
    end interface

    procedure(launcher), bind(C, name="tandem_cuda_fill_u32") :: c_fill_u32
    procedure(launcher), bind(C, name="tandem_cuda_fill_u64") :: c_fill_u64
    procedure(launcher), bind(C, name="tandem_cuda_fill_f32") :: c_fill_f32
    procedure(launcher), bind(C, name="tandem_cuda_fill_f64") :: c_fill_f64
    procedure(launcher), bind(C, name="tandem_cuda_fill_u16") :: c_fill_u16
    procedure(launcher), bind(C, name="tandem_cuda_fill_u8") :: c_fill_u8
    procedure(launcher), bind(C, name="tandem_cuda_fill_bool") :: c_fill_bool
    procedure(launcher), bind(C, name="tandem_cuda_fill_f16_bits") :: c_fill_f16
    procedure(launcher), bind(C, name="tandem_cuda_fill_normal_f64") :: c_fill_normal64
    procedure(launcher), bind(C, name="tandem_cuda_fill_normal_f32") :: c_fill_normal32
    procedure(launcher), bind(C, name="tandem_cuda_fill_exponential_f64") :: c_fill_exp64
    procedure(launcher), bind(C, name="tandem_cuda_fill_exponential_f32") :: c_fill_exp32
    procedure(launcher_below32), bind(C, name="tandem_cuda_fill_u32_below") :: c_fill_below32
    procedure(launcher_below64), bind(C, name="tandem_cuda_fill_u64_below") :: c_fill_below64

    interface
        function cuda_malloc(p, nbytes) result(err) bind(C, name="cudaMalloc")
            import :: c_int, c_ptr, c_size_t
            type(c_ptr), intent(out) :: p
            integer(c_size_t), value :: nbytes
            integer(c_int) :: err
        end function
        function cuda_free(p) result(err) bind(C, name="cudaFree")
            import :: c_int, c_ptr
            type(c_ptr), value :: p
            integer(c_int) :: err
        end function
        function cuda_memcpy(dst, src, nbytes, kind) result(err) bind(C, name="cudaMemcpy")
            import :: c_int, c_ptr, c_size_t
            type(c_ptr), value :: dst, src
            integer(c_size_t), value :: nbytes
            integer(c_int), value :: kind
            integer(c_int) :: err
        end function
        function cuda_device_synchronize() result(err) bind(C, name="cudaDeviceSynchronize")
            import :: c_int
            integer(c_int) :: err
        end function
    end interface

contains

    ! n elements of uniform reals in [0, 1) at the device address x.
    subroutine tandem_device_fill_real64(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(F64, rng, x, n, stat)
    end subroutine

    subroutine tandem_device_fill_real32(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(F32, rng, x, n, stat)
    end subroutine

    ! Unsigned words, as their bit patterns in the signed type.
    subroutine tandem_device_fill_int64(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(U64, rng, x, n, stat)
    end subroutine

    subroutine tandem_device_fill_int32(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(U32, rng, x, n, stat)
    end subroutine

    subroutine tandem_device_fill_int16(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(U16, rng, x, n, stat)
    end subroutine

    subroutine tandem_device_fill_int8(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(U8, rng, x, n, stat)
    end subroutine

    ! One stream bit per element, stored as one byte: the memory is logical(c_bool).
    subroutine tandem_device_fill_logical(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(BOOL, rng, x, n, stat)
    end subroutine

    ! binary16 bit patterns of uniform draws in [0, 1), as 16-bit integers.
    subroutine tandem_device_fill_real16_bits(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(F16, rng, x, n, stat)
    end subroutine

    ! n complex elements are the 2n real draws of the real fill, real part first.
    subroutine tandem_device_fill_complex64(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(F64, rng, x, 2 * n, stat)
    end subroutine

    subroutine tandem_device_fill_complex32(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(F32, rng, x, 2 * n, stat)
    end subroutine

    ! Standard normals. real64 equals the host fill bit for bit. real32 agrees to a few ulps,
    ! as device log and cos differ from the host's in the last bits. The position moves as it
    ! does for the host fill.
    subroutine tandem_device_fill_normal_real64(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(NORMAL64, rng, x, n, stat)
    end subroutine

    subroutine tandem_device_fill_normal_real32(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(NORMAL32, rng, x, n, stat)
    end subroutine

    ! Standard exponentials -log(1 - u), element i from uniform i of the real fill of the same
    ! kind. They equal the host fill_exponential bit for bit.
    subroutine tandem_device_fill_exponential_real64(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(EXP64, rng, x, n, stat)
    end subroutine

    subroutine tandem_device_fill_exponential_real32(rng, x, n, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        call device_fill(EXP32, rng, x, n, stat)
    end subroutine

    ! A select rather than a dummy procedure: nvfortran 25.3 miscalls bind(C) dummy procedures.
    subroutine device_fill(kind, rng, x, n, stat)
        integer, intent(in) :: kind
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer, intent(out), optional :: stat
        integer(c_int32_t) :: key(4)
        integer(c_int64_t) :: pos
        integer(c_int) :: err
        key = rng%key()
        pos = rng%position()
        select case (kind)
        case (F64)
            err = c_fill_f64(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (F32)
            err = c_fill_f32(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (U64)
            err = c_fill_u64(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (U32)
            err = c_fill_u32(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (U16)
            err = c_fill_u16(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (U8)
            err = c_fill_u8(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (BOOL)
            err = c_fill_bool(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (F16)
            err = c_fill_f16(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (NORMAL64)
            err = c_fill_normal64(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (NORMAL32)
            err = c_fill_normal32(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case (EXP64)
            err = c_fill_exp64(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        case default
            err = c_fill_exp32(key, pos, rng%chunk_length(), x, int(n, c_size_t))
        end select
        call check(err, "fill", stat)
        call rng%set_position(pos)
    end subroutine

    ! Uniform on [0, bound) by Lemire's method, as the host fill_below: element i takes draw i
    ! of the plain fill and a rejected draw retries on a fallback generator, so the position
    ! moves by exactly n draws. bound is an unsigned bit pattern.
    subroutine tandem_device_fill_below_int32(rng, x, n, bound, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer(int32), intent(in) :: bound
        integer, intent(out), optional :: stat
        integer(c_int32_t) :: key(4)
        integer(c_int64_t) :: pos
        key = rng%key()
        pos = rng%position()
        call check(c_fill_below32(key, pos, rng%chunk_length(), bound, x, int(n, c_size_t)), &
            "fill", stat)
        call rng%set_position(pos)
    end subroutine

    subroutine tandem_device_fill_below_int64(rng, x, n, bound, stat)
        type(tandem_t), intent(inout) :: rng
        type(c_ptr), intent(in) :: x
        integer(int64), intent(in) :: n
        integer(int64), intent(in) :: bound
        integer, intent(out), optional :: stat
        integer(c_int32_t) :: key(4)
        integer(c_int64_t) :: pos
        key = rng%key()
        pos = rng%position()
        call check(c_fill_below64(key, pos, rng%chunk_length(), bound, x, int(n, c_size_t)), &
            "fill", stat)
        call rng%set_position(pos)
    end subroutine

    ! Without stat, a CUDA error stops the program.
    subroutine check(err, what, stat)
        integer(c_int), intent(in) :: err
        character(*), intent(in) :: what
        integer, intent(out), optional :: stat
        if (present(stat)) then
            stat = err
        else if (err /= 0) then
            write (*, '("tandem_rng_cuda: ", a, " failed with cudaError_t ", i0)') what, err
            error stop 1
        end if
    end subroutine

    function tandem_device_alloc(nbytes, stat) result(p)
        integer(int64), intent(in) :: nbytes
        integer, intent(out), optional :: stat
        type(c_ptr) :: p
        p = c_null_ptr
        call check(cuda_malloc(p, int(nbytes, c_size_t)), "cudaMalloc", stat)
    end function

    subroutine tandem_device_free(p, stat)
        type(c_ptr), intent(in) :: p
        integer, intent(out), optional :: stat
        call check(cuda_free(p), "cudaFree", stat)
    end subroutine

    ! Copies wait for preceding fills on the default stream.
    subroutine tandem_copy_to_host(dst, src, nbytes, stat)
        type(c_ptr), intent(in) :: dst, src
        integer(int64), intent(in) :: nbytes
        integer, intent(out), optional :: stat
        call check(cuda_memcpy(dst, src, int(nbytes, c_size_t), DEVICE_TO_HOST), "cudaMemcpy", stat)
    end subroutine

    subroutine tandem_copy_to_device(dst, src, nbytes, stat)
        type(c_ptr), intent(in) :: dst, src
        integer(int64), intent(in) :: nbytes
        integer, intent(out), optional :: stat
        call check(cuda_memcpy(dst, src, int(nbytes, c_size_t), HOST_TO_DEVICE), "cudaMemcpy", stat)
    end subroutine

    subroutine tandem_device_synchronize(stat)
        integer, intent(out), optional :: stat
        call check(cuda_device_synchronize(), "cudaDeviceSynchronize", stat)
    end subroutine

end module tandem_rng_cuda
