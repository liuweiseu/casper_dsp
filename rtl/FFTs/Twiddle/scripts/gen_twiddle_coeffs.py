#!/usr/bin/env python3
"""Generate the twiddle-coefficient table (.mem) for twiddle_general.

Implements casper_library's coeff_gen coefficient formula
(coeff_gen_init.m):

    br_indices   = bit_rev(Coeffs, FFTSize-1)
    ActualCoeffs = exp(-2*pi*1j * br_indices / 2^FFTSize)

Row k of the table is w[k] = ActualCoeffs[k], in the order of the Coeffs
list, so twiddle_general can walk the table with a plain counter (the
bit reversal is already in the values). A flat table is written; none of
casper_library's table-size optimizations (quarter-wave symmetry, packing,
coefficient sharing / decimation) are reproduced.

Each coefficient part is quantized to a COEFF_BIT_WIDTH-bit signed word with
binary point COEFF_BIT_WIDTH-1 (the format twiddle_general's multiplier
expects), rounding half away from zero (MATLAB round) and saturating, so
+1.0 becomes the largest positive word 1 - 2^-(COEFF_BIT_WIDTH-1).

Each .mem row is one hexadecimal word {re, im} (re in the upper
COEFF_BIT_WIDTH bits), matching rom's DATA_WIDTH = 2*COEFF_BIT_WIDTH.

Usage:
  python3 rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --fft-size 5 --coeffs 0 1 2 3 \\
      --coeff-bit-width 18 -o twiddle.mem
"""

import argparse
import cmath
import math
from pathlib import Path


def bit_rev(value, n_bits):
    """Reverse the n_bits least significant bits of value (MATLAB bit_rev)."""
    out = 0
    for _ in range(n_bits):
        out = (out << 1) | (value & 1)
        value >>= 1
    return out


def twiddle_values(coeffs, fft_size):
    """Exact complex twiddle factors w[k] for the Coeffs list."""
    return [cmath.exp(-2j * math.pi * bit_rev(c, fft_size - 1) / 2 ** fft_size)
            for c in coeffs]


def quantize_coeff(x, coeff_bit_width):
    """Real value -> signed integer with binary point coeff_bit_width-1."""
    scaled = x * 2 ** (coeff_bit_width - 1)
    q = math.floor(abs(scaled) + 0.5)          # round half away from zero
    q = q if scaled >= 0 else -q
    hi = (1 << (coeff_bit_width - 1)) - 1
    lo = -(1 << (coeff_bit_width - 1))
    return min(max(q, lo), hi)


def twiddle_table(coeffs, fft_size, coeff_bit_width):
    """[(re_int, im_int), ...] quantized signed integers, one per Coeffs entry."""
    return [(quantize_coeff(w.real, coeff_bit_width), quantize_coeff(w.imag, coeff_bit_width))
            for w in twiddle_values(coeffs, fft_size)]


def mem_lines(table, coeff_bit_width):
    """.mem rows: {re, im} packed as one 2*coeff_bit_width-bit hex word."""
    mask = (1 << coeff_bit_width) - 1
    digits = (2 * coeff_bit_width + 3) // 4
    return [f"{((re & mask) << coeff_bit_width) | (im & mask):0{digits}x}"
            for re, im in table]


def write_mem(path, coeffs, fft_size, coeff_bit_width):
    table = twiddle_table(coeffs, fft_size, coeff_bit_width)
    Path(path).write_text("".join(line + "\n" for line in mem_lines(table, coeff_bit_width)))
    return table


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--fft-size", type=int, required=True,
                    help="FFTSize: log2 of the FFT length")
    ap.add_argument("--coeffs", type=int, nargs="+", required=True,
                    help="Coeffs: twiddle indices in the order the hardware uses them")
    ap.add_argument("--coeff-bit-width", type=int, required=True,
                    help="COEFF_BIT_WIDTH of twiddle_general")
    ap.add_argument("-o", "--output", required=True, help="output .mem file")
    args = ap.parse_args()
    if args.fft_size < 1:
        ap.error("--fft-size must be >= 1")
    if any(c < 0 or c >= 2 ** (args.fft_size - 1) for c in args.coeffs):
        ap.error(f"coefficient indices must be in 0 .. 2^(fft-size-1)-1 = {2 ** (args.fft_size - 1) - 1}")
    write_mem(args.output, args.coeffs, args.fft_size, args.coeff_bit_width)
    print(f"wrote {len(args.coeffs)} coefficients to {args.output} "
          f"(twiddle_general: N_COEFFS={len(args.coeffs)}, "
          f"COEFF_BIT_WIDTH={args.coeff_bit_width}, FFT_SIZE={args.fft_size})")


if __name__ == "__main__":
    main()
