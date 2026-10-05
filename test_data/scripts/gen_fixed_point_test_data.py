#!/usr/bin/env python3
"""Generate test data for the fixed-point modules in rtl/Bus/ and rtl/Multipliers/.

Complex words of cmult are packed {re, im} (real part in the MSBs).

The expected outputs come from an exact golden model (Python Fraction
arithmetic followed by explicit quantization / overflow rules), independent
of the bit-level tricks used in the RTL.

For every module this writes, under test_data/<Category>/<module>/:
  simdataN/params.json   DUT parameters of test N (the testbench uses it to
                         find the data set matching the DUT it is running)
  simdataN/sim_*.csv     raw (unsigned bit-pattern) input / expected output
                         words, one value per clock cycle
  test_data.md           table of all test configurations

and prints the matching [[simulations]] blocks for tests/simulation.toml.

Usage:
  python3 test_data/scripts/gen_fixed_point_test_data.py            # all modules
  python3 test_data/scripts/gen_fixed_point_test_data.py --module convert

Encodings (identical to the RTL):
  TYPE          0 = unsigned, 1 = signed
  QUANTIZATION  0 = truncate, 1 = round half away from zero, 2 = round half to even
  OVERFLOW      0 = wrap, 1 = saturate
"""

import json
import math
import random
from fractions import Fraction
from pathlib import Path

from common import TEST_DATA_ROOT as TEST_DATA, run_cli

SCRIPT = Path(__file__).name
CYCLES = 128

QUANT_NAMES = {0: "truncate", 1: "round ±inf", 2: "round even"}
OVF_NAMES = {0: "wrap", 1: "saturate"}


# ── fixed-point golden model ────────────────────────────────────────────────

def to_value(raw, n_bits, bin_pt, signed):
    """Raw bit pattern -> exact real value."""
    if signed and raw >= 1 << (n_bits - 1):
        raw -= 1 << n_bits
    return Fraction(raw) / Fraction(2) ** bin_pt


def quantize(value, n_bits, bin_pt, signed, quant, ovf):
    """Exact real value -> raw bit pattern of the output format."""
    x = value * Fraction(2) ** bin_pt
    if quant == 0:
        q = math.floor(x)
    elif quant == 1:
        q = math.floor(abs(x) + Fraction(1, 2))
        q = q if x >= 0 else -q
    else:
        q = round(x)  # Fraction.__round__ rounds half to even
    lo = -(1 << (n_bits - 1)) if signed else 0
    hi = (1 << (n_bits - 1)) - 1 if signed else (1 << n_bits) - 1
    if ovf == 1:
        q = min(max(q, lo), hi)
    return q % (1 << n_bits)


def fmt(n_bits, bin_pt, signed):
    return f"{'Fix' if signed else 'UFix'}_{n_bits}_{bin_pt}"


# ── stimulus ────────────────────────────────────────────────────────────────

def corners(n_bits):
    """Raw corner-case words: 0, 1, all-ones, MSB-only, MSB-1, MSB+1."""
    m = 1 << (n_bits - 1)
    return [0, 1, (1 << n_bits) - 1, m, m - 1, m + 1]


def stimulus(rng, widths):
    """CYCLES tuples of raw words, one per input port.

    The first cycles walk the corner cases of every input simultaneously
    (and all pairs of corners for 2-input modules); the rest are uniform
    random words.
    """
    cs = [corners(w) for w in widths]
    vecs = []
    if len(widths) == 2:
        vecs = [(x, y) for x in cs[0] for y in cs[1]]
    else:
        k = max(len(c) for c in cs)
        vecs = [tuple(c[i % len(c)] for c in cs) for i in range(k)]
    while len(vecs) < CYCLES:
        vecs.append(tuple(rng.randrange(1 << w) for w in widths))
    return vecs[:CYCLES]


def delayed(values, latency, zero_result):
    """Pre-edge read convention: cycle i observes the result of input i-L.

    The first L cycles show the zero power-on state of the pipeline. With
    L = 0 (combinational), cycle 0 still shows the result for all-zero
    inputs, because the first clock edge happens at t = 0, before the first
    input value reaches the output.
    """
    if latency == 0:
        return [zero_result] + values[1:]
    return [0] * latency + values[: len(values) - latency]


