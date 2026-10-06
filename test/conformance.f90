! Reader for the specification's conformance fixtures in test/conformance, copies of
! tandem-spec's conformance/*.json, plus the SHA-256 and FNV-1a hashes that hashes.json uses.
! The reader knows the layout that tools/gen_conformance.py of tandem-spec writes: one object
! per case with flat fields, so it finds a field by its quoted name.
module tandem_conformance
    use, intrinsic :: iso_fortran_env, only: int8, int32, int64
    implicit none
    private

    public :: read_cases, read_streams, read_dumps, find_case, as_int32, sha256_hex, fnv1a_init, &
        fnv1a_update, fnv1a_digest, hex64

    character(*), parameter, public :: CONFORMANCE_DIR = "test/conformance/"

    ! One case of below, fill_below, normal, exponential or choice.json. Hexadecimal fields hold
    ! their unsigned bit pattern, 32-bit ones in the low half. Absent end and rejected are -1.
    type, public :: conformance_case
        character(:), allocatable :: id, kind
        integer(int32) :: key(4) = 0, K = 0
        integer(int64) :: start = 0, n = 0, range = 0, end = -1, rejected = -1, capacity = 0
        logical :: tol = .false.
        integer(int64), allocatable :: values(:), weights(:), cut(:), alias(:)
    end type

    ! A uniform fill of hashes.json "streams".
    type, public :: stream_case
        character(:), allocatable :: file, type, sha256
        integer(int32) :: key(4) = 0, K = 0
        integer(int64) :: start = 0, n = 0, bytes = 0
    end type

    ! A long derived output of hashes.json "dumps": the draws run in order from each start.
    type, public :: dump_case
        character(:), allocatable :: id, sha256
        character(32), allocatable :: draws(:)
        integer(int32) :: key(4) = 0, K = 0
        integer(int64) :: bytes = 0, fnv1a = 0, end = -1
        integer(int64), allocatable :: starts(:), counts(:)
    end type

    integer(int64), parameter :: MASK32 = 4294967295_int64

