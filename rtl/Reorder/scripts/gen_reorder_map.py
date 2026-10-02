#!/usr/bin/env python3
"""Generate the map table (.mem) and ORDER for rtl/Reorder/reorder.sv.

casper_library's reorder takes a permutation `map` of 0 .. MAP_LEN-1 and
outputs every frame of MAP_LEN samples permuted: output step k of a frame is
input sample map[k] of the previous frame. In hardware (single buffered, as
reorder_init.m builds it) one read-before-write RAM is addressed, in the f-th
frame after a sync, with map^f(k) (map composed f times), which repeats with
period ORDER = lcm of the permutation's cycle lengths (compute_order.m).
reorder's implementation depends on ORDER (1: plain delay, 2: k / map[k]
select, > 2: an incrementally updated copy of map^f), so it needs ORDER as a
parameter, together with MAP_LEN and the map itself.

This script writes the map (row k = map[k], one hexadecimal word per line)
and prints MAP_LEN and ORDER:

    reorder #(.MAP_LEN(MAP_LEN), .ORDER(ORDER), .MAP_INIT_FILE("table.mem"), ...)

Maps can be given literally or by name of the casper block that uses them:

  --map 0 7 1 3 2 5 6 4               a literal permutation
  --bi-real {even,odd,out} --fft-size F
                                      bi_real_unscr_4x's reorder_even /
                                      reorder_odd / reorder_out maps
  --unscrambler --fft-size F --log2-n-groups N
                                      fft_unscrambler's map

Usage:
  python3 rtl/Reorder/scripts/gen_reorder_map.py --bi-real even --fft-size 5 -o even.mem
"""

import argparse
from math import gcd
from pathlib import Path


def bit_reverse(n, bits):
    """casper_library bit_reverse.m: reverse the low `bits` bits of n."""
    out = 0
    for i in range(bits):
        out |= ((n >> i) & 1) << (bits - 1 - i)
    return out


def compute_order(perm):
    """casper_library compute_order.m: lcm of the permutation's cycle lengths."""
    order = 1
    for i in range(len(perm)):
        j, length = perm[i], 1
        while j != i:
            j = perm[j]
            length += 1
        order = order * length // gcd(order, length)
    return order


def check_map(perm):
    n = len(perm)
    if n < 2 or n & (n - 1):
        raise ValueError(f"map length {n} is not a power of two >= 2 (reorder_init.m requires 2^k)")
    if sorted(perm) != list(range(n)):
        raise ValueError("map is not a permutation of 0 .. len-1")


def map_powers(perm):
    """[map^0, map^1, ..., map^(ORDER-1)] flattened (row f*len + k = map^f(k))."""
    check_map(perm)
    order = compute_order(perm)
    cur, table = list(range(len(perm))), []
    for _ in range(order):
        table += cur
        cur = [perm[c] for c in cur]
    return order, table


def bi_real_map(which, fft_size):
    """bi_real_unscr_4x_init.m: map_even, map_odd, map_out."""
    half = 2 ** (fft_size - 1)
    if which == "even":
        return [bit_reverse(i, fft_size - 1) for i in range(half)]
    if which == "odd":
        return [bit_reverse(i, fft_size - 1) for i in range(half - 1, -1, -1)]
    if which == "out":
        return list(range(half - 1, -1, -1))
    raise ValueError(which)


def unscrambler_map(fft_size, log2_n_groups):
    """fft_unscrambler_init.m: part = [0 : 2^(F-2n)-1]·2^n; map = [part+0, part+1, ...]."""
    n = log2_n_groups
    if fft_size - 2 * n < 0:
        raise ValueError("fft_unscrambler map needs 2*log2_n_groups <= fft_size (else casper's map is empty)")
    part = [i * 2 ** n for i in range(2 ** (fft_size - 2 * n))]
    return [p + g for g in range(2 ** n) for p in part]


def mem_lines(perm):
    """(ORDER, .mem rows): row k = map[k]."""
    check_map(perm)
    digits = max(1, ((len(perm) - 1).bit_length() + 3) // 4)
    return compute_order(perm), [f"{v:0{digits}x}" for v in perm]


def write_mem(path, perm):
    """Write reorder's table; returns (MAP_LEN, ORDER)."""
    order, lines = mem_lines(perm)
    Path(path).write_text("".join(line + "\n" for line in lines))
    return len(perm), order


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--map", type=int, nargs="+", help="literal permutation")
    src.add_argument("--bi-real", choices=["even", "odd", "out"],
                     help="a bi_real_unscr_4x reorder map (needs --fft-size)")
    src.add_argument("--unscrambler", action="store_true",
                     help="the fft_unscrambler map (needs --fft-size, --log2-n-groups)")
    ap.add_argument("--fft-size", type=int)
    ap.add_argument("--log2-n-groups", type=int)
    ap.add_argument("-o", "--output", required=True, help="output .mem file")
    args = ap.parse_args()
    if args.map:
        perm = args.map
    elif args.bi_real:
        if args.fft_size is None:
            ap.error("--bi-real needs --fft-size")
        perm = bi_real_map(args.bi_real, args.fft_size)
    else:
        if args.fft_size is None or args.log2_n_groups is None:
            ap.error("--unscrambler needs --fft-size and --log2-n-groups")
        perm = unscrambler_map(args.fft_size, args.log2_n_groups)
    map_len, order = write_mem(args.output, perm)
    print(f"wrote {args.output}: MAP_LEN={map_len} ORDER={order}")


if __name__ == "__main__":
    main()