# ── per-module models ───────────────────────────────────────────────────────

def m_convert(p, v):
    (din,) = v
    x = to_value(din, p["N_BITS_IN"], p["BIN_PT_IN"], p["TYPE_IN"])
    return [quantize(x, p["N_BITS_OUT"], p["BIN_PT_OUT"], p["TYPE_OUT"],
                     p["QUANTIZATION"], p["OVERFLOW"])]


def m_adder_subtractor(p, v):
    a = to_value(v[0], p["N_BITS_A"], p["BIN_PT_A"], p["TYPE_A"])
    b = to_value(v[1], p["N_BITS_B"], p["BIN_PT_B"], p["TYPE_B"])
    r = a + b if p["OPMODE"] == 0 else a - b
    return [quantize(r, p["N_BITS_OUT"], p["BIN_PT_OUT"], p["TYPE_OUT"],
                     p["QUANTIZATION"], p["OVERFLOW"])]


def m_multiplier(p, v):
    a = to_value(v[0], p["N_BITS_A"], p["BIN_PT_A"], p["TYPE_A"])
    b = to_value(v[1], p["N_BITS_B"], p["BIN_PT_B"], p["TYPE_B"])
    return [quantize(a * b, p["N_BITS_OUT"], p["BIN_PT_OUT"], p["TYPE_OUT"],
                     p["QUANTIZATION"], p["OVERFLOW"])]


def m_complex_multiplier(p, v):
    ar, ai = (to_value(x, p["N_BITS_A"], p["BIN_PT_A"], p["TYPE_A"]) for x in v[0:2])
    br, bi = (to_value(x, p["N_BITS_B"], p["BIN_PT_B"], p["TYPE_B"]) for x in v[2:4])
    q = (p["N_BITS_OUT"], p["BIN_PT_OUT"], p["TYPE_OUT"], p["QUANTIZATION"], p["OVERFLOW"])
    return [quantize(ar * br - ai * bi, *q), quantize(ar * bi + ai * br, *q)]


def unpack(word, n_bits):
    """Packed {re, im} word -> (re, im) raw words."""
    return word >> n_bits, word & ((1 << n_bits) - 1)


def m_cmult(p, v):
    na, nb, nab = p["N_BITS_A"], p["N_BITS_B"], p["N_BITS_AB"]
    ar, ai = (to_value(x, na, p["BIN_PT_A"], 1) for x in unpack(v[0], na))
    br, bi = (to_value(x, nb, p["BIN_PT_B"], 1) for x in unpack(v[1], nb))
    if p["CONJUGATED"]:
        re, im = ar * br + ai * bi, ai * br - ar * bi
    else:
        re, im = ar * br - ai * bi, ai * br + ar * bi
    q = (nab, p["BIN_PT_AB"], 1, p["QUANTIZATION"], p["OVERFLOW"])
    return [(quantize(re, *q) << nab) | quantize(im, *q)]


def cmult_vectors(rng, p):
    """Packed (a, b) words: component corner cases, then random words.

    Every pair of component corners appears as (a_re, a_im), with b both
    swapped and equal, so -2^(n-1) meets -2^(n-1) in every product.
    """
    na, nb = p["N_BITS_A"], p["N_BITS_B"]
    ca, cb = corners(na), corners(nb)
    vecs = []
    for i in range(len(ca)):
        for j in range(len(ca)):
            a = (ca[i] << na) | ca[j]
            vecs.append((a, (cb[j % len(cb)] << nb) | cb[i % len(cb)]))
            vecs.append((a, (cb[i % len(cb)] << nb) | cb[j % len(cb)]))
    while len(vecs) < CYCLES:
        vecs.append((rng.randrange(1 << 2 * na), rng.randrange(1 << 2 * nb)))
    return vecs[:CYCLES]


