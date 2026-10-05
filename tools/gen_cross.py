#!/usr/bin/env python3
"""Turn tandem-c's cross_*.h and cuda_fill_*.h fixtures into test/cross.f90, so the tests need
no C parser.

The cross fixtures hold values that core.hpp of tandem-cuda produces for bounded integers,
normals and exponentials, the cuda fixtures values its device fills produce. Usage:
tools/gen_cross.py path/to/tandem-c/tests > test/cross.f90
"""
import re
import sys

PER_LINE = {"int32": 6, "int64": 4, "real64": 3, "real32": 4}


def signed(x, bits):
    """The unsigned value as the signed integer with the same bit pattern, as a literal."""
    x = x - (1 << bits) if x >= 1 << (bits - 1) else x
    kind = f"int{bits}"
    if x == -(1 << (bits - 1)):  # the literal 2^(bits-1) overflows before the negation
        return f"(-{-(x + 1)}_{kind} - 1_{kind})"
    return f"{x}_{kind}"


def literal(x, kind):
    if kind.startswith("int"):
        return signed(x, int(kind[3:]))
    return f"{x!r}_{kind}"


def array(name, kind, values, shape):
    """A parameter array, shape given as a Fortran extent list, filled in column-major order."""
    n = PER_LINE[kind]
    items = [literal(v, kind) for v in values]
    rows = [", ".join(items[i:i + n]) for i in range(0, len(items), n)]
    body = ", &\n        ".join(rows)
    if len(shape) == 1:
        return f"    {decl(kind)}, parameter :: {name}({shape[0]}) = [ &\n        {body}]"
    return (f"    {decl(kind)}, parameter :: {name}({', '.join(map(str, shape))}) = reshape([ &\n"
            f"        {body}], &\n        [{', '.join(map(str, shape))}])")


def decl(kind):
    return {"int32": "integer(int32)", "int64": "integer(int64)",
            "real64": "real(real64)", "real32": "real(real32)"}[kind]


def number(text):
    return int(re.sub(r"(ull|u)$", "", text))


def cases(source, name):
    """The (n, want, end_pos, start) entries of a struct array. A fill fixture has a start
    position, a scalar fixture has none and gets 0."""
    block = source.split(f"{name}[] = {{", 1)[1].split("\n};", 1)[0]
    pattern = r"\{(?:(\d+ull),\s*)?(\d+(?:ull|u)),\s*\{([^}]*)\},\s*(\d+(?:ull|u))\}"
    return [(number(n), [number(w) for w in ws.split(",")], number(e), number(s) if s else 0)
            for s, n, ws, e in re.findall(pattern, block)]


def floats(source, name):
    block = source.split(f"{name}[2 * CROSS_NORMAL_COUNT] = {{", 1)[1].split("};", 1)[0]
    return [float(x.strip().rstrip("f")) for x in block.replace("\n", " ").split(",") if x.strip()]


def start_fills(source, name):
    """The (start, values, end_pos) entries of a fill fixture with one row per start."""
    block = source.split(f"{name}[] = {{", 1)[1].split("\n};", 1)[0]
    pattern = r"\{(\d+)ull,\s*\{([^}]*)\},\s*(\d+)u\}"
    return [(int(s), [float(v.strip().rstrip("f")) for v in vs.split(",")], int(e))
            for s, vs, e in re.findall(pattern, block)]


def start_arrays(prefix, source, name, kind, count):
    """prefix_START, prefix_WANT (count values per start) and prefix_END of a fill fixture."""
    fills = start_fills(source, name)
    assert fills and all(len(f[1]) == count for f in fills)
    m = len(fills)
    return [array(f"{prefix}_START", "int64", [f[0] for f in fills], [m]),
            array(f"{prefix}_WANT", kind, [v for f in fills for v in f[1]], [count, m]),
            array(f"{prefix}_END", "int64", [f[2] for f in fills], [m])]


def device_cases(source, name, parse):
    """The (head, count, values) entries of a cuda fixture {range or pos, rejected or n, {values}}."""
    block = source.split(f"{name}[] = {{", 1)[1].split("\n};", 1)[0]
    pattern = r"\{(\d+)(?:ull|u), (\d+), \{([^}]*)\}\}"
    return [(int(head), int(count), [parse(v.strip()) for v in values.split(",")])
            for head, count, values in re.findall(pattern, block)]


