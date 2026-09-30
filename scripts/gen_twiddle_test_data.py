#!/usr/bin/env python3
"""Generate test data for the rtl/FFTs/Twiddle/ modules.

Expected outputs come from cycle-accurate Python reference models of the
behavior derived from casper_library's twiddle_*_init.m (documented in each
RTL header), not from the RTL. twiddle_general's coefficient table is built
with scripts/gen_twiddle_coeffs.py, and its expected output is the exact
product bi · w[k] (w[k] held for 2^STEP_PERIOD cycles, schedule restarted by
every sync pulse), requantized with the Phase 1 convert rules.

For every module this writes, under test_data/FFTs/Twiddle/<module>/:
  simdataN/params.json   DUT parameters (+ COEFFS metadata for
                         twiddle_general); the testbench matches the
                         integer parameters it lists
  simdataN/sim_<port>.csv one row per clock cycle; lane ports have
                         N_INPUTS columns (lane 0 first); raw unsigned words
  simdataN/twiddle.mem   (twiddle_general) coefficient table for INIT_FILE
  test_data.md           table of all test configurations

and prints the matching [[simulations]] blocks for tests/simulation.toml.

Usage:
  python3 scripts/gen_twiddle_test_data.py            # write data, print TOML
  python3 scripts/gen_twiddle_test_data.py --toml     # print TOML only
"""

import argparse
import json
import random
import sys
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_fixed_point_test_data import quantize, to_value  # noqa: E402
from gen_twiddle_coeffs import mem_lines, twiddle_table    # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CATEGORY = "FFTs/Twiddle"
TEST_DATA = ROOT / "test_data" / CATEGORY

# INIT_FILE is relative to the simulator's working directory, which
# tests/test_runner.py makes tests/sim_build/FFTs/Twiddle/twiddle_general/.
MEM_REL = "../../../../test_data/FFTs/Twiddle/twiddle_general/simdata{n}/twiddle.mem"

LANE_IN = ["ai_re", "ai_im", "bi_re", "bi_im"]
LANE_OUT = ["ao_re", "ao_im", "bwo_re", "bwo_im"]


# ── helpers ─────────────────────────────────────────────────────────────────

def delayed(seq, latency, zero):
    """seq delayed by latency cycles; earlier cycles show the power-on value.

    With latency 0 (combinational), cycle 0 still reads the power-on value:
    the first clock edge is at t = 0, before the first input value arrives.
    """
    return [seq[t - latency] if t >= latency and t > 0 else zero for t in range(len(seq))]


def lanes_delayed(rows, latency, n):
    return delayed(rows, latency, [0] * n)


def neg_sat(raw, width):
    """Two's-complement negation with saturation (negate, OVERFLOW = 1)."""
    v = raw - (1 << width) if raw >= 1 << (width - 1) else raw
    v = min(max(-v, -(1 << (width - 1))), (1 << (width - 1)) - 1)
    return v % (1 << width)