def cmult_total_latency(p):
    pipe = p["PIPELINE_LATENCY"] if (p["MULTIPLIER_IMPLEMENTATION"] == 2
                                     and p["PIPELINE_CMULT_EN"]) else 0
    return p["IN_LATENCY"] + p["MULT_LATENCY"] + pipe + p["ADD_LATENCY"] + p["CONV_LATENCY"]


def m_scale(p, v):
    x = to_value(v[0], p["N_BITS_IN"], p["BIN_PT_IN"], p["TYPE_IN"])
    x *= Fraction(2) ** p["SCALE_FACTOR"]
    return [quantize(x, p["N_BITS_OUT"], p["BIN_PT_OUT"], p["TYPE_OUT"],
                     p["QUANTIZATION"], p["OVERFLOW"])]


def m_negate(p, v):
    x = to_value(v[0], p["N_BITS_IN"], p["BIN_PT_IN"], p["TYPE_IN"])
    return [quantize(-x, p["N_BITS_OUT"], p["BIN_PT_OUT"], p["TYPE_OUT"],
                     p["QUANTIZATION"], p["OVERFLOW"])]


def cmult_latency(p):
    if p["MULT_SPEC"] == 0:
        return p["MULT_LATENCY"] + p["ADD_LATENCY"]
    return p["MULT_LATENCY"] + 2 * p["ADD_LATENCY"]


# ── test configurations ─────────────────────────────────────────────────────

def P(names, values):
    return dict(zip(names, values))


CONV = ["N_BITS_IN", "BIN_PT_IN", "TYPE_IN", "N_BITS_OUT", "BIN_PT_OUT",
        "TYPE_OUT", "QUANTIZATION", "OVERFLOW", "LATENCY"]
ADDSUB = ["N_BITS_A", "BIN_PT_A", "TYPE_A", "N_BITS_B", "BIN_PT_B", "TYPE_B",
          "N_BITS_OUT", "BIN_PT_OUT", "TYPE_OUT", "OPMODE", "QUANTIZATION",
          "OVERFLOW", "LATENCY"]
MULT = ["N_BITS_A", "BIN_PT_A", "TYPE_A", "N_BITS_B", "BIN_PT_B", "TYPE_B",
        "N_BITS_OUT", "BIN_PT_OUT", "TYPE_OUT", "QUANTIZATION", "OVERFLOW",
        "LATENCY"]
CMULT = ["N_BITS_A", "BIN_PT_A", "TYPE_A", "N_BITS_B", "BIN_PT_B", "TYPE_B",
         "N_BITS_OUT", "BIN_PT_OUT", "TYPE_OUT", "QUANTIZATION", "OVERFLOW",
         "MULT_SPEC", "MULT_LATENCY", "ADD_LATENCY"]
CM = ["N_BITS_A", "BIN_PT_A", "N_BITS_B", "BIN_PT_B", "N_BITS_AB", "BIN_PT_AB",
      "QUANTIZATION", "OVERFLOW", "MULT_LATENCY", "ADD_LATENCY", "CONV_LATENCY",
      "IN_LATENCY", "CONJUGATED", "MULTIPLIER_IMPLEMENTATION", "PIPELINE_CMULT_EN",
      "PIPELINE_LATENCY"]
SCALE = ["N_BITS_IN", "BIN_PT_IN", "TYPE_IN", "SCALE_FACTOR", "N_BITS_OUT",
         "BIN_PT_OUT", "TYPE_OUT", "QUANTIZATION", "OVERFLOW", "LATENCY"]