contains

    function read_text(name) result(text)
        character(*), intent(in) :: name
        character(:), allocatable :: text
        integer :: u
        integer(int64) :: n
        open (newunit=u, file=CONFORMANCE_DIR//name, access="stream", form="unformatted", &
            status="old", action="read")
        inquire (unit=u, size=n)
        allocate (character(n) :: text)
        read (u) text
        close (u)
    end function

    ! The bounds a:b of the object or array that opens at text(a:a). Fixture strings hold no
    ! brackets of the other kind, so depth counting ignores strings.
    function closing(text, a) result(b)
        character(*), intent(in) :: text
        integer, intent(in) :: a
        integer :: b, depth
        character :: open, close
        open = text(a:a)
        close = merge("}", "]", open == "{")
        depth = 0
        do b = a, len(text)
            if (text(b:b) == open) depth = depth + 1
            if (text(b:b) == close) depth = depth - 1
            if (depth == 0) return
        end do
        error stop "conformance: unbalanced JSON"
    end function

    ! The objects of the top-level list name, as bounds into text.
    subroutine objects(text, name, first, last)
        character(*), intent(in) :: text, name
        integer, allocatable, intent(out) :: first(:), last(:)
        integer :: a, b, p, list_end
        p = index(text, '"'//name//'": [')
        if (p == 0) error stop "conformance: no list "//name
        p = p + len(name) + 4
        list_end = closing(text, p)
        allocate (first(0), last(0))
        do
            a = index(text(p + 1:list_end), "{")
            if (a == 0) exit
            a = p + a
            b = closing(text, a)
            first = [first, a]
            last = [last, b]
            p = b
        end do
    end subroutine

    ! The raw value text of field name in the object obj, or "" when absent.
    function raw(obj, name) result(v)
        character(*), intent(in) :: obj, name
        character(:), allocatable :: v
        integer :: a, b
        a = index(obj, '"'//name//'": ')
        if (a == 0) then
            v = ""
            return
        end if
        a = a + len(name) + 4
        select case (obj(a:a))
        case ("[", "{")
            b = closing(obj, a)
        case ('"')
            b = a + index(obj(a + 1:), '"')
        case default
            b = a + scan(obj(a:), ",}") - 2
        end select
        v = obj(a:b)
    end function

    function integer_field(obj, name, absent) result(x)
        character(*), intent(in) :: obj, name
        integer(int64), intent(in) :: absent
        integer(int64) :: x
        character(:), allocatable :: v
        v = raw(obj, name)
        x = absent
        if (len(v) > 0) read (v, *) x
    end function

    function string_field(obj, name) result(s)
        character(*), intent(in) :: obj, name
        character(:), allocatable :: s
        s = raw(obj, name)
        if (len(s) >= 2) s = s(2:len(s) - 1)
    end function

    ! The quoted items of a list field.
    function strings(obj, name) result(items)
        character(*), intent(in) :: obj, name
        character(64), allocatable :: items(:)
        character(:), allocatable :: v
        integer :: a, b
        v = raw(obj, name)
        allocate (items(0))
        b = 0
        do
            a = index(v(b + 1:), '"')
            if (a == 0) exit
            a = b + a
            b = a + index(v(a + 1:), '"')
            items = [items, v(a + 1:b - 1)]
        end do
    end function

    ! A hexadecimal string of up to 16 digits as its unsigned bit pattern.
    elemental function hex64(s) result(x)
        character(*), intent(in) :: s
        integer(int64) :: x
        integer :: i
        x = 0
        do i = 1, len_trim(s)
            x = ior(shiftl(x, 4), int(index("0123456789abcdef", s(i:i)) - 1, int64))
        end do
    end function

    ! The low 32 bits as the signed integer with that bit pattern.
    elemental function as_int32(x) result(r)
        integer(int64), intent(in) :: x
        integer(int32) :: r
        integer(int64) :: low
        low = iand(x, MASK32)
        if (low >= 2_int64**31) low = low - 2_int64**32
        r = int(low, int32)
    end function

    function key_field(obj) result(key)
        character(*), intent(in) :: obj
        integer(int32) :: key(4)
        key = as_int32(hex64(strings(obj, "key")))
    end function

    function read_cases(name) result(cases)
        character(*), intent(in) :: name
        type(conformance_case), allocatable :: cases(:)
        character(:), allocatable :: text
        integer, allocatable :: first(:), last(:)
        integer :: i
        text = read_text(name)
        call objects(text, "cases", first, last)
        allocate (cases(size(first)))
        do i = 1, size(first)
            associate (obj => text(first(i):last(i)), c => cases(i))
                c%id = string_field(obj, "id")
                c%kind = string_field(obj, "kind")
                c%key = key_field(obj)
                c%K = int(integer_field(obj, "K", 0_int64), int32)
                c%start = integer_field(obj, "start", 0_int64)
                c%n = integer_field(obj, "n", 0_int64)
                c%end = integer_field(obj, "end", -1_int64)
                c%rejected = integer_field(obj, "rejected", -1_int64)
                c%range = hex64(string_field(obj, "range"))
                c%capacity = hex64(string_field(obj, "capacity"))
                c%tol = len(raw(obj, "tol")) > 0
                c%values = hex64(strings(obj, "values"))
                c%weights = hex64(strings(obj, "weights"))
                c%cut = hex64(strings(obj, "cut"))
                c%alias = hex64(strings(obj, "alias"))
            end associate
        end do
    end function

    ! The case whose id ends in suffix, such as "CROSS_BELOW32[4]".
    pure function find_case(cases, suffix) result(c)
        type(conformance_case), intent(in) :: cases(:)
        character(*), intent(in) :: suffix
        type(conformance_case) :: c
        integer :: i, n
        do i = 1, size(cases)
            n = len(cases(i)%id)
            if (n < len(suffix)) cycle
            if (cases(i)%id(n - len(suffix) + 1:) == suffix) then
                c = cases(i)
                return
            end if
        end do
        error stop "conformance: no case "//suffix
    end function

    function read_streams() result(streams)
        type(stream_case), allocatable :: streams(:)
        character(:), allocatable :: text
        integer, allocatable :: first(:), last(:)
        integer :: i
        text = read_text("hashes.json")
        call objects(text, "streams", first, last)
        allocate (streams(size(first)))
        do i = 1, size(first)
            associate (obj => text(first(i):last(i)), s => streams(i))
                s%file = string_field(obj, "file")
                s%type = string_field(obj, "type")
                s%sha256 = string_field(obj, "sha256")
                s%key = key_field(obj)
                s%K = int(integer_field(obj, "K", 0_int64), int32)
                s%start = integer_field(obj, "start", 0_int64)
                s%n = integer_field(obj, "n", 0_int64)
                s%bytes = integer_field(obj, "bytes", 0_int64)
            end associate
        end do
    end function

    function read_dumps() result(dumps)
        type(dump_case), allocatable :: dumps(:)
        character(:), allocatable :: text, list
        integer, allocatable :: first(:), last(:), a(:), b(:)
        integer :: i, j
        text = read_text("hashes.json")
        call objects(text, "dumps", first, last)
        allocate (dumps(size(first)))
        do i = 1, size(first)
            associate (obj => text(first(i):last(i)), d => dumps(i))
                d%id = string_field(obj, "id")
                d%sha256 = string_field(obj, "sha256")
                d%key = key_field(obj)
                d%K = int(integer_field(obj, "K", 0_int64), int32)
                d%bytes = integer_field(obj, "bytes", 0_int64)
                d%fnv1a = hex64(string_field(obj, "fnv1a"))
                d%end = integer_field(obj, "end", -1_int64)
                list = raw(obj, "starts")
                allocate (d%starts(count_items(list)))
                read (list(2:len(list) - 1), *) d%starts
                list = obj
                call objects(list, "draws", a, b)
                allocate (d%draws(size(a)), d%counts(size(a)))
                do j = 1, size(a)
                    d%draws(j) = string_field(list(a(j):b(j)), "kind")
                    d%counts(j) = integer_field(list(a(j):b(j)), "n", 0_int64)
                end do
            end associate
        end do
    end function

    pure function count_items(list) result(n)
        character(*), intent(in) :: list
        integer :: n, i
        n = 0
        if (len_trim(list(2:len(list) - 1)) > 0) n = 1
        do i = 1, len(list)
            if (list(i:i) == ",") n = n + 1
        end do
    end function

    ! ---- Hashes: 32-bit words in int64, masked after every sum, so nothing overflows -----------

    pure function rotr(x, r) result(y)
        integer(int64), intent(in) :: x
        integer, intent(in) :: r
        integer(int64) :: y
        y = iand(ior(shiftr(x, r), shiftl(x, 32 - r)), MASK32)
    end function

    ! SHA-256 of bytes, as 64 hexadecimal digits.
    function sha256_hex(bytes) result(hex)
        integer(int8), intent(in) :: bytes(:)
        character(64) :: hex
        integer(int64), parameter :: KS(64) = [ &
            1116352408_int64, 1899447441_int64, 3049323471_int64, 3921009573_int64, 961987163_int64, &
            1508970993_int64, 2453635748_int64, 2870763221_int64, 3624381080_int64, 310598401_int64, &
            607225278_int64, 1426881987_int64, 1925078388_int64, 2162078206_int64, 2614888103_int64, &
            3248222580_int64, 3835390401_int64, 4022224774_int64, 264347078_int64, 604807628_int64, &
            770255983_int64, 1249150122_int64, 1555081692_int64, 1996064986_int64, 2554220882_int64, &
            2821834349_int64, 2952996808_int64, 3210313671_int64, 3336571891_int64, 3584528711_int64, &
            113926993_int64, 338241895_int64, 666307205_int64, 773529912_int64, 1294757372_int64, &
            1396182291_int64, 1695183700_int64, 1986661051_int64, 2177026350_int64, 2456956037_int64, &
            2730485921_int64, 2820302411_int64, 3259730800_int64, 3345764771_int64, 3516065817_int64, &
            3600352804_int64, 4094571909_int64, 275423344_int64, 430227734_int64, 506948616_int64, &
            659060556_int64, 883997877_int64, 958139571_int64, 1322822218_int64, 1537002063_int64, &
            1747873779_int64, 1955562222_int64, 2024104815_int64, 2227730452_int64, 2361852424_int64, &
            2428436474_int64, 2756734187_int64, 3204031479_int64, 3329325298_int64]
        integer(int64) :: h(8), w(64), s(8), t1, t2
        integer(int64), allocatable :: m(:)
        integer(int64) :: nbits
        integer :: nm, i, j, blk
        h = [1779033703_int64, 3144134277_int64, 1013904242_int64, 2773480762_int64, &
            1359893119_int64, 2600822924_int64, 528734635_int64, 1541459225_int64]
        nm = (size(bytes) + 8) / 64 * 64 + 64
        allocate (m(nm))
        m = 0
        m(:size(bytes)) = iand(int(bytes, int64), 255_int64)
        m(size(bytes) + 1) = 128
        nbits = 8_int64 * size(bytes)
        do i = 1, 8
            m(nm - i + 1) = iand(shiftr(nbits, 8 * (i - 1)), 255_int64)
        end do
        do blk = 0, nm - 64, 64
            do j = 1, 16
                w(j) = ior(ior(shiftl(m(blk + 4 * j - 3), 24), shiftl(m(blk + 4 * j - 2), 16)), &
                    ior(shiftl(m(blk + 4 * j - 1), 8), m(blk + 4 * j)))
            end do
            do j = 17, 64
                w(j) = iand(w(j - 16) + ieor(ieor(rotr(w(j - 15), 7), rotr(w(j - 15), 18)), &
                    shiftr(w(j - 15), 3)) + w(j - 7) + ieor(ieor(rotr(w(j - 2), 17), &
                    rotr(w(j - 2), 19)), shiftr(w(j - 2), 10)), MASK32)
            end do
            s = h
            do j = 1, 64
                t1 = iand(s(8) + ieor(ieor(rotr(s(5), 6), rotr(s(5), 11)), rotr(s(5), 25)) + &
                    ieor(iand(s(5), s(6)), iand(ieor(s(5), MASK32), s(7))) + KS(j) + w(j), MASK32)
                t2 = iand(ieor(ieor(rotr(s(1), 2), rotr(s(1), 13)), rotr(s(1), 22)) + &
                    ieor(ieor(iand(s(1), s(2)), iand(s(1), s(3))), iand(s(2), s(3))), MASK32)
                s(2:8) = s(1:7)
                s(5) = iand(s(5) + t1, MASK32)
                s(1) = iand(t1 + t2, MASK32)
            end do
            h = iand(h + s, MASK32)
        end do
        write (hex, '(8z8.8)') h
        do i = 1, 64
            j = index("ABCDEF", hex(i:i))
            if (j > 0) hex(i:i) = "abcdef"(j:j)
        end do
    end function

    ! FNV-1a 64 as (low, high) 32-bit halves. The prime is 2^40 + 435, so the high half gains
    ! the low half shifted by 8.
    pure function fnv1a_init() result(h)
        integer(int64) :: h(2)
        h = [2216829733_int64, 3421674724_int64]
    end function

    pure subroutine fnv1a_update(h, bytes)
        integer(int64), intent(inout) :: h(2)
        integer(int8), intent(in) :: bytes(:)
        integer(int64) :: lo, hi, p
        integer :: i
        lo = h(1)
        hi = h(2)
        do i = 1, size(bytes)
            lo = ieor(lo, iand(int(bytes(i), int64), 255_int64))
            p = lo * 435
            hi = iand(hi * 435 + shiftr(p, 32) + shiftl(lo, 8), MASK32)
            lo = iand(p, MASK32)
        end do
        h = [lo, hi]
    end subroutine

    pure function fnv1a_digest(h) result(x)
        integer(int64), intent(in) :: h(2)
        integer(int64) :: x
        x = ior(shiftl(h(2), 32), h(1))
    end function

end module tandem_conformance
