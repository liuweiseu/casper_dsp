#!/usr/bin/env python3
"""Generate the twiddle-coefficient table (.mem) for twiddle_general.

Row k of the table is the coefficient casper_library's coeff_gen
(coeff_gen_init.m) outputs for Coeffs[k],

    w[k] = exp(-2*pi*1j * bit_rev(Coeffs[k], FFTSize-1) / 2^FFTSize),

in the order of the Coeffs list, so twiddle_general walks the table with a
plain counter (the bit reversal is already in the values). The table is
flat, but each word is the one casper's cosin lookup produces:

- coeff_gen_init.m / cosin_init.m choose which part of the cycle is stored
  (full, half or quarter cycle), whether cos and sin share one table, and
  derive the other values by moving the address and negating. A stored
  +1.0 saturates to the largest word 1 - 2^-(COEFF_BIT_WIDTH-1), so a -1.0
  derived by negating it is -(1 - 2^-(COEFF_BIT_WIDTH-1)), not the most
  negative word (cos = -1 at w = -1, sin = -1 at w = -j). That layout
  depends on StepPeriod, coeffs_bit_limit, coeff_sharing and
  coeff_decimation, so pass the module's values.
- Exception (mlib_devel bug 15, docs/bugs.md): for quarter-cycle storage
  casper saturates the backwards address 2^lookup_bits at address 0 and
  reads the wrong entry; this table holds the intended value instead.
- Lists casper builds with a feedback_osc oscillator (coeff_generation on,
  bit-reversed and long enough), lists coeff_gen rejects, and in-order lists
  with FFTSize - StepPeriod - log2(length) != 1 get the exactly rounded
  formula values. For the last, casper's cosin uses the angles
  2*pi*bit_rev(k, log2 N)/2^(FFTSize - StepPeriod), which are not the formula
  (only the biplex case, FFTSize - StepPeriod - log2 N = 1, agrees).
- A one-entry list is coeff_gen's pair of Constants, which casper rounds to
  COEFF_BIT_WIDTH-2 fractional bits (coeff_gen_init.m:156-157).

Each part is a COEFF_BIT_WIDTH-bit signed word with binary point
COEFF_BIT_WIDTH-1 (the format twiddle_general's multiplier expects), rounded
half away from zero (MATLAB round) and saturated. Each .mem row is one
hexadecimal word {re, im} (re in the upper COEFF_BIT_WIDTH bits), matching
rom's DATA_WIDTH = 2*COEFF_BIT_WIDTH.

Usage:
  python3 rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --fft-size 5 --coeffs 0 1 2 3 \\
      --step-period 2 --coeff-bit-width 18 -o twiddle.mem
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


def quantize_const(x, coeff_bit_width):
    """coeff_gen's single-coefficient Constant (coeff_gen_init.m:156-157):
    rounded to coeff_bit_width-2 fractional bits, held in the same
    coeff_bit_width-1 binary-point word (saturating)."""
    q = math.floor(abs(x) * 2 ** (coeff_bit_width - 2) + 0.5)   # MATLAB round
    q = 2 * (q if x >= 0 else -q)
    hi = (1 << (coeff_bit_width - 1)) - 1
    lo = -(1 << (coeff_bit_width - 1))
    return min(max(q, lo), hi)


# ── casper's cosin lookup (coeff_gen_init.m, cosin_init.m) ──────────────────

_REF = ["cos", "-sin", "-cos", "sin"]       # coeff_gen output_ref
_BRAM_CAPACITY = 2 ** 9 * 36                 # coeff_gen_init.m:190-196
_DECIMATION_LIMIT_BITS = 6                   # coeff_gen_init.m:91


def _fval(func, angle):
    return {"cos": math.cos(angle), "sin": math.sin(angle),
            "-cos": -math.cos(angle), "-sin": -math.sin(angle)}[func]


def cosin_layout(coeffs, fft_size, coeff_bit_width, step_period, coeffs_bit_limit,
                 coeff_sharing, coeff_decimation, coeff_generation, latency_sum, cal_bits):
    """The cosin coeff_gen builds for a list of more than one coefficient, or
    None when it uses no cosin (feedback_osc) or rejects the list."""
    n, f = len(coeffs), fft_size
    inorder = all(coeffs[i + 1] - coeffs[i] == coeffs[i] - coeffs[i - 1] for i in range(1, n - 2))
    br = [bit_rev(c, f - 1) for c in coeffs]
    bit_reversed = (not inorder) and all(br[i + 1] - br[i] == br[i] - br[i - 1]
                                         for i in range(1, n - 2))
    if inorder:
        offset, step, top, bottom = coeffs[0], coeffs[1] - coeffs[0], coeffs[-1], coeffs[0]
    else:
        offset, step, top, bottom = br[0], br[1] - br[0], br[-1], br[0]
    if (not inorder and not bit_reversed) or (inorder and offset != 0) or offset % n:
        return None                          # coeff_gen_init.m:266-298 errors
    span = (top + step) - bottom
    if span <= 0 or (2 ** (f - step_period)) % span or n & (n - 1):
        return None
    multiple_bits = int(math.log2(2 ** (f - step_period) // span))
    if 2 ** multiple_bits * span != 2 ** (f - step_period):
        return None
    if (coeff_generation and bit_reversed
            and math.log2(n) <= math.ceil(math.log2(latency_sum + 1)) + cal_bits):
        coeff_generation = 0                 # coeff_gen_init.m:260-264
    if not inorder and coeff_generation:
        return None                          # feedback_osc
    table_bits = int(math.log2(n))
    fraction = offset / 2 ** (f - step_period)
    ref = int(math.floor(fraction / 0.25 + 1e-12))
    outputs = (_REF[ref % 4], _REF[(ref + 1) % 4])
    phase = fraction - ref * 0.25
    # coeff_gen_init.m:330-386: store / pack decisions
    derivable = phase == 0 and multiple_bits <= 2
    volume = n * 2 * coeff_bit_width
    n_brams = volume / _BRAM_CAPACITY
    if derivable and coeff_sharing:
        pack, volume = False, volume / 2
    else:
        pack = True
    if derivable and coeff_decimation and table_bits > _DECIMATION_LIMIT_BITS:
        store = 2
        volume = volume / 2 ** (store - multiple_bits)
        n_brams = volume / _BRAM_CAPACITY
    else:
        store = multiple_bits
    bram = volume > 2 ** coeffs_bit_limit
    if bram and derivable and coeff_decimation and n_brams < 1:
        new = (multiple_bits if n_brams <= 1 / 4 else
               max(1, multiple_bits) if n_brams <= 1 / 2 else 2)
        n_brams *= 2 ** (store - new)
        store = new
    if (not pack) and bram and coeff_bit_width * 2 <= 36 and n_brams <= 1 / 2:
        pack = True
    # cosin_init.m:173-210: overrides
    if store < multiple_bits or (multiple_bits <= 2 and store > 2):
        store = multiple_bits
    full_cycle_bits = table_bits + multiple_bits
    if full_cycle_bits < 3 or multiple_bits > 2 or phase != 0:
        store, pack = multiple_bits, True
    lookups = outputs if pack else (("cos", "cos") if store in (0, 1) else ("sin", "sin"))
    return dict(inorder=inorder, table_bits=table_bits, full_cycle_bits=full_cycle_bits,
                lookup_bits=full_cycle_bits - store, phase=phase, outputs=outputs,
                lookups=lookups)


def _cosin_word(theta, lay, i, coeff_bit_width):
    """cosin output i (add_convert + invert) for address theta, with the
    intended backwards address (bug 15 not reproduced)."""
    fcb, lb = lay["full_cycle_bits"], lay["lookup_bits"]
    lookup, output = lay["lookups"][i], lay["outputs"][i]
    diff = fcb - lb
    d = (_REF.index(output) - _REF.index(lookup)) % 4
    neg_off = (d + 1) % 4 if (diff == 2 and lookup in ("cos", "-cos")) else d
    quadrant = (theta >> (fcb - 2)) & 3
    low = theta & ((1 << (fcb - 2)) - 1)
    if d == 0 and diff == 0:
        qp, addr = quadrant, theta & ((1 << lb) - 1)
    else:
        qp = (quadrant + d) % 4
        addr = ((qp << (fcb - 2)) | low) & ((1 << lb) - 1)
    if diff == 2 and qp & 1:
        addr = (1 << lb) - addr                           # backwards
    invert = 0
    if diff != 0:
        invert = (((quadrant + neg_off) % 4 if neg_off != d else qp) >> 1) & 1
    angle = lay["phase"] * 2 * math.pi + 2 * math.pi / 2 ** fcb * addr
    v = quantize_coeff(_fval(lookup, angle), coeff_bit_width)
    return min(-v, (1 << (coeff_bit_width - 1)) - 1) if invert else v   # Negate, Saturate


def twiddle_table(coeffs, fft_size, coeff_bit_width, *, step_period, coeffs_bit_limit,
                  coeff_sharing, coeff_decimation, coeff_generation, latency_sum, cal_bits):
    """[(re_int, im_int), ...] quantized signed integers, one per Coeffs entry,
    as casper's coeff_gen outputs them (see the module docstring). The keyword
    arguments are the twiddle's casper parameters; latency_sum = mult + add +
    conv latency (add 2 with dsp48_adders)."""
    if len(coeffs) == 1:
        return [(quantize_const(w.real, coeff_bit_width), quantize_const(w.imag, coeff_bit_width))
                for w in twiddle_values(coeffs, fft_size)]
    lay = cosin_layout(coeffs, fft_size, coeff_bit_width, step_period, coeffs_bit_limit,
                       coeff_sharing, coeff_decimation, coeff_generation, latency_sum, cal_bits)
    if lay is None or (lay["inorder"] and lay["full_cycle_bits"] - lay["table_bits"] != 1):
        # no cosin, or an in-order list whose cosin angles 2*pi*bit_rev(k)/2^(table_bits +
        # multiple_bits) are not the Coeffs formula (only multiple_bits = 1, the biplex
        # case, agrees): the formula values, exactly rounded
        return [(quantize_coeff(w.real, coeff_bit_width), quantize_coeff(w.imag, coeff_bit_width))
                for w in twiddle_values(coeffs, fft_size)]
    tb = lay["table_bits"]
    table = []
    for k in range(len(coeffs)):
        theta = bit_rev(k, tb) if lay["inorder"] else k
        table.append(tuple(_cosin_word(theta, lay, i, coeff_bit_width) for i in range(2)))
    return table


COEFF_KEYS = ("COEFFS_BIT_LIMIT", "COEFF_SHARING", "COEFF_DECIMATION", "COEFF_GENERATION",
              "CAL_BITS", "DSP48_ADDERS")


def _defaults(limit, generation):
    return dict(COEFFS_BIT_LIMIT=limit, COEFF_SHARING=1, COEFF_DECIMATION=1,
                COEFF_GENERATION=generation, CAL_BITS=1, DSP48_ADDERS=0)


# per-module RTL defaults of COEFF_KEYS (= the casper mask defaults); fft_stage_n
# (and so biplex_core) passes coeff_generation 'off' (fft_stage_n_init.m:501)
COEFF_DEFAULTS = {
    "twiddle_general": _defaults(9, 1), "butterfly_direct": _defaults(8, 1),
    "fft_stage_n": _defaults(8, 0), "biplex_core": _defaults(8, 0),
    "fft_biplex_real_4x": _defaults(8, 0), "fft_direct": _defaults(9, 1),
    "fft_wideband_real": _defaults(8, 1),
}


def coeff_params(p, defaults):
    """The COEFF_KEYS of a module's parameters p, missing ones from defaults
    (the module's RTL / casper mask defaults)."""
    return {k: p.get(k, defaults[k]) for k in COEFF_KEYS}


def coeff_options(p, step_period):
    """twiddle_table keyword arguments from HDL parameters p, which must hold
    COEFF_KEYS (see coeff_params) and MULT / ADD / CONV_LATENCY."""
    add = 2 if p["DSP48_ADDERS"] else p["ADD_LATENCY"]
    return dict(step_period=step_period, coeffs_bit_limit=p["COEFFS_BIT_LIMIT"],
                coeff_sharing=p["COEFF_SHARING"], coeff_decimation=p["COEFF_DECIMATION"],
                coeff_generation=p["COEFF_GENERATION"],
                latency_sum=p["MULT_LATENCY"] + add + p["CONV_LATENCY"],
                cal_bits=p["CAL_BITS"])


def mem_lines(table, coeff_bit_width):
    """.mem rows: {re, im} packed as one 2*coeff_bit_width-bit hex word."""
    mask = (1 << coeff_bit_width) - 1
    digits = (2 * coeff_bit_width + 3) // 4
    return [f"{((re & mask) << coeff_bit_width) | (im & mask):0{digits}x}"
            for re, im in table]


def write_mem(path, coeffs, fft_size, coeff_bit_width, **options):
    table = twiddle_table(coeffs, fft_size, coeff_bit_width, **options)
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
    ap.add_argument("--step-period", type=int, default=0, help="STEP_PERIOD (default 0)")
    ap.add_argument("--coeffs-bit-limit", type=int, default=9,
                    help="COEFFS_BIT_LIMIT (default 9, twiddle_general's)")
    ap.add_argument("--coeff-sharing", type=int, default=1, help="COEFF_SHARING (default 1)")
    ap.add_argument("--coeff-decimation", type=int, default=1, help="COEFF_DECIMATION (default 1)")
    ap.add_argument("--coeff-generation", type=int, default=1, help="COEFF_GENERATION (default 1)")
    ap.add_argument("--latency-sum", type=int, default=4,
                    help="MULT_LATENCY + ADD_LATENCY + CONV_LATENCY (default 4)")
    ap.add_argument("--cal-bits", type=int, default=1, help="CAL_BITS (default 1)")
    ap.add_argument("-o", "--output", required=True, help="output .mem file")
    args = ap.parse_args()
    if args.fft_size < 1:
        ap.error("--fft-size must be >= 1")
    if any(c < 0 or c >= 2 ** (args.fft_size - 1) for c in args.coeffs):
        ap.error(f"coefficient indices must be in 0 .. 2^(fft-size-1)-1 = {2 ** (args.fft_size - 1) - 1}")
    write_mem(args.output, args.coeffs, args.fft_size, args.coeff_bit_width,
              step_period=args.step_period, coeffs_bit_limit=args.coeffs_bit_limit,
              coeff_sharing=args.coeff_sharing, coeff_decimation=args.coeff_decimation,
              coeff_generation=args.coeff_generation, latency_sum=args.latency_sum,
              cal_bits=args.cal_bits)
    print(f"wrote {len(args.coeffs)} coefficients to {args.output} "
          f"(twiddle_general: N_COEFFS={len(args.coeffs)}, "
          f"COEFF_BIT_WIDTH={args.coeff_bit_width}, FFT_SIZE={args.fft_size})")


if __name__ == "__main__":
    main()