# category: the module's casper_library (Simulink) category, which is also
# its directory under rtl/, test_data/, testbench/ and docs/.
MODULES = {
    "convert": dict(
        category="Bus",
        model=m_convert, inputs=["din"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_IN"]],
        latency=lambda p: p["LATENCY"],
        prose="`convert` requantizes `din` from the input fixed-point format "
              "to the output format.",
        tests=[
            (P(CONV, [16, 8, 1, 8, 4, 1, 0, 0, 0]),
             "Fix_16_8 → Fix_8_4, truncate + wrap, combinational"),
            (P(CONV, [16, 8, 1, 8, 4, 1, 1, 1, 1]),
             "Fix_16_8 → Fix_8_4, round half away from zero + saturate"),
            (P(CONV, [16, 8, 1, 8, 4, 1, 2, 1, 2]),
             "Fix_16_8 → Fix_8_4, round half to even + saturate, 2-stage pipeline"),
            (P(CONV, [8, 4, 0, 10, 6, 1, 0, 0, 1]),
             "UFix_8_4 → Fix_10_6, exact bit growth (unsigned → signed)"),
            (P(CONV, [12, 10, 1, 8, 4, 0, 1, 1, 1]),
             "Fix_12_10 → UFix_8_4, round + saturate (negatives clamp to 0)"),
            (P(CONV, [16, 12, 1, 8, 4, 1, 2, 0, 1]),
             "Fix_16_12 → Fix_8_4, round half to even + wrap"),
            (P(CONV, [8, -2, 1, 12, 0, 1, 0, 0, 0]),
             "Fix_8_-2 → Fix_12_0, negative input binary point (exact ×4)"),
        ]),
    "adder_subtractor": dict(
        category="Bus",
        model=m_adder_subtractor, inputs=["a", "b"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_A"], p["N_BITS_B"]],
        latency=lambda p: p["LATENCY"],
        prose="`adder_subtractor` computes `a + b` (`OPMODE`=0) or `a - b` "
              "(`OPMODE`=1) and requantizes to the output format.",
        tests=[
            (P(ADDSUB, [8, 4, 1, 8, 4, 1, 9, 4, 1, 0, 0, 0, 0]),
             "Fix_8_4 + Fix_8_4 → Fix_9_4, full precision, combinational"),
            (P(ADDSUB, [8, 4, 1, 8, 4, 1, 8, 4, 1, 0, 0, 1, 1]),
             "Fix_8_4 + Fix_8_4 → Fix_8_4, saturate"),
            (P(ADDSUB, [8, 4, 1, 10, 7, 1, 8, 4, 1, 1, 1, 1, 1]),
             "Fix_8_4 − Fix_10_7 → Fix_8_4, mixed binary points, round + saturate"),
            (P(ADDSUB, [8, 0, 0, 8, 0, 0, 9, 0, 1, 1, 0, 0, 2]),
             "UFix_8_0 − UFix_8_0 → Fix_9_0, unsigned subtract, 2-stage pipeline"),
            (P(ADDSUB, [16, 15, 1, 8, 8, 0, 12, 10, 1, 0, 2, 0, 1]),
             "Fix_16_15 + UFix_8_8 → Fix_12_10, signed + unsigned, round even + wrap"),
            (P(ADDSUB, [8, 4, 0, 8, 4, 0, 8, 4, 0, 1, 0, 1, 1]),
             "UFix_8_4 − UFix_8_4 → UFix_8_4, saturate (negatives clamp to 0)"),
        ]),
    "multiplier": dict(
        category="Bus",
        model=m_multiplier, inputs=["a", "b"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_A"], p["N_BITS_B"]],
        latency=lambda p: p["LATENCY"],
        prose="`multiplier` computes `a * b` and requantizes to the output format.",
        tests=[
            (P(MULT, [8, 7, 1, 8, 7, 1, 16, 14, 1, 0, 0, 0]),
             "Fix_8_7 × Fix_8_7 → Fix_16_14, full precision, combinational"),
            (P(MULT, [18, 17, 1, 18, 17, 1, 18, 17, 1, 2, 1, 3]),
             "Fix_18_17 × Fix_18_17 → Fix_18_17, round even + saturate (−1×−1)"),
            (P(MULT, [8, 0, 0, 8, 4, 1, 17, 4, 1, 0, 0, 1]),
             "UFix_8_0 × Fix_8_4 → Fix_17_4, unsigned × signed, exact"),
            (P(MULT, [12, 11, 1, 6, 6, 0, 8, 7, 1, 1, 0, 2]),
             "Fix_12_11 × UFix_6_6 → Fix_8_7, round + wrap, 2-stage pipeline"),
            (P(MULT, [8, 4, 1, 8, 4, 1, 8, 4, 1, 0, 1, 1]),
             "Fix_8_4 × Fix_8_4 → Fix_8_4, truncate + saturate"),
        ]),
    "complex_multiplier": dict(
        category="Multipliers",
        model=m_complex_multiplier,
        inputs=["a_re", "a_im", "b_re", "b_im"], outputs=["dout_re", "dout_im"],
        widths=lambda p: [p["N_BITS_A"]] * 2 + [p["N_BITS_B"]] * 2,
        latency=cmult_latency,
        prose="`complex_multiplier` computes `(a_re + j·a_im)(b_re + j·b_im)` and "
              "requantizes both output parts. Tests are paired so that each "
              "format is exercised with both `MULT_SPEC`=0 (4-multiply) and "
              "`MULT_SPEC`=1 (3-multiply); the expected values of a pair are "
              "identical apart from the latency shift.",
        tests=[
            (P(CMULT, [8, 7, 1, 8, 7, 1, 17, 14, 1, 0, 0, 0, 2, 1]),
             "Fix_8_7 × Fix_8_7 → Fix_17_14, exact, 4-mult"),
            (P(CMULT, [8, 7, 1, 8, 7, 1, 17, 14, 1, 0, 0, 1, 2, 1]),
             "Fix_8_7 × Fix_8_7 → Fix_17_14, exact, 3-mult"),
            (P(CMULT, [18, 17, 1, 18, 17, 1, 18, 17, 1, 2, 1, 0, 3, 2]),
             "Fix_18_17 twiddle-style, round even + saturate, 4-mult"),
            (P(CMULT, [18, 17, 1, 18, 17, 1, 18, 17, 1, 2, 1, 1, 3, 2]),
             "Fix_18_17 twiddle-style, round even + saturate, 3-mult"),
            (P(CMULT, [8, 4, 0, 8, 6, 1, 14, 8, 1, 1, 0, 0, 1, 1]),
             "UFix_8_4 × Fix_8_6 → Fix_14_8, round + wrap, 4-mult"),
            (P(CMULT, [8, 4, 0, 8, 6, 1, 14, 8, 1, 1, 0, 1, 1, 1]),
             "UFix_8_4 × Fix_8_6 → Fix_14_8, round + wrap, 3-mult"),
            (P(CMULT, [8, 7, 1, 8, 7, 1, 10, 7, 1, 1, 1, 1, 0, 0]),
             "Fix_8_7 → Fix_10_7, round + saturate, 3-mult, fully combinational"),
        ]),
    "cmult": dict(
        category="Multipliers",
        model=m_cmult, inputs=["a", "b"], outputs=["ab"],
        widths=lambda p: [2 * p["N_BITS_A"], 2 * p["N_BITS_B"]],
        vectors=cmult_vectors,
        stimulus_note="The first 72 cycles walk every pair of per-part corner cases "
                      "(0, 1, all-ones, MSB only, MSB−1, MSB+1) as (a_re, a_im), with "
                      "b set to the swapped and the same pair, so −2^(n−1) meets "
                      "−2^(n−1) in every product. The rest are seeded uniform-random "
                      "words.",
        latency=cmult_total_latency,
        prose="`cmult` (casper_library cmult) computes `a·b` (`CONJUGATED`=0) or "
              "`a·conj(b)` (`CONJUGATED`=1) on packed `{re, im}` words (real part "
              "in the MSBs) and converts both parts to `N_BITS_AB`/`BIN_PT_AB`. "
              "Latency = `IN_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY` "
              "(+ `PIPELINE_LATENCY` with embedded multipliers and "
              "`PIPELINE_CMULT_EN`). Sets 2 and 3 are the full-precision "
              "`cmult_4bit_hdl*` / `cmult_4bit_hdl` equivalents.",
        tests=[
            (P(CM, [18, 17, 18, 17, 37, 14, 0, 0, 3, 1, 1, 0, 0, 0, 0, 2]),
             "cmult_init.m defaults: Fix_18_17 → Fix_37_14, truncate + wrap"),
            (P(CM, [18, 17, 18, 17, 37, 14, 0, 0, 3, 1, 1, 0, 1, 0, 0, 2]),
             "Defaults, conjugated (a·conj(b))"),
            (P(CM, [4, 3, 4, 3, 9, 6, 0, 0, 1, 0, 0, 0, 1, 0, 0, 2]),
             "cmult_4bit_hdl* equivalent: Fix_4_3, full precision Fix_9_6, conjugated, latency 1"),
            (P(CM, [4, 3, 4, 3, 9, 6, 0, 0, 1, 0, 0, 0, 0, 0, 0, 2]),
             "cmult_4bit_hdl equivalent: not conjugated, latency 1"),
            (P(CM, [8, 7, 8, 7, 17, 14, 0, 0, 0, 0, 0, 0, 1, 0, 0, 2]),
             "Fix_8_7 full precision, conjugated, fully combinational"),
            (P(CM, [8, 7, 12, 11, 10, 7, 1, 1, 2, 1, 2, 1, 1, 0, 0, 2]),
             "Fix_8_7 × Fix_12_11 → Fix_10_7, round ±inf + saturate, conjugated, IN_LATENCY 1"),
            (P(CM, [8, 7, 8, 7, 9, 6, 2, 0, 3, 1, 1, 2, 0, 0, 0, 2]),
             "Fix_8_7 → Fix_9_6, round even + wrap, IN_LATENCY 2"),
            (P(CM, [6, 5, 6, 5, 13, 10, 0, 0, 2, 1, 1, 0, 1, 2, 1, 2]),
             "Embedded multipliers + PIPELINE_CMULT_EN: 2 extra cycles"),
            (P(CM, [6, 5, 6, 5, 13, 10, 0, 0, 2, 1, 1, 0, 1, 0, 1, 3]),
             "PIPELINE_CMULT_EN with behavioral HDL: no extra latency"),
            (P(CM, [18, 17, 18, 17, 18, 17, 2, 1, 3, 1, 1, 0, 1, 0, 0, 2]),
             "Fix_18_17 → Fix_18_17, round even + saturate, conjugated"),
        ]),
    "scale": dict(
        category="Bus",
        model=m_scale, inputs=["din"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_IN"]],
        latency=lambda p: p["LATENCY"],
        prose="`scale` computes `din · 2^SCALE_FACTOR` and requantizes to the "
              "output format.",
        tests=[
            (P(SCALE, [16, 8, 1, -3, 16, 8, 1, 2, 0, 1]),
             "Fix_16_8 ÷ 8, round half to even"),
            (P(SCALE, [8, 4, 1, 2, 8, 4, 1, 0, 1, 0]),
             "Fix_8_4 × 4, saturate, combinational"),
            (P(SCALE, [8, 4, 1, 2, 8, 4, 1, 0, 0, 1]),
             "Fix_8_4 × 4, wrap"),
            (P(SCALE, [8, 8, 0, -1, 8, 8, 0, 1, 0, 2]),
             "UFix_8_8 ÷ 2, round half away from zero, 2-stage pipeline"),
            (P(SCALE, [8, 2, 1, 5, 12, 0, 1, 0, 0, 1]),
             "Fix_8_2 × 32 → Fix_12_0 (intermediate binary point −3), exact"),
            (P(SCALE, [18, 17, 1, -1, 18, 17, 1, 2, 1, 1]),
             "Fix_18_17 ÷ 2, round even + saturate (FFT stage shift)"),
        ]),
    "negate": dict(
        category="Bus",
        model=m_negate, inputs=["din"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_IN"]],
        latency=lambda p: p["LATENCY"],
        prose="`negate` computes `-din` and requantizes to the output format.",
        tests=[
            (P(CONV, [8, 4, 1, 8, 4, 1, 0, 0, 0]),
             "Fix_8_4 → Fix_8_4, wrap (−(−8) wraps to −8), combinational"),
            (P(CONV, [8, 4, 1, 8, 4, 1, 0, 1, 1]),
             "Fix_8_4 → Fix_8_4, saturate (−(−8) clamps to max)"),
            (P(CONV, [8, 4, 1, 9, 4, 1, 0, 0, 1]),
             "Fix_8_4 → Fix_9_4, full precision"),
            (P(CONV, [8, 4, 0, 9, 4, 1, 0, 0, 2]),
             "UFix_8_4 → Fix_9_4, unsigned input, 2-stage pipeline"),
            (P(CONV, [12, 8, 1, 8, 4, 1, 1, 1, 1]),
             "Fix_12_8 → Fix_8_4, round half away from zero + saturate"),
            (P(CONV, [12, 8, 1, 8, 4, 1, 2, 0, 1]),
             "Fix_12_8 → Fix_8_4, round half to even + wrap"),
        ]),
}


# ── writers ─────────────────────────────────────────────────────────────────

def write_module(name, spec):
    mdir = TEST_DATA / spec["category"] / name
    for n, (params, _) in enumerate(spec["tests"]):
        rng = random.Random(f"{name}-{n}")
        if "vectors" in spec:
            vecs = spec["vectors"](rng, params)
        else:
            vecs = stimulus(rng, spec["widths"](params))
        results = [spec["model"](params, v) for v in vecs]
        lat = spec["latency"](params)
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        (d / "params.json").write_text(json.dumps(params, indent=2) + "\n")
        for k, port in enumerate(spec["inputs"]):
            (d / f"sim_{port}.csv").write_text("".join(f"{v[k]}\n" for v in vecs))
        for k, port in enumerate(spec["outputs"]):
            zero = spec["model"](params, (0,) * len(spec["inputs"]))[k]
            col = delayed([r[k] for r in results], lat, zero)
            (d / f"sim_{port}.csv").write_text("".join(f"{x}\n" for x in col))
    (mdir / "test_data.md").write_text(test_data_md(name, spec))


def test_data_md(name, spec):
    keys = list(spec["tests"][0][0].keys())
    ins = ", ".join(f"`sim_{p}.csv`" for p in spec["inputs"])
    outs = ", ".join(f"`sim_{p}.csv`" for p in spec["outputs"])
    lines = [
        f"# {name} test data",
        "",
        spec["prose"],
        "",
        "Generated by `test_data/scripts/gen_fixed_point_test_data.py` from an exact "
        "rational-arithmetic golden model (not exported from MATLAB). Each "
        "`simdataN/` holds a `params.json` with the DUT parameters (the "
        "testbench uses it to select the data set), input words "
        f"{ins} and expected output words {outs}. All words are raw unsigned "
        "bit patterns, one per clock cycle. Expected outputs already include "
        "the pipeline latency (the first `LATENCY` values are the zero "
        "power-on state).",
        "",
        spec.get("stimulus_note",
                 "The first cycles walk corner-case words (0, 1, all-ones, MSB only, "
                 "MSB−1, MSB+1; all pairs for 2-input modules), and the rest are "
                 "seeded uniform-random words."),
        "",
        "Encodings: `TYPE` 0=unsigned, 1=signed; `QUANTIZATION` 0=truncate, "
        "1=round half away from zero, 2=round half to even; `OVERFLOW` "
        "0=wrap, 1=saturate.",
        "",
        "| Test # | Directory | " + " | ".join(keys) + " | Cycles | Description |",
        "|" + "---|" * (len(keys) + 4),
    ]
    for n, (params, desc) in enumerate(spec["tests"]):
        vals = " | ".join(str(params[k]) for k in keys)
        lines.append(f"| {n} | `simdata{n}` | {vals} | {CYCLES} | {desc} |")
    return "\n".join(lines) + "\n"


def toml_block(name, spec):
    lines = [f"# test {name}", "[[simulations]]", f'dir = "{spec["category"]}"', f'top = "{name}"',
             f'test_data_script = "{SCRIPT}"']
    for params, desc in spec["tests"]:
        lines.append(f"# {desc}")
        lines.append("[[simulations.parameters]]")
        lines += [f"{k} = {v}" for k, v in params.items()]
    return "\n".join(lines)


def generator(name):
    def gen():
        write_module(name, MODULES[name])
        return toml_block(name, MODULES[name])
    return gen


def main():
    run_cli(__doc__, {name: generator(name) for name in MODULES})


if __name__ == "__main__":
    main()
