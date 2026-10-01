#!/usr/bin/env python3
"""Generate the memory files of fft_direct, fft_biplex_real_4x and fft_wideband_real.

These modules read their twiddle tables and reorder maps from a directory
(COEFF_DIR / MAP_DIR / MEM_DIR, ending in '/'). This script writes every
file a configuration needs:

  direct          fft_direct: twiddle_direct_s<s>_<u>.mem for each butterfly
                  that uses a general twiddle (Coeffs as fft_direct_init.m)
  biplex_real_4x  fft_biplex_real_4x: twiddle_stage<s>.mem (biplex_core,
                  stages >= 3) and map_even.mem / map_odd.mem / map_out.mem
                  (bi_real_unscr_4x)
  wideband_real   fft_wideband_real: the biplex_real_4x files for the first
                  FFT_SIZE-N_INPUTS stages, the direct files for the last
                  N_INPUTS stages (MAP_TAIL on) and map_unscrambler.mem

Usage:
  python3 rtl/FFTs/scripts/gen_fft_mem_files.py wideband_real --fft-size 6 --n-inputs 2 \\
          --coeff-bit-width 18 -o mem/
  python3 rtl/FFTs/scripts/gen_fft_mem_files.py direct --fft-size 3 --coeff-bit-width 18 -o mem/
  python3 rtl/FFTs/scripts/gen_fft_mem_files.py direct --fft-size 2 --map-tail \\
          --larger-fft-size 6 --start-stage 5 --coeff-bit-width 18 -o mem/
"""

import argparse
import sys
from pathlib import Path

_RTL = Path(__file__).resolve().parents[2]
for _d in (_RTL / "FFTs" / "Twiddle" / "scripts", _RTL / "Reorder" / "scripts"):
    if str(_d) not in sys.path:
        sys.path.insert(0, str(_d))

from gen_twiddle_coeffs import bit_rev, mem_lines as twiddle_mem_lines, twiddle_table  # noqa: E402
from gen_reorder_map import bi_real_map, mem_lines as map_mem_lines, unscrambler_map    # noqa: E402


# ── fft_direct ──────────────────────────────────────────────────────────────

def direct_coeffs(fft_size, s, u, map_tail=False, larger=None, start=None):
    """Coeffs of butterfly u of stage s (fft_direct_init.m), and its FFT size."""
    n = u << (fft_size - s - 1)
    if not map_tail:
        return [n >> (fft_size - (s + 1))], fft_size
    out = []
    for r in range(2 ** (larger - fft_size)):
        num = n + bit_rev(r, larger - fft_size) * 2 ** (fft_size - 1)
        sh = larger - (start + s)
        out.append(num >> sh if sh >= 0 else num << -sh)
    return out, larger


def twiddle_kind(coeffs, fft_size, biplex=False, step_period=0):
    """butterfly_direct_init.m's twiddle selection."""
    if len(coeffs) == 1 and coeffs[0] == 0:
        return "pass_through" if biplex else "coeff_0"
    if len(coeffs) == 1 and coeffs[0] == 1:
        return "coeff_1"
    if len(coeffs) == 2 and coeffs == [0, 1] and step_period == fft_size - 2:
        return "stage_2"
    return "general"


def write_lines(path, lines):
    Path(path).write_text("".join(x + "\n" for x in lines))


def write_direct(out_dir, fft_size, coeff_bit_width, map_tail=False, larger=None, start=None):
    """Write fft_direct's general twiddle tables; returns the file names."""
    out_dir, names = Path(out_dir), []
    out_dir.mkdir(parents=True, exist_ok=True)
    for s in range(fft_size):
        for u in range(2 ** s):
            coeffs, size = direct_coeffs(fft_size, s, u, map_tail, larger, start)
            if twiddle_kind(coeffs, size) != "general":
                continue
            name = f"twiddle_direct_s{s}_{u}.mem"
            write_lines(out_dir / name, twiddle_mem_lines(
                twiddle_table(coeffs, size, coeff_bit_width), coeff_bit_width))
            names.append(name)
    return names


# ── fft_biplex_real_4x ──────────────────────────────────────────────────────

def write_biplex_real_4x(out_dir, fft_size, coeff_bit_width):
    out_dir, names = Path(out_dir), []
    out_dir.mkdir(parents=True, exist_ok=True)
    for s in range(3, fft_size + 1):           # biplex_core stages >= 3 use twiddle_general
        name = f"twiddle_stage{s}.mem"
        coeffs = list(range(1 << (s - 1)))
        write_lines(out_dir / name, twiddle_mem_lines(
            twiddle_table(coeffs, fft_size, coeff_bit_width), coeff_bit_width))
        names.append(name)
    for which in ("even", "odd", "out"):
        name = f"map_{which}.mem"
        write_lines(out_dir / name, map_mem_lines(bi_real_map(which, fft_size))[1])
        names.append(name)
    return names


# ── fft_wideband_real ───────────────────────────────────────────────────────

def write_wideband_real(out_dir, fft_size, n_inputs, coeff_bit_width, unscramble=True):
    names = write_biplex_real_4x(out_dir, fft_size - n_inputs, coeff_bit_width)
    names += write_direct(out_dir, n_inputs, coeff_bit_width, map_tail=True,
                          larger=fft_size, start=fft_size - n_inputs + 1)
    if unscramble and n_inputs > 1:
        name = "map_unscrambler.mem"
        write_lines(Path(out_dir) / name,
                    map_mem_lines(unscrambler_map(fft_size - 1, n_inputs - 1))[1])
        names.append(name)
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="block", required=True)
    d = sub.add_parser("direct", help="fft_direct")
    d.add_argument("--fft-size", type=int, required=True)
    d.add_argument("--map-tail", action="store_true")
    d.add_argument("--larger-fft-size", type=int)
    d.add_argument("--start-stage", type=int)
    b = sub.add_parser("biplex_real_4x", help="fft_biplex_real_4x")
    b.add_argument("--fft-size", type=int, required=True)
    w = sub.add_parser("wideband_real", help="fft_wideband_real")
    w.add_argument("--fft-size", type=int, required=True)
    w.add_argument("--n-inputs", type=int, required=True)
    w.add_argument("--no-unscramble", action="store_true")
    for p in (d, b, w):
        p.add_argument("--coeff-bit-width", type=int, required=True)
        p.add_argument("-o", "--output-dir", required=True)
    args = ap.parse_args()
    if args.block == "direct":
        if args.map_tail and (args.larger_fft_size is None or args.start_stage is None):
            ap.error("--map-tail needs --larger-fft-size and --start-stage")
        names = write_direct(args.output_dir, args.fft_size, args.coeff_bit_width,
                             args.map_tail, args.larger_fft_size, args.start_stage)
    elif args.block == "biplex_real_4x":
        names = write_biplex_real_4x(args.output_dir, args.fft_size, args.coeff_bit_width)
    else:
        names = write_wideband_real(args.output_dir, args.fft_size, args.n_inputs,
                                    args.coeff_bit_width, not args.no_unscramble)
    print(f"wrote {len(names)} files to {args.output_dir}: {' '.join(names) or '(none needed)'}")


if __name__ == "__main__":
    main()
