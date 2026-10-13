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
                         words, one value per clock cycle; sets with MISC = 1
                         add sim_misci.csv (random MISC_WIDTH-bit words) and
                         sim_misco.csv (misci delayed by the casper misc latency)
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


def convert_overflow(p, din):
    """casper convert_of overflow rule (bus_convert of = on): the top
    wb_lost+1 bits of din are not all equal; never when wb_lost <= 0."""
    n_in = p["N_BITS_IN"]
    wb_lost = (n_in - p["BIN_PT_IN"]) - (p["N_BITS_OUT"] - p["BIN_PT_OUT"])
    if wb_lost <= 0:
        return 0
    n_top = min(wb_lost + 1, n_in)
    top = din >> (n_in - n_top)
    return int(top not in (0, (1 << n_top) - 1))


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


def en_stream(rng, n):
    """Random enable for async sets: ~70 % high, with a few longer en = 0 runs."""
    en = [1 if rng.random() < 0.75 else 0 for _ in range(n)]
    for start in (n // 4, n // 2, 3 * n // 4):
        en[start:start + 6] = [0] * 6
    return en


def gated(values, en, latency, zero):
    """Xilinx latency chain with an en port: it only advances while en = 1.

    Pre-edge read convention as delayed(); latency 0 is combinational.
    """
    if latency == 0:
        return delayed(values, 0, zero)
    chain, out = [zero] * latency, []
    for v, e in zip(values, en):
        out.append(chain[-1])
        if e:
            chain = [v] + chain[:-1]
    return out


def m_cmult_async(p, a, b, en):
    """cmult with async = on (cmult_init.m): every Mult / AddSub / Convert is
    gated by the en aligned to its input when pipelined_enable is on (en
    delayed in, mult, add latency), by the raw en otherwise (in_latency forced
    to 0, no dvalid). dvalid = en delayed in + mult + add + conv, aligned with
    ab: the intended behaviour. casper's den Delay takes the add latency
    instead (cmult_init.m:532-535, 623-627; mlib_devel bug 13)."""
    na, nb, nab = p["N_BITS_A"], p["N_BITS_B"], p["N_BITS_AB"]
    pe = p["PIPELINED_ENABLE"]
    il = p["IN_LATENCY"] if pe else 0
    ml, al, cl = p["MULT_LATENCY"], p["ADD_LATENCY"], p["CONV_LATENCY"]
    a_d, b_d = delayed(a, il, 0), delayed(b, il, 0)
    e1 = delayed(en, il, 0) if pe else en
    e2 = delayed(e1, ml, 0) if pe else en
    e3 = delayed(e2, al, 0) if pe else en
    prods = []
    for x, y in zip(a_d, b_d):
        ar, ai = (to_value(t, na, p["BIN_PT_A"], 1) for t in unpack(x, na))
        br, bi = (to_value(t, nb, p["BIN_PT_B"], 1) for t in unpack(y, nb))
        prods.append((ar * br, ai * bi, ai * br, ar * bi))
    m = gated(prods, e1, ml, (0, 0, 0, 0))
    sums = [((rr + ii, ir - ri) if p["CONJUGATED"] else (rr - ii, ir + ri)) for rr, ii, ir, ri in m]
    s = gated(sums, e2, al, (0, 0))
    q = (nab, p["BIN_PT_AB"], 1, p["QUANTIZATION"], p["OVERFLOW"])
    conv = [(quantize(re, *q) << nab) | quantize(im, *q) for re, im in s]
    out = {"ab": gated(conv, e3, cl, 0)}
    if pe:
        out["dvalid"] = delayed(e3, cl, 0)
    return out


def with_misc(params, width):
    """params plus the casper misc pass-through (MISC = 1, MISC_WIDTH = width)."""
    return dict(params, MISC=1, MISC_WIDTH=width)


# Parameter names follow the casper_library masks (upper case): the Bus
# blocks' latency is csp_latency (bus_mult: mult_latency); scale keeps the
# Xilinx Convert-style LATENCY of its HDL-only requantizer.
CONV = ["N_BITS_IN", "BIN_PT_IN", "TYPE_IN", "N_BITS_OUT", "BIN_PT_OUT",
        "TYPE_OUT", "QUANTIZATION", "OVERFLOW", "CSP_LATENCY"]
ADDSUB = ["N_BITS_A", "BIN_PT_A", "TYPE_A", "N_BITS_B", "BIN_PT_B", "TYPE_B",
          "N_BITS_OUT", "BIN_PT_OUT", "TYPE_OUT", "OPMODE", "QUANTIZATION",
          "OVERFLOW", "CSP_LATENCY"]
MULT = ["N_BITS_A", "BIN_PT_A", "TYPE_A", "N_BITS_B", "BIN_PT_B", "TYPE_B",
        "N_BITS_OUT", "BIN_PT_OUT", "TYPE_OUT", "QUANTIZATION", "OVERFLOW",
        "MULT_LATENCY"]
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
        latency=lambda p: p["CSP_LATENCY"], latency_name="CSP_LATENCY",
        misc_latency=lambda p: p["CSP_LATENCY"],          # bus_convert_init.m:281-285
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
            (P(CONV, [8, 0, 1, 12, 2, 1, 0, 0, 0]),
             "Fix_8_0 → Fix_12_2, same shift as set 6 (exact ×4), Simulink-buildable"),
            (with_misc(P(CONV, [16, 8, 1, 8, 4, 1, 2, 1, 2]), 3),
             "set 2 with misc: 3-bit misci → misco, delayed CSP_LATENCY"),
            (dict(P(CONV, [16, 8, 1, 8, 4, 1, 1, 1, 1]), OF=1),
             "set 1 with of: overflow flags 4 dropped integer bits (casper convert_of rule)"),
            (dict(P(CONV, [8, 4, 0, 10, 6, 1, 0, 0, 0]), OF=1),
             "set 3 with of, combinational: bit growth, overflow always 0"),
        ]),
    "adder_subtractor": dict(
        category="Bus",
        model=m_adder_subtractor, inputs=["a", "b"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_A"], p["N_BITS_B"]],
        latency=lambda p: p["CSP_LATENCY"], latency_name="CSP_LATENCY",
        misc_latency=lambda p: p["CSP_LATENCY"],          # bus_addsub_init.m:443-447
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
            (with_misc(P(ADDSUB, [8, 0, 0, 8, 0, 0, 9, 0, 1, 1, 0, 0, 2]), 4),
             "set 3 with misc: 4-bit misci → misco, delayed CSP_LATENCY"),
            (dict(P(ADDSUB, [8, 0, 0, 8, 0, 0, 9, 0, 1, 1, 0, 0, 2]), ASYNC=1),
             "set 3 async: random en stalls the AddSub chain, dvalid = en delayed CSP_LATENCY"),
            (dict(P(ADDSUB, [8, 4, 1, 8, 4, 1, 8, 4, 1, 0, 0, 1, 1]), ASYNC=1),
             "set 1 async, CSP_LATENCY 1"),
        ]),
    "multiplier": dict(
        category="Bus",
        model=m_multiplier, inputs=["a", "b"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_A"], p["N_BITS_B"]],
        latency=lambda p: p["MULT_LATENCY"], latency_name="MULT_LATENCY",
        misc_latency=lambda p: p["MULT_LATENCY"],         # bus_mult_init.m:701-711 (fan_latency 0)
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
            (with_misc(P(MULT, [12, 11, 1, 6, 6, 0, 8, 7, 1, 1, 0, 2]), 5),
             "set 3 with misc: 5-bit misci → misco, delayed MULT_LATENCY"),
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
              "identical apart from the latency shift. Set 7 also drives random "
              "`sim_a_tvalid.csv` / `sim_b_tvalid.csv` (80 % high) and expects "
              "`sim_dout_tvalid.csv` = `a_tvalid & b_tvalid` delayed by the "
              "latency; the data path ignores the valids (no AXI blocking). "
              "The other sets leave both valids at 1.",
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
            (P(CMULT, [12, 11, 1, 10, 9, 1, 13, 10, 1, 0, 1, 0, 2, 1]),
             "Fix_12_11 × Fix_10_9 → Fix_13_10, truncate + saturate, 4-mult, "
             "random a_tvalid / b_tvalid (dout_tvalid = both, delayed)"),
        ],
        # sets that drive a_tvalid / b_tvalid and check dout_tvalid
        tvalid_sets={7}),
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
            (dict(P(CM, [8, 7, 12, 11, 10, 7, 1, 1, 2, 1, 2, 1, 1, 0, 0, 2]), ASYNC=1, PIPELINED_ENABLE=1),
             "set 5 async, pipelined_enable on: each stage gated by its aligned en; "
             "dvalid = en delayed in + mult + add + conv (bug 13 fixed: aligned with ab)"),
            (dict(P(CM, [18, 17, 18, 17, 37, 14, 0, 0, 3, 1, 1, 0, 0, 0, 0, 2]), ASYNC=1, PIPELINED_ENABLE=0),
             "set 0 async, pipelined_enable off: every stage gated by the raw en, no dvalid"),
        ]),
    "scale": dict(
        category="Bus",
        model=m_scale, inputs=["din"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_IN"]],
        latency=lambda p: p["LATENCY"],
        misc_latency=lambda p: 0,                         # bus_scale_init.m:159-164
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
            (with_misc(P(SCALE, [16, 8, 1, -3, 16, 11, 1, 0, 0, 0]), 4),
             "Fix_16_8 ÷ 8 as a pure reinterpretation to Fix_16_11 (the bus_scale-equivalent "
             "format, LATENCY 0), with misc: 4-bit misci → misco undelayed"),
        ]),
    "negate": dict(
        category="Bus",
        model=m_negate, inputs=["din"], outputs=["dout"],
        widths=lambda p: [p["N_BITS_IN"]],
        latency=lambda p: p["CSP_LATENCY"], latency_name="CSP_LATENCY",
        misc_latency=lambda p: p["CSP_LATENCY"],          # bus_negate_init.m:226-230
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
            (with_misc(P(CONV, [8, 4, 1, 8, 4, 1, 0, 1, 1]), 2),
             "set 1 with misc (the bus_negate-equivalent format): 2-bit misci → misco, delayed CSP_LATENCY"),
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
        en = en_stream(random.Random(f"{name}-{n}-en"), len(vecs)) if params.get("ASYNC") else None
        if en is not None:
            (d / "sim_en.csv").write_text("".join(f"{x}\n" for x in en))
        if en is not None and name == "cmult":
            outs = m_cmult_async(params, [v[0] for v in vecs], [v[1] for v in vecs], en)
            for port, col in outs.items():
                (d / f"sim_{port}.csv").write_text("".join(f"{x}\n" for x in col))
        for k, port in enumerate(spec["outputs"]):
            if en is not None and name == "cmult":
                break
            zero = spec["model"](params, (0,) * len(spec["inputs"]))[k]
            col = (gated([r[k] for r in results], en, lat, zero) if en is not None
                   else delayed([r[k] for r in results], lat, zero))
            (d / f"sim_{port}.csv").write_text("".join(f"{x}\n" for x in col))
        if en is not None and name != "cmult":
            # dvalid = en through a free Delay of the latency (bus_addsub den)
            (d / "sim_dvalid.csv").write_text("".join(f"{x}\n" for x in delayed(en, lat, 0)))
        if n in spec.get("tvalid_sets", ()):
            trng = random.Random(f"{name}-{n}-tvalid")
            a_tv = [int(trng.random() < 0.8) for _ in vecs]
            b_tv = [int(trng.random() < 0.8) for _ in vecs]
            tv = delayed([a & b for a, b in zip(a_tv, b_tv)], lat, 0)
            for port, col in (("a_tvalid", a_tv), ("b_tvalid", b_tv), ("dout_tvalid", tv)):
                (d / f"sim_{port}.csv").write_text("".join(f"{x}\n" for x in col))
        if params.get("OF"):
            of = delayed([convert_overflow(params, v[0]) for v in vecs], lat,
                         convert_overflow(params, 0))
            (d / "sim_overflow.csv").write_text("".join(f"{x}\n" for x in of))
        if params.get("MISC"):
            mrng = random.Random(f"{name}-{n}-misc")
            misci = [mrng.randrange(1 << params["MISC_WIDTH"]) for _ in vecs]
            misco = delayed(misci, spec["misc_latency"](params), 0)
            (d / "sim_misci.csv").write_text("".join(f"{x}\n" for x in misci))
            (d / "sim_misco.csv").write_text("".join(f"{x}\n" for x in misco))
    (mdir / "test_data.md").write_text(test_data_md(name, spec))


MISC_DEFAULTS = {"MISC": 0, "MISC_WIDTH": 1, "OF": 0, "ASYNC": 0, "PIPELINED_ENABLE": 1}


def test_data_md(name, spec):
    keys = list(dict.fromkeys(k for params, _ in spec["tests"] for k in params))
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
        f"the pipeline latency (the first `{spec.get('latency_name', 'LATENCY')}` values are the zero "
        "power-on state)."
        + (" Sets with `MISC` = 1 also drive random `MISC_WIDTH`-bit words on "
           "`sim_misci.csv` and expect them on `sim_misco.csv`, delayed by the "
           "casper misc latency; the other sets leave `MISC` at its default 0 "
           "(no misc files, not in `params.json`)."
           if any(params.get("MISC") for params, _ in spec["tests"]) else "")
        + (" Sets with `ASYNC` = 1 drive a random `sim_en.csv` (about 70 % "
           "high, with a few 6-cycle gaps) and expect `sim_dvalid.csv`; they "
           "follow casper's async mode, checked against Simulink (MATLAB "
           "R2021a): see the module documentation."
           if any(params.get("ASYNC") for params, _ in spec["tests"]) else "")
        + (" Sets with `OF` = 1 also expect `sim_overflow.csv`: casper "
           "`convert_of`'s flag (the top wb_lost+1 bits of `din` not all "
           "equal, wb_lost = dropped integer bits), with the same latency."
           if any(params.get("OF") for params, _ in spec["tests"]) else ""),
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
        vals = " | ".join(str(params.get(k, MISC_DEFAULTS.get(k))) for k in keys)
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