def sync_pulses(cycles, frame, first=3):
    """Periodic sync every `frame` cycles, plus one early re-sync mid-run."""
    s = [0] * cycles
    t = first
    early_done = False
    while t < cycles:
        s[t] = 1
        if not early_done and t > cycles // 2:
            t += max(1, frame // 3 + 1)      # early sync, not on a frame boundary
            early_done = True
        else:
            t += frame
    return s


def lane_stim(rng, width, n, cycles):
    return {p: [[rng.randrange(1 << width) for _ in range(n)] for _ in range(cycles)]
            for p in LANE_IN}


# ── reference models ────────────────────────────────────────────────────────

def m_twiddle_general(p, st, table):
    n, w = p["N_INPUTS"], p["INPUT_BIT_WIDTH"]
    bp, cw = p["BIN_PT_IN"], p["COEFF_BIT_WIDTH"]
    period = p["N_COEFFS"] << p["STEP_PERIOD"]
    lat = p["BRAM_LATENCY"] + p["MULT_LATENCY"] + p["ADD_LATENCY"] + p["CONV_LATENCY"]
    cycles = len(st["sync_in"])

    cnt, addr = 0, []
    for t in range(cycles):
        addr.append(cnt >> p["STEP_PERIOD"])
        cnt = 0 if st["sync_in"][t] else (cnt + 1) % period

    one = Fraction(1, 2 ** (cw - 1))
    fmt = (w + 1, bp, 1, p["QUANTIZATION"], p["OVERFLOW"])
    prod_re, prod_im = [], []
    for t in range(cycles):
        c_re, c_im = (Fraction(x) * one for x in table[addr[t]])
        row_re, row_im = [], []
        for k in range(n):
            b_re = to_value(st["bi_re"][t][k], w, bp, 1)
            b_im = to_value(st["bi_im"][t][k], w, bp, 1)
            row_re.append(quantize(b_re * c_re - b_im * c_im, *fmt))
            row_im.append(quantize(b_re * c_im + b_im * c_re, *fmt))
        prod_re.append(row_re)
        prod_im.append(row_im)

    return {
        "ao_re": lanes_delayed(st["ai_re"], lat, n),
        "ao_im": lanes_delayed(st["ai_im"], lat, n),
        "bwo_re": lanes_delayed(prod_re, lat, n),
        "bwo_im": lanes_delayed(prod_im, lat, n),
        "sync_out": delayed(st["sync_in"], lat, 0),
    }


def m_twiddle_pass_through(p, st):
    n = p["N_INPUTS"]
    return {
        "ao_re": lanes_delayed(st["ai_re"], 0, n),
        "ao_im": lanes_delayed(st["ai_im"], 0, n),
        "bwo_re": lanes_delayed(st["bi_re"], 0, n),
        "bwo_im": lanes_delayed(st["bi_im"], 0, n),
        "sync_out": delayed(st["sync_in"], 0, 0),
    }


def coeff01_latency(p):
    return 1 + p["MULT_LATENCY"] + p["ADD_LATENCY"] + p["CONV_LATENCY"]


def m_twiddle_coeff_0(p, st):
    n, lat = p["N_INPUTS"], coeff01_latency(p)
    return {
        "ao_re": lanes_delayed(st["ai_re"], lat, n),
        "ao_im": lanes_delayed(st["ai_im"], lat, n),
        "bwo_re": lanes_delayed(st["bi_re"], lat, n),
        "bwo_im": lanes_delayed(st["bi_im"], lat, n),
        "sync_out": delayed(st["sync_in"], lat, 0),
    }


def m_twiddle_coeff_1(p, st):
    n, w, lat = p["N_INPUTS"], p["INPUT_BIT_WIDTH"], coeff01_latency(p)
    neg_re = [[neg_sat(x, w) for x in row] for row in st["bi_re"]]
    return {
        "ao_re": lanes_delayed(st["ai_re"], lat, n),
        "ao_im": lanes_delayed(st["ai_im"], lat, n),
        "bwo_re": lanes_delayed(st["bi_im"], lat, n),     # -j·b: re <- im
        "bwo_im": lanes_delayed(neg_re, lat, n),          #       im <- -re
        "sync_out": delayed(st["sync_in"], lat, 0),
    }


def m_twiddle_stage_2(p, st):
    n, w = p["N_INPUTS"], p["INPUT_BIT_WIDTH"]
    b = p["BRAM_LATENCY"]
    mux = p["MULT_LATENCY"] + p["CONV_LATENCY"] + p["ADD_LATENCY"]
    lat = b + mux
    cycles = len(st["sync_in"])
    cnt_mod = 1 << (p["FFT_SIZE"] - 1)
    msb = p["FFT_SIZE"] - 2

    sync_d = delayed(st["sync_in"], b, 0)
    re_d = lanes_delayed(st["bi_re"], b, n)
    im_d = lanes_delayed(st["bi_im"], b, n)

    cnt, pre_re, pre_im = 0, [], []
    for t in range(cycles):
        sel = (cnt >> msb) & 1
        if sel:
            pre_re.append(list(im_d[t]))
            pre_im.append([neg_sat(x, w) for x in re_d[t]])
        else:
            pre_re.append(list(re_d[t]))
            pre_im.append(list(im_d[t]))
        cnt = 0 if sync_d[t] else (cnt + 1) % cnt_mod

    return {
        "ao_re": lanes_delayed(st["ai_re"], lat, n),
        "ao_im": lanes_delayed(st["ai_im"], lat, n),
        "bwo_re": lanes_delayed(pre_re, mux, n),
        "bwo_im": lanes_delayed(pre_im, mux, n),
        "sync_out": delayed(sync_d, mux, 0),
    }


# ── test configurations ─────────────────────────────────────────────────────

def P(names, values):
    return dict(zip(names, values))


GEN = ["N_INPUTS", "FFT_SIZE", "N_COEFFS", "STEP_PERIOD", "INPUT_BIT_WIDTH", "BIN_PT_IN",
       "COEFF_BIT_WIDTH", "MULT_LATENCY", "ADD_LATENCY", "CONV_LATENCY", "BRAM_LATENCY",
       "QUANTIZATION", "OVERFLOW"]
PASS = ["N_INPUTS", "INPUT_BIT_WIDTH"]
C0 = ["N_INPUTS", "INPUT_BIT_WIDTH", "MULT_LATENCY", "ADD_LATENCY", "BRAM_LATENCY", "CONV_LATENCY"]
C1 = ["N_INPUTS", "INPUT_BIT_WIDTH", "BIN_PT_IN", "MULT_LATENCY", "ADD_LATENCY",
      "BRAM_LATENCY", "CONV_LATENCY"]
S2 = ["N_INPUTS", "FFT_SIZE", "INPUT_BIT_WIDTH", "BIN_PT_IN", "ADD_LATENCY", "MULT_LATENCY",
      "BRAM_LATENCY", "CONV_LATENCY"]

# twiddle_general: (coeffs, [param values without N_COEFFS], cycles, description)
GENERAL_TESTS = [
    ([0, 1, 2, 3], [1, 4, 0, 18, 17, 18, 2, 1, 1, 1, 1, 0], 512,
     "16-point stage coefficients 0..3, casper defaults (round ±inf, wrap)"),
    ([0, 1, 2, 3], [2, 4, 2, 18, 17, 18, 2, 1, 1, 1, 2, 1], 512,
     "2 lanes, each coefficient held 4 cycles, round even + saturate"),
    ([0, 1, 2, 3, 4, 5, 6, 7], [1, 5, 1, 12, 11, 10, 1, 1, 0, 1, 0, 1], 512,
     "12-bit data × 10-bit coefficients, truncate, combinational convert"),
    ([2, 5, 7], [1, 4, 1, 16, 15, 16, 2, 1, 1, 1, 1, 0], 512,
     "3 coefficients (not a power of two), held 2 cycles"),
    ([3], [4, 3, 0, 8, 7, 8, 0, 0, 0, 1, 1, 1], 256,
     "single coefficient, 4 lanes, only the rom latency"),
    ([0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15], [1, 6, 0, 18, 17, 18, 3, 2, 2, 2, 1, 0],
     1024, "16 bit-reversed coefficients of a 64-point FFT, BRAM_LATENCY 2"),
]

MODULES = {
    "twiddle_general": dict(
        prose="`twiddle_general` multiplies the `bi` lanes by the coefficient table "
              "(`bwo = bi · w[k]`) and delay-matches `ai` and `sync`. Each "
              "`simdataN/twiddle.mem` comes from `scripts/gen_twiddle_coeffs.py` "
              "for the listed `COEFFS` (the `Coeffs` of casper_library). The "
              "expected `bwo` is the exact product with `w[k]` held for "
              "`2^STEP_PERIOD` cycles, the schedule restarting at `w[0]` on the "
              "cycle after every sync pulse, requantized to "
              "`INPUT_BIT_WIDTH+1` bits (binary point `BIN_PT_IN`). Sync pulses "
              "come once per schedule period, with one early re-sync mid-run.",
        tests=[(P(GEN, [v[0], v[1], len(c)] + v[2:]), cyc, d, c) for c, v, cyc, d in GENERAL_TESTS],
        frame=lambda p: p["N_COEFFS"] << p["STEP_PERIOD"]),
    "twiddle_pass_through": dict(
        prose="`twiddle_pass_through` wires every leg straight through (zero latency).",
        tests=[(P(PASS, [1, 18]), 128, "1 lane, 18-bit", None),
               (P(PASS, [3, 8]), 128, "3 lanes, 8-bit", None)],
        frame=lambda p: 16),
    "twiddle_coeff_0": dict(
        prose="`twiddle_coeff_0` delays every leg by `1 + MULT_LATENCY + "
              "ADD_LATENCY + CONV_LATENCY` cycles (w = 1).",
        tests=[(P(C0, [1, 18, 2, 1, 1, 1]), 256, "casper-style latencies (total 5)", None),
               (P(C0, [2, 12, 3, 2, 2, 2]), 256, "2 lanes, total latency 8 (BRAM_LATENCY unused)", None),
               (P(C0, [1, 8, 0, 0, 1, 0]), 256, "minimum latency 1", None)],
        frame=lambda p: 16),
    "twiddle_coeff_1": dict(
        prose="`twiddle_coeff_1` multiplies `bi` by w = −j: `bwo_re = bi_im`, "
              "`bwo_im = −bi_re` (saturating), every leg delayed by "
              "`1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY` cycles. The "
              "first cycles include the most negative input word, whose "
              "negation saturates.",
        tests=[(P(C1, [1, 18, 17, 2, 1, 1, 1]), 256, "casper-style latencies (total 5)", None),
               (P(C1, [3, 8, 7, 1, 1, 2, 0]), 256, "3 lanes, 8-bit, total latency 3", None),
               (P(C1, [2, 16, 12, 0, 0, 1, 0]), 256, "2 lanes, minimum latency 1", None)],
        frame=lambda p: 16),
    "twiddle_stage_2": dict(
        prose="`twiddle_stage_2` applies w = 1 to the first `2^(FFT_SIZE-2)` "
              "samples after each sync and w = −j (`bwo = (bi_im, −bi_re)`, "
              "saturating) to the next `2^(FFT_SIZE-2)`, repeating; every leg "
              "is delayed by `BRAM_LATENCY + MULT_LATENCY + CONV_LATENCY + "
              "ADD_LATENCY` cycles. Sync pulses come once per "
              "`2^(FFT_SIZE-1)`-cycle frame, with one early re-sync mid-run.",
        tests=[(P(S2, [1, 5, 18, 17, 1, 2, 2, 2]), 512, "casper defaults (FFTSize 5, total latency 7)", None),
               (P(S2, [2, 3, 12, 11, 1, 1, 1, 1]), 256, "2 lanes, FFTSize 3 (w switches every 2 samples)", None),
               (P(S2, [1, 2, 8, 7, 0, 0, 1, 0]), 256, "FFTSize 2 (w switches every sample), latency 1", None),
               (P(S2, [4, 6, 16, 15, 2, 3, 3, 1]), 512, "4 lanes, FFTSize 6, total latency 9", None)],
        frame=lambda p: 1 << (p["FFT_SIZE"] - 1)),
}

MODELS = {
    "twiddle_pass_through": m_twiddle_pass_through,
    "twiddle_coeff_0": m_twiddle_coeff_0,
    "twiddle_coeff_1": m_twiddle_coeff_1,
    "twiddle_stage_2": m_twiddle_stage_2,
}


# ── writers ─────────────────────────────────────────────────────────────────

def full_params(name, n, params):
    if name == "twiddle_general":
        return dict(params, INIT_FILE=MEM_REL.format(n=n))
    return dict(params)


def write_csv(path, rows):
    path.write_text("".join(
        (" ".join(str(v) for v in r) if isinstance(r, list) else str(r)) + "\n" for r in rows))


def write_module(name, spec):
    mdir = TEST_DATA / name
    for n, (params, cycles, _, coeffs) in enumerate(spec["tests"]):
        rng = random.Random(f"{name}-{n}")
        w, lanes = params["INPUT_BIT_WIDTH"], params["N_INPUTS"]
        st = lane_stim(rng, w, lanes, cycles)
        # start with the extreme words so saturation / sign handling is hit
        extremes = [1 << (w - 1), (1 << (w - 1)) - 1, (1 << w) - 1, 0]
        for t, x in enumerate(extremes):
            for p in LANE_IN:
                st[p][t + 1] = [x] * lanes
        st["sync_in"] = sync_pulses(cycles, spec["frame"](params))

        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        meta = full_params(name, n, params)
        if name == "twiddle_general":
            table = twiddle_table(coeffs, params["FFT_SIZE"], params["COEFF_BIT_WIDTH"])
            (d / "twiddle.mem").write_text(
                "".join(line + "\n" for line in mem_lines(table, params["COEFF_BIT_WIDTH"])))
            out = m_twiddle_general(params, st, table)
            meta["COEFFS"] = coeffs
        else:
            out = MODELS[name](params, st)
        (d / "params.json").write_text(json.dumps(meta, indent=2) + "\n")
        for port in LANE_IN + ["sync_in"]:
            write_csv(d / f"sim_{port}.csv", st[port])
        for port in LANE_OUT + ["sync_out"]:
            write_csv(d / f"sim_{port}.csv", out[port])
    (mdir / "test_data.md").write_text(test_data_md(name, spec))


def test_data_md(name, spec):
    keys = list(spec["tests"][0][0].keys())
    has_coeffs = name == "twiddle_general"
    extra = " | COEFFS" if has_coeffs else ""
    lines = [
        f"# {name} test data",
        "",
        spec["prose"],
        "",
        "Generated by `scripts/gen_twiddle_test_data.py` from cycle-accurate "
        "Python reference models of the casper_library behavior (not exported "
        "from MATLAB). Each `simdataN/` holds a `params.json` with the DUT "
        "parameters (the testbench matches the integer ones), and one "
        "`sim_<port>.csv` per port: one row per clock cycle, with `N_INPUTS` "
        "space-separated columns (lane 0 first) for the lane ports "
        "(`ai_*`, `bi_*`, `ao_*`, `bwo_*`). All values are raw unsigned bit "
        "patterns. Expected outputs follow the pre-edge read convention, so "
        "the first latency cycles show the zero power-on state. Cycles 1–4 "
        "drive the extreme words (most negative, most positive, −1, 0) on "
        "every lane; the rest are seeded uniform-random words.",
        "",
        "| Test # | Directory | " + " | ".join(keys) + extra + " | Cycles | Description |",
        "|" + "---|" * (len(keys) + 4 + (1 if has_coeffs else 0)),
    ]
    for n, (params, cycles, desc, coeffs) in enumerate(spec["tests"]):
        vals = " | ".join(str(params[k]) for k in keys)
        c = f" | {coeffs}" if has_coeffs else ""
        lines.append(f"| {n} | `simdata{n}` | {vals}{c} | {cycles} | {desc} |")
    return "\n".join(lines) + "\n"


def toml_value(v):
    return f'"{v}"' if isinstance(v, str) else str(v)


def toml_block(name, spec):
    lines = [f"# test {name}", "[[simulations]]", f'dir = "{CATEGORY}"', f'top = "{name}"']
    for n, (params, _, desc, _) in enumerate(spec["tests"]):
        lines.append(f"# {desc}")
        lines.append("[[simulations.parameters]]")
        lines += [f"{k} = {toml_value(v)}" for k, v in full_params(name, n, params).items()]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--toml", action="store_true", help="only print the TOML blocks")
    args = ap.parse_args()
    for name in sorted(MODULES):
        if not args.toml:
            write_module(name, MODULES[name])
        print(toml_block(name, MODULES[name]))
        print()


if __name__ == "__main__":
    main()