def device_arrays(prefix, source, name, kind, parse, head_kind, with_n):
    """prefix_HEAD holds the range or start position per case, prefix_OUT the 64 values of each
    case, padded with zeros, and prefix_N the count of values when the fixture has one."""
    entries = device_cases(source, name, parse)
    m = len(entries)
    out = [array(f"{prefix}_HEAD", head_kind, [e[0] for e in entries], [m])]
    if with_n:
        out.append(array(f"{prefix}_N", "int32", [e[1] for e in entries], [m]))
    zero = 0.0 if kind.startswith("real") else 0
    out.append(array(f"{prefix}_OUT", kind,
                     [v for e in entries for v in e[2] + [zero] * (64 - len(e[2]))], [64, m]))
    return out


def end_pos(source, name):
    return int(re.search(rf"{name} = (\d+)u;", source).group(1))


def main(directory):
    below = open(f"{directory}/cross_below.h").read()
    fill = open(f"{directory}/cross_fill_below.h").read()
    normal = open(f"{directory}/cross_normal.h").read()
    exponential = open(f"{directory}/cross_exponential.h").read()
    device_below = open(f"{directory}/cuda_fill_below.h").read()
    device_normal = open(f"{directory}/cuda_fill_normal.h").read()
    count = int(re.search(r"CROSS_COUNT (\d+)", below).group(1))
    assert count == int(re.search(r"CROSS_NORMAL_COUNT (\d+)", normal).group(1))
    assert count == int(re.search(r"CROSS_EXPONENTIAL_COUNT (\d+)", exponential).group(1))

    out = [
        "! Generated by tools/gen_cross.py from tandem-c's tests/cross_*.h and cuda_fill_*.h.",
        "! Do not edit.",
        "module tandem_cross",
        "    use, intrinsic :: iso_fortran_env, only: int32, int64, real32, real64",
        "    implicit none",
        "",
        f"    integer, parameter :: CROSS_COUNT = {count}",
    ]
    for prefix, source, tag in (("BELOW", below, "CROSS"), ("FILL_BELOW", fill, "CROSS_FILL")):
        for bits in (32, 64):
            entries = cases(source, f"{tag}_U{bits}")
            kind = f"int{bits}"
            m = len(entries)
            out.append(array(f"CROSS_{prefix}{bits}_N", kind, [e[0] for e in entries], [m]))
            out.append(array(f"CROSS_{prefix}{bits}_WANT", kind,
                             [w for e in entries for w in e[1]], [count, m]))
            out.append(array(f"CROSS_{prefix}{bits}_END", "int64", [e[2] for e in entries], [m]))
            if tag == "CROSS_FILL":
                out.append(array(f"CROSS_{prefix}{bits}_START", "int64", [e[3] for e in entries], [m]))
    # Float64 ziggurat fills and exponential fills of CROSS_COUNT elements from each start.
    out += start_arrays("CROSS_NORMAL", normal, "CROSS_NORMAL", "real64", count)
    out += start_arrays("CROSS_EXPONENTIAL", exponential, "CROSS_EXPONENTIAL", "real64", count)
    out += start_arrays("CROSS_EXPONENTIALF", exponential, "CROSS_EXPONENTIALF", "real32", count)
    # Float32 pairs: element 2i is the cos half and 2i + 1 the sin half.
    out.append(array("CROSS_NORMALF", "real32", floats(normal, "CROSS_NORMALF"), [2 * count]))
    out.append(f"    integer(int64), parameter :: CROSS_NORMALF_END = "
               f"{end_pos(normal, 'CROSS_NORMALF_END_POS')}_int64")

    key = re.search(r"CROSS_FILL_KEY\[4\] = \{([^}]*)\}", device_below).group(1)
    out.append(array("CROSS_DEVICE_KEY", "int32", [int(w.strip().rstrip("u"), 16) for w in key.split(",")], [4]))
    out += device_arrays("CROSS_DEVICE_BELOW32", device_below, "CROSS_BELOW32", "int32", number, "int32", False)
    out += device_arrays("CROSS_DEVICE_BELOW64", device_below, "CROSS_BELOW64", "int64", number, "int64", False)
    out += device_arrays("CROSS_DEVICE_NORMAL64", device_normal, "CROSS_NORMAL64", "real64", float, "int64", True)
    out += device_arrays("CROSS_DEVICE_NORMAL32", device_normal, "CROSS_NORMAL32", "real32",
                         lambda v: float(v.rstrip("f")), "int64", True)
    out.append("end module tandem_cross")
    print("\n".join(out))


if __name__ == "__main__":
    main(sys.argv[1])
