#!/usr/bin/env python3
"""Generate test data for rtl/FFTs/{fft_direct, fft_biplex_real_4x, fft_wideband_real}.

Expected outputs come from Python reference models built, as the casper
init scripts wire the blocks (fft_direct_init.m, fft_biplex_real_4x_init.m,
fft_wideband_real_init.m), from the reference models of the earlier phases:
butterfly_direct (gen_butterfly_test_data.py), biplex_core
(gen_biplex_test_data.py), bi_real_unscr_4x (gen_fft_internal_test_data.py)
and fft_unscrambler (gen_fft_unscrambler_test_data.py). Not from the RTL.

The script also checks with numpy, independently of the chain's structure,
that the models compute FFTs:
  fft_direct (MAP_TAIL off)  every cycle, out<s><n> = bin n of the FFT of
                             in<s><0 … 2^F-1> (natural order)
  fft_biplex_real_4x         every frame, pol<i>_out = the FFT of pol<i>_in
  fft_wideband_real          every frame, the outputs are the lower half of
                             the FFT of each stream's real input
                             x[t·2^N_INPUTS + n] = in<s><n> at frame cycle t,
                             in a fixed bin order (natural order with
                             UNSCRAMBLE: bin = t·2^(N_INPUTS-1) + n)
(shift all ones: every stage that does not grow a bit halves, so the FFTs
are scaled by 2^-(number of such stages)).

Writes test_data/FFTs/<module>/simdataN/{params.json, sim_<port>.csv, *.mem}
and test_data.md, and prints the [[simulations]] blocks for
tests/simulation.toml. Array ports have one column per element (element 0
first); values are raw two's-complement words.

Usage:
  python3 test_data/scripts/gen_fft_wideband_test_data.py
  python3 test_data/scripts/gen_fft_wideband_test_data.py --module fft_direct
"""

import json
import random
import sys
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli                     # also puts rtl/.../scripts on sys.path
from gen_butterfly_test_data import delay, write_csv, P, toml, m_butterfly
from gen_biplex_test_data import BC, m_biplex_core, signed
from gen_fft_internal_test_data import BR, m_bi_real_unscr_4x
from gen_fft_unscrambler_test_data import FU, m_fft_unscrambler
from gen_fft_mem_files import (bit_rev, direct_coeffs, twiddle_kind, write_biplex_real_4x,
                               write_direct, write_wideband_real)

SCRIPT = Path(__file__).name
CATEGORY = "FFTs"
TEST_DATA = TEST_DATA_ROOT / CATEGORY
MEM_REL = "../../../test_data/FFTs/{module}/simdata{n}/"


def sync_every(cycles, period, first=3):
    return [1 if t >= first and (t - first) % period == 0 else 0 for t in range(cycles)]


def clamp_width(iw, extra, bitgrowth, max_bits):
    return min(max_bits, iw + extra) if bitgrowth else iw


def lanes(rows, idx):
    return [[r[i] for i in idx] for r in rows]


# ── fft_direct ──────────────────────────────────────────────────────────────

FD = ["N_STREAMS", "FFT_SIZE", "INPUT_BIT_WIDTH", "BIN_PT_IN", "COEFF_BIT_WIDTH", "MAP_TAIL",
      "LARGER_FFT_SIZE", "START_STAGE", "ADD_LATENCY", "MULT_LATENCY", "BRAM_LATENCY",
      "CONV_LATENCY", "QUANTIZATION", "OVERFLOW", "MAX_FANOUT", "BITGROWTH", "MAX_BITS",
      "HARDCODE_SHIFTS", "SHIFT_SCHEDULE"]


def direct_stage(p, s):
    """Width, growth and downshift of stage s (fft_direct_init.m)."""
    w_in = clamp_width(p["INPUT_BIT_WIDTH"], s, p["BITGROWTH"], p["MAX_BITS"])
    grow = 1 if p["BITGROWTH"] and w_in + 1 <= p["MAX_BITS"] else 0
    down = 1 if p["HARDCODE_SHIFTS"] and (p["SHIFT_SCHEDULE"] >> s) & 1 else 0
    return w_in, grow, down


def direct_shifts(p):
    """Number of stages that halve (all shift bits set): those not growing a bit."""
    return sum(1 - direct_stage(p, s)[1] for s in range(p["FFT_SIZE"]))


def biplex_shifts(p):
    """Same for a biplex_core of p's FFT_SIZE / width / growth settings."""
    f, iw, mb = p["FFT_SIZE"], p["INPUT_BIT_WIDTH"], p["MAX_BITS"]
    n = 0
    for s in range(1, f + 1):
        w_in = min(mb, iw + s - 1) if p["BITGROWTH"] else iw
        n += 0 if p["BITGROWTH"] and w_in + 1 <= mb else 1
    return n


def direct_out_width(p):
    w_in, grow, _ = direct_stage(p, p["FFT_SIZE"] - 1)
    return w_in + grow


def m_fft_direct(p, st):
    """st: din_re / din_im rows (element s·2^F + n), sync, shift (int)."""
    f, ns = p["FFT_SIZE"], p["N_STREAMS"]
    cycles, half, l0 = len(st["sync"]), 1 << (f - 1), ns << (f - 1)
    mt = bool(p["MAP_TAIL"])
    outs = {}                                   # (s, u) -> butterfly result
    for s in range(f):
        w_in, grow, down = direct_stage(p, s)
        nl = ns << (f - s - 1)
        mask = (1 << w_in) - 1
        for u in range(1 << s):
            coeffs, size = direct_coeffs(f, s, u, mt, p["LARGER_FFT_SIZE"], p["START_STAGE"])
            if s == 0:
                el = [(i % ns) * (1 << f) + i // ns for i in range(2 * l0)]
                a = {c: lanes(st[f"din_{c}"], el[:l0]) for c in ("re", "im")}
                b = {c: lanes(st[f"din_{c}"], el[l0:]) for c in ("re", "im")}
                s_in = st["sync"]
            else:
                par = outs[(s - 1, u // 2)]
                src = "apbw" if u % 2 == 0 else "ambw"
                a = {c: [[x & mask for x in r[:nl]] for r in par[f"{src}_{c}"]] for c in ("re", "im")}
                b = {c: [[x & mask for x in r[nl:]] for r in par[f"{src}_{c}"]] for c in ("re", "im")}
                s_in = par["sync_out"]
            bp = {"N_INPUTS": nl, "BIPLEX": 0, "FFT_SIZE": size, "N_COEFFS": len(coeffs),
                  "COEFF_0": coeffs[0], "COEFF_1": coeffs[1] if len(coeffs) > 1 else 0,
                  "STEP_PERIOD": 0, "COEFF_BIT_WIDTH": p["COEFF_BIT_WIDTH"],
                  "INPUT_BIT_WIDTH": w_in, "BIN_PT_IN": p["BIN_PT_IN"], "BITGROWTH": grow,
                  "DOWNSHIFT": down, "HARDCODE_SHIFTS": p["HARDCODE_SHIFTS"],
                  "ADD_LATENCY": p["ADD_LATENCY"], "MULT_LATENCY": p["MULT_LATENCY"],
                  "BRAM_LATENCY": p["BRAM_LATENCY"], "CONV_LATENCY": p["CONV_LATENCY"],
                  "QUANTIZATION": p["QUANTIZATION"], "OVERFLOW": p["OVERFLOW"],
                  "MAX_FANOUT": p["MAX_FANOUT"]}
            bst = {"a_re": a["re"], "a_im": a["im"], "b_re": b["re"], "b_im": b["im"],
                   "sync_in": s_in, "shift": [(x >> s) & 1 for x in st["shift"]]}
            outs[(s, u)] = m_butterfly(bp, coeffs, bst)
    out = {"dout_re": [[0] * (ns << f) for _ in range(cycles)],
           "dout_im": [[0] * (ns << f) for _ in range(cycles)],
           "sync_out": outs[(f - 1, 0)]["sync_out"]}
    for n in range(1 << f):
        pos = bit_rev(n, f)
        for s_ in range(ns):
            for t in range(cycles):
                out["dout_re"][t][s_ * (1 << f) + n] = src_val(outs, f, pos, "re", t, s_)
                out["dout_im"][t][s_ * (1 << f) + n] = src_val(outs, f, pos, "im", t, s_)
    # overflow tree
    if f == 1:
        out["of"] = outs[(0, 0)]["of"]
    else:
        vec = [0] * cycles
        for s in range(f):
            nl = ns << (f - s - 1)
            for u in range(1 << s):
                ofs = outs[(s, u)]["of"]
                for t in range(cycles):
                    for l in range(nl):
                        if (ofs[t] >> l) & 1:
                            vec[t] |= 1 << (u * nl + l)
        vec = delay(vec, 2, 0)
        comb = [0] * cycles
        for t in range(cycles):
            for pt in range(half):
                comb[t] |= (vec[t] >> (pt * ns)) & ((1 << ns) - 1)
        out["of"] = delay(comb, 2, 0)
    return out


def src_val(outs, f, pos, part, t, lane):
    port = "apbw" if pos % 2 == 0 else "ambw"
    return outs[(f - 1, pos // 2)][f"{port}_{part}"][t][lane]


def check_direct_is_fft(p, st, out):
    """Every cycle the outputs are the FFT of that cycle's inputs (MAP_TAIL off)."""
    try:
        import numpy as np
    except ImportError:
        print("# numpy not available: fft_direct FFT check skipped", file=sys.stderr)
        return None
    f, ns, iw, bp = p["FFT_SIZE"], p["N_STREAMS"], p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"]
    w_out = direct_out_width(p)
    lat = out["sync_out"].index(1) - st["sync"].index(1)
    worst, n = 0.0, 1 << f
    for t in range(1, len(st["sync"]) - lat):
        for s in range(ns):
            x = np.array([signed(st["din_re"][t][s * n + k], iw) + 1j * signed(st["din_im"][t][s * n + k], iw)
                          for k in range(n)]) / 2 ** bp
            y = np.array([signed(out["dout_re"][t + lat][s * n + k], w_out)
                          + 1j * signed(out["dout_im"][t + lat][s * n + k], w_out)
                          for k in range(n)]) / 2 ** bp
            worst = max(worst, np.max(np.abs(y - np.fft.fft(x) / 2 ** direct_shifts(p))) * 2 ** bp)
    assert worst < 3, f"fft_direct model is not an FFT (error {worst:.1f} LSB)"
    return worst


FD_TESTS = [
    # values: FD order; amp: input amplitude (bits below full scale), shift: "ones" or "random"
    (P(FD, [1, 2, 18, 17, 18, 0, 0, 0, 1, 2, 2, 1, 1, 1, 4, 0, 19, 0, 0]), 3, "ones",
     "4-point, 1 stream, coeff_0 / coeff_1 twiddles only"),
    (P(FD, [2, 3, 16, 15, 18, 0, 0, 0, 1, 2, 2, 1, 2, 1, 4, 1, 21, 0, 0]), 3, "ones",
     "8-point, 2 streams, general twiddles, bit growth (output width min(MAX_BITS, IW+F))"),
    (P(FD, [1, 4, 18, 17, 18, 0, 0, 0, 2, 3, 1, 0, 1, 1, 2, 0, 19, 0, 0]), 3, "ones",
     "16-point, combinational convert, MAX_FANOUT 2"),
    (P(FD, [3, 1, 12, 11, 18, 0, 0, 0, 1, 2, 2, 1, 1, 0, 4, 0, 19, 0, 0]), 0, "random",
     "FFT_SIZE 1 (one butterfly), 3 streams, full-scale data, random shift, wrap"),
    (P(FD, [2, 3, 12, 11, 12, 0, 0, 0, 1, 2, 2, 1, 1, 1, 4, 0, 19, 1, 0b110]), 0, "random",
     "8-point, full-scale data, hardcoded shifts 110 (stages 1, 2), saturate: overflow flags"),
    (P(FD, [1, 2, 18, 17, 18, 1, 6, 5, 1, 2, 2, 1, 1, 1, 4, 0, 19, 0, 0]), 3, "random",
     "MAP_TAIL: last 2 stages of a 64-point FFT (as in fft_wideband_real), 16 coefficients"),
]


def gen_fft_direct():
    name, mdir, sets = "fft_direct", TEST_DATA / "fft_direct", []
    for n, (p, amp, shift_kind, desc) in enumerate(FD_TESTS):
        rng = random.Random(f"{name}-{n}")
        f, ns, iw = p["FFT_SIZE"], p["N_STREAMS"], p["INPUT_BIT_WIDTH"]
        period = 1 << (p["LARGER_FFT_SIZE"] - f) if p["MAP_TAIL"] else 16
        cycles = 3 + 6 * period + 40
        a = 1 << (iw - 1 - amp)
        st = {c: [[0] * (ns << f)] + [[rng.randrange(-a, a) % (1 << iw) for _ in range(ns << f)]
                                      for _ in range(cycles - 1)] for c in ("din_re", "din_im")}
        st["sync"] = sync_every(cycles, period)
        st["shift"] = ([(1 << f) - 1] * cycles if shift_kind == "ones"
                       else [rng.randrange(1 << f) for _ in range(cycles)])
        out = m_fft_direct(p, st)
        worst = check_direct_is_fft(p, st, out) if (not p["MAP_TAIL"] and shift_kind == "ones") else None
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.mem"):
            old.unlink()
        files = write_direct(d, f, p["COEFF_BIT_WIDTH"], bool(p["MAP_TAIL"]),
                             p["LARGER_FFT_SIZE"], p["START_STAGE"])
        full = dict(p, COEFF_DIR=MEM_REL.format(module=name, n=n))
        (d / "params.json").write_text(json.dumps(full, indent=2) + "\n")
        for k in ("din_re", "din_im", "sync", "shift"):
            write_csv(d / f"sim_{k}.csv", st[k])
        for k in ("dout_re", "dout_im", "sync_out", "of"):
            write_csv(d / f"sim_{k}.csv", out[k])
        check = "n/a" if worst is None else f"{worst:.2f} LSB"
        sets.append((full, desc, cycles, len(files), check))
    md(mdir, name, FD, sets, ["Twiddle files", "FFT check"],
       "`fft_direct` is a fully parallel FFT of 2^FFT_SIZE samples per stream "
       "per cycle, built from butterfly_direct stages as `fft_direct_init.m` "
       "wires them. `sync` pulses every 16 cycles (MAP_TAIL off) or every "
       "2^(LARGER_FFT_SIZE−FFT_SIZE) cycles, the coefficient period (MAP_TAIL "
       "on). Data are random: small (1/8 of full scale) for the sets with an "
       "FFT check, full scale otherwise (so the overflow flags are exercised); "
       "`shift` is all ones or random per cycle. *FFT check*: numpy check that "
       "each cycle's outputs are the FFT of that cycle's inputs, divided by "
       "2^FFT_SIZE (worst error in output LSBs); not applicable to MAP_TAIL "
       "(only the tail of a larger FFT) or non-uniform shifts. The twiddle "
       "tables come from `rtl/FFTs/scripts/gen_fft_mem_files.py direct`; "
       "`COEFF_DIR` is relative to `tests/sim_build/FFTs/fft_direct/`.")
    return toml(CATEGORY, name, [(full, desc) for full, desc, *_ in sets], SCRIPT)


# ── fft_biplex_real_4x ──────────────────────────────────────────────────────

FB4 = ["N_BIPLEX_INPUTS", "FFT_SIZE", "INPUT_BIT_WIDTH", "BIN_PT_IN", "COEFF_BIT_WIDTH",
       "ADD_LATENCY", "MULT_LATENCY", "BRAM_LATENCY", "CONV_LATENCY", "QUANTIZATION", "OVERFLOW",
       "DELAYS_BIT_LIMIT", "COEFFS_BIT_LIMIT", "MAX_FANOUT", "BITGROWTH", "MAX_BITS",
       "HARDCODE_SHIFTS", "SHIFT_SCHEDULE"]


def biplex4x_derived(p):
    """bram_delays, bram_map and output width (fft_biplex_real_4x_init.m)."""
    f, iw, nb, bl = p["FFT_SIZE"], p["INPUT_BIT_WIDTH"], p["N_BIPLEX_INPUTS"], p["BRAM_LATENCY"]
    half = 2 ** (f - 1)
    bram_delays = int(half * 2 * iw * nb >= 2 ** p["DELAYS_BIT_LIMIT"] and half >= bl + 2)
    bram_map = int(half * (f - 1) >= 2 ** p["COEFFS_BIT_LIMIT"] and half >= bl)
    w_out = min(iw + f, p["MAX_BITS"]) if p["BITGROWTH"] else iw
    return bram_delays, bram_map, w_out


def m_fft_biplex_real_4x(p, st):
    """st: pol_in rows (4·N_BIPLEX_INPUTS real words), sync, shift (int)."""
    nb = p["N_BIPLEX_INPUTS"]
    bram_delays, bram_map, w_out = biplex4x_derived(p)
    bc = P(BC, [nb, p["FFT_SIZE"], p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"], p["COEFF_BIT_WIDTH"],
                p["ADD_LATENCY"], p["MULT_LATENCY"], p["BRAM_LATENCY"], p["CONV_LATENCY"],
                p["QUANTIZATION"], p["OVERFLOW"], p["DELAYS_BIT_LIMIT"], p["MAX_FANOUT"],
                p["BITGROWTH"], p["MAX_BITS"], p["HARDCODE_SHIFTS"], p["SHIFT_SCHEDULE"]])
    bst = {"pol1_re": lanes(st["pol_in"], [4 * j for j in range(nb)]),
           "pol1_im": lanes(st["pol_in"], [4 * j + 1 for j in range(nb)]),
           "pol2_re": lanes(st["pol_in"], [4 * j + 2 for j in range(nb)]),
           "pol2_im": lanes(st["pol_in"], [4 * j + 3 for j in range(nb)]),
           "sync": st["sync"], "shift": st["shift"]}
    bo = m_biplex_core(bc, bst)
    br = P(BR, [nb, p["FFT_SIZE"], w_out, p["BIN_PT_IN"], p["ADD_LATENCY"], p["CONV_LATENCY"],
                p["BRAM_LATENCY"], bram_map, bram_delays])
    ro = m_bi_real_unscr_4x(br, {"sync": bo["sync_out"], "even_re": bo["out1_re"],
                                 "even_im": bo["out1_im"], "odd_re": bo["out2_re"],
                                 "odd_im": bo["out2_im"]})
    cycles = len(st["sync"])
    out = {"sync_out": ro["sync_out"], "of": bo["of"],
           "pol_out_re": [[ro[f"pol{i % 4 + 1}_out_re"][t][i // 4] for i in range(4 * nb)]
                          for t in range(cycles)],
           "pol_out_im": [[ro[f"pol{i % 4 + 1}_out_im"][t][i // 4] for i in range(4 * nb)]
                          for t in range(cycles)]}
    return out


def frame_fft_check(x_of, y_of, starts_in, starts_out, npts, scale, bp, tol=4):
    """Each output frame matches the FFT of one input frame, at a fixed frame lag.

    x_of(start) -> list of real/complex input vectors (one per signal),
    y_of(start) -> list of output vectors (same order). Returns (frames, worst LSB).
    """
    import numpy as np
    lag, worst, frames = None, 0.0, 0
    for so in starts_out[1:]:
        errs = {}
        for si in [s for s in starts_in if s < so]:
            errs[si] = max(np.max(np.abs(np.array(y) - np.fft.fft(np.array(x)) * scale))
                           for x, y in zip(x_of(si), y_of(so))) * 2 ** bp
        best = min(errs, key=errs.get)
        assert errs[best] < tol, f"output frame at {so} is not an FFT (error {errs[best]:.1f} LSB)"
        assert lag in (None, so - best), "frame latency changes"
        lag, worst, frames = so - best, max(worst, errs[best]), frames + 1
    assert frames >= 2, "too few frames"
    return frames, worst


def check_biplex4x_is_fft(p, st, out):
    try:
        import numpy as np  # noqa: F401
    except ImportError:
        print("# numpy not available: fft_biplex_real_4x FFT check skipped", file=sys.stderr)
        return None
    f, iw, bp = p["FFT_SIZE"], p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"]
    w_out, npts, cycles = biplex4x_derived(p)[2], 1 << p["FFT_SIZE"], len(st["sync"])
    ni = 4 * p["N_BIPLEX_INPUTS"]
    starts_in = [t + 1 for t, s in enumerate(st["sync"]) if s and t + npts < cycles]
    starts_out = [t + 1 for t, s in enumerate(out["sync_out"]) if s and t + npts < cycles]

    def x_of(s0):
        return [[signed(st["pol_in"][s0 + k][i], iw) / 2 ** bp for k in range(npts)] for i in range(ni)]

    def y_of(s0):
        return [[(signed(out["pol_out_re"][s0 + k][i], w_out)
                  + 1j * signed(out["pol_out_im"][s0 + k][i], w_out)) / 2 ** bp
                 for k in range(npts)] for i in range(ni)]

    return frame_fft_check(x_of, y_of, starts_in, starts_out, npts, 2.0 ** -biplex_shifts(p), bp)


FB4_TESTS = [
    (P(FB4, [1, 3, 18, 17, 18, 1, 2, 2, 1, 1, 1, 8, 8, 4, 0, 19, 0, 0]), "casper defaults, 8-point"),
    (P(FB4, [2, 4, 12, 11, 18, 1, 2, 1, 0, 2, 1, 8, 8, 4, 1, 15, 0, 0]),
     "2 biplex inputs (8 real signals), bit growth capped at MAX_BITS 15"),
    (P(FB4, [1, 5, 16, 15, 18, 2, 3, 2, 1, 1, 1, 4, 4, 2, 0, 19, 0, 0]),
     "32-point, low bit limits: BRAM delays and BRAM map"),
    (P(FB4, [2, 3, 12, 11, 18, 1, 2, 2, 1, 1, 0, 8, 8, 4, 0, 19, 0, 0]),
     "full-scale data, random shift, wrap: overflow flags per lane (no FFT check)"),
]
FB4_FULL_SCALE = {3}                 # test numbers with full-scale data and random shift


def gen_fft_biplex_real_4x():
    name, mdir, sets = "fft_biplex_real_4x", TEST_DATA / "fft_biplex_real_4x", []
    for n, (p, desc) in enumerate(FB4_TESTS):
        rng = random.Random(f"{name}-{n}")
        f, iw, nb = p["FFT_SIZE"], p["INPUT_BIT_WIDTH"], p["N_BIPLEX_INPUTS"]
        npts = 1 << f
        cycles = 3 + 7 * npts + 128
        full_scale = n in FB4_FULL_SCALE
        a = 1 << (iw - 1 if full_scale else iw - 3)
        st = {"pol_in": [[0] * (4 * nb)] + [[rng.randrange(-a, a) % (1 << iw) for _ in range(4 * nb)]
                                            for _ in range(cycles - 1)],
              "sync": sync_every(cycles, npts),
              "shift": ([rng.randrange(1 << f) for _ in range(cycles)] if full_scale
                        else [(1 << f) - 1] * cycles)}
        out = m_fft_biplex_real_4x(p, st)
        chk = "n/a" if full_scale else check_biplex4x_is_fft(p, st, out)
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        write_biplex_real_4x(d, f, p["COEFF_BIT_WIDTH"])
        bram_delays, bram_map, w_out = biplex4x_derived(p)
        rel = MEM_REL.format(module=name, n=n)
        full = dict(p, COEFF_DIR=rel, MAP_DIR=rel)
        (d / "params.json").write_text(json.dumps(dict(full, BRAM_DELAYS=bram_delays, BRAM_MAP=bram_map,
                                                       N_BITS_OUT=w_out), indent=2) + "\n")
        for k in ("pol_in", "sync", "shift"):
            write_csv(d / f"sim_{k}.csv", st[k])
        for k in ("pol_out_re", "pol_out_im", "sync_out", "of"):
            write_csv(d / f"sim_{k}.csv", out[k])
        check = ("n/a" if chk == "n/a" else "skipped (no numpy)" if chk is None
                 else f"{chk[0]} ({chk[1]:.2f} LSB)")
        sets.append((full, desc, cycles, bram_delays, bram_map, check))
    md(mdir, name, FB4, sets, ["BRAM delays", "BRAM map", "FFT frames checked"],
       "`fft_biplex_real_4x` computes the FFTs of 4·N_BIPLEX_INPUTS real "
       "signals with one biplex_core and a bi_real_unscr_4x. The inputs are "
       "random real signals at 1/4 of full scale and `shift` is all ones, "
       "except in the full-scale set (random shift, so the overflow flags are "
       "exercised); `sync` pulses once per 2^FFT_SIZE-cycle frame. *FFT frames checked*: "
       "numpy check that every output frame after the first is the FFT of one "
       "input frame of each signal divided by 2^FFT_SIZE (worst error in "
       "output LSBs). The memory files come from "
       "`rtl/FFTs/scripts/gen_fft_mem_files.py biplex_real_4x`; `COEFF_DIR` and "
       "`MAP_DIR` are relative to `tests/sim_build/FFTs/fft_biplex_real_4x/`.")
    return toml(CATEGORY, name, [(full, desc) for full, desc, *_ in sets], SCRIPT)


# ── fft_wideband_real ───────────────────────────────────────────────────────

WR = ["N_STREAMS", "FFT_SIZE", "N_INPUTS", "INPUT_BIT_WIDTH", "BIN_PT_IN", "COEFF_BIT_WIDTH",
      "UNSCRAMBLE", "ADD_LATENCY", "MULT_LATENCY", "BRAM_LATENCY", "CONV_LATENCY",
      "INPUT_LATENCY", "BIPLEX_DIRECT_LATENCY", "QUANTIZATION", "OVERFLOW", "DELAYS_BIT_LIMIT",
      "COEFFS_BIT_LIMIT", "MAX_FANOUT", "BITGROWTH", "MAX_BITS", "HARDCODE_SHIFTS",
      "SHIFT_SCHEDULE"]


def wideband_derived(p):
    f, ni, ns, iw = p["FFT_SIZE"], p["N_INPUTS"], p["N_STREAMS"], p["INPUT_BIT_WIDTH"]
    fb = f - ni
    return {"fb": fb, "nb": (ns << ni) // 4,
            "unscr": int(p["UNSCRAMBLE"] and ni != 1),
            "w_dir": clamp_width(iw, fb, p["BITGROWTH"], p["MAX_BITS"]),
            "w_out": clamp_width(iw, f, p["BITGROWTH"], p["MAX_BITS"])}


def m_fft_wideband_real(p, st):
    """st: din rows (N_STREAMS·2^N_INPUTS real words), sync, shift (int)."""
    dv = wideband_derived(p)
    f, ni, ns, fb, nb = p["FFT_SIZE"], p["N_INPUTS"], p["N_STREAMS"], dv["fb"], dv["nb"]
    cycles, il, bdl = len(st["sync"]), p["INPUT_LATENCY"], p["BIPLEX_DIRECT_LATENCY"]
    nin, nout = ns << ni, ns << (ni - 1)
    # fft_biplex_real_4x on the delayed inputs
    q4 = P(FB4, [nb, fb, p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"], p["COEFF_BIT_WIDTH"],
                 p["ADD_LATENCY"], p["MULT_LATENCY"], p["BRAM_LATENCY"], p["CONV_LATENCY"],
                 p["QUANTIZATION"], p["OVERFLOW"], p["DELAYS_BIT_LIMIT"], p["COEFFS_BIT_LIMIT"],
                 p["MAX_FANOUT"], p["BITGROWTH"], p["MAX_BITS"], p["HARDCODE_SHIFTS"],
                 p["SHIFT_SCHEDULE"] & ((1 << fb) - 1)])
    b4 = m_fft_biplex_real_4x(q4, {"pol_in": delay(st["din"], il, [0] * nin),
                                   "sync": delay(st["sync"], il, 0),
                                   "shift": [x & ((1 << fb) - 1) for x in st["shift"]]})
    # fft_direct on the last NI stages
    qd = P(FD, [ns, ni, dv["w_dir"], p["BIN_PT_IN"], p["COEFF_BIT_WIDTH"], 1, f, fb + 1,
                p["ADD_LATENCY"], p["MULT_LATENCY"], p["BRAM_LATENCY"], p["CONV_LATENCY"],
                p["QUANTIZATION"], p["OVERFLOW"], p["MAX_FANOUT"], p["BITGROWTH"], p["MAX_BITS"],
                p["HARDCODE_SHIFTS"], p["SHIFT_SCHEDULE"] >> fb])
    dr = m_fft_direct(qd, {"din_re": delay(b4["pol_out_re"], bdl, [0] * nin),
                           "din_im": delay(b4["pol_out_im"], bdl, [0] * nin),
                           "sync": delay(b4["sync_out"], bdl, 0),
                           "shift": [x >> fb for x in st["shift"]]})
    keep = [s * (1 << ni) + n for s in range(ns) for n in range(1 << (ni - 1))]
    kept = {c: lanes(dr[f"dout_{c}"], keep) for c in ("re", "im")}
    if dv["unscr"]:
        qu = P(FU, [ns, f - 1, ni - 1, dv["w_out"], p["BRAM_LATENCY"], p["COEFFS_BIT_LIMIT"]])
        un = m_fft_unscrambler(qu, {"din_re": delay(kept["re"], bdl, [0] * nout),
                                    "din_im": delay(kept["im"], bdl, [0] * nout),
                                    "sync": delay(dr["sync_out"], bdl, 0)})
        out = {"dout_re": un["dout_re"], "dout_im": un["dout_im"], "sync_out": un["sync_out"]}
    else:
        out = {"dout_re": kept["re"], "dout_im": kept["im"], "sync_out": dr["sync_out"]}
    # of: LSB-aligned OR, latency 1 (casper bit b = biplex lane nb-1-b | stream ns-1-b)
    of_w = max(ns, nb)
    comb = []
    for t in range(cycles):
        v = 0
        for b in range(of_w):
            bit = 0
            if b < ns and (dr["of"][t] >> (ns - 1 - b)) & 1:
                bit = 1
            if b < nb and (b4["of"][t] >> (nb - 1 - b)) & 1:
                bit = 1
            v |= bit << b
        comb.append(v)
    out["of"] = delay(comb, 1, 0)
    return out


def check_wideband_is_fft(p, st, out):
    """Each output frame = lower half of the FFT of one input frame, fixed bin order.

    Returns (frames checked, worst LSB, bin order description).
    """
    try:
        import numpy as np
    except ImportError:
        print("# numpy not available: fft_wideband_real FFT check skipped", file=sys.stderr)
        return None
    dv = wideband_derived(p)
    f, ni, ns, iw, bp = p["FFT_SIZE"], p["N_INPUTS"], p["N_STREAMS"], p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"]
    g, frame, cycles, w = 1 << (ni - 1), 1 << dv["fb"], len(st["sync"]), dv["w_out"]
    starts_in = [t + 1 for t, s in enumerate(st["sync"]) if s and t + frame < cycles]
    starts_out = [t + 1 for t, s in enumerate(out["sync_out"]) if s and t + frame < cycles]
    n_shifts = (biplex_shifts(dict(p, FFT_SIZE=dv["fb"]))
                + direct_shifts(dict(p, FFT_SIZE=ni, INPUT_BIT_WIDTH=dv["w_dir"])))

    def spectrum(s0, s):
        x = [signed(st["din"][s0 + t][s * (1 << ni) + n], iw) / 2 ** bp
             for t in range(frame) for n in range(1 << ni)]
        return np.fft.fft(np.array(x)) / 2 ** n_shifts

    def got(s0, s):
        return np.array([[(signed(out["dout_re"][s0 + t][s * g + n], w)
                           + 1j * signed(out["dout_im"][s0 + t][s * g + n], w)) / 2 ** bp
                          for n in range(g)] for t in range(frame)])

    order, lag, worst, frames = None, None, 0.0, 0
    for so in starts_out[1:]:
        best = None
        for si in [s for s in starts_in if s < so]:
            perms, err = [], 0.0
            for s in range(ns):
                spec, y = spectrum(si, s)[: frame * g], got(so, s)
                # nearest bin for every output sample
                idx = np.argmin(np.abs(y.reshape(-1, 1) - spec.reshape(1, -1)), axis=1)
                err = max(err, np.max(np.abs(y.reshape(-1) - spec[idx])) * 2 ** bp)
                perms.append(tuple(idx))
            if best is None or err < best[0]:
                best = (err, si, perms)
        err, si, perms = best
        assert err < 4, f"output frame at {so} is not the FFT of an input frame ({err:.1f} LSB)"
        assert all(sorted(pm) == list(range(frame * g)) for pm in perms), "not all bins present"
        assert order in (None, perms[0]) and all(pm == perms[0] for pm in perms), "bin order changes"
        assert lag in (None, so - si), "frame latency changes"
        order, lag, worst, frames = perms[0], so - si, max(worst, err), frames + 1
    assert frames >= 2, "too few frames"
    natural = order == tuple(range(frame * g))
    if dv["unscr"]:
        assert natural, "unscrambled outputs are not in natural order"
    return frames, worst, "natural (bin = t·2^(N_INPUTS-1) + n)" if natural else "scrambled"


WR_TESTS = [
    (P(WR, [1, 5, 2, 18, 17, 18, 1, 1, 2, 2, 0, 0, 0, 1, 1, 8, 8, 4, 0, 19, 0, 31]),
     "casper defaults, 32-point, 4 samples / cycle, unscrambled"),
    (P(WR, [1, 6, 3, 16, 15, 18, 1, 1, 2, 2, 1, 0, 0, 1, 1, 8, 8, 4, 0, 19, 0, 63]),
     "64-point, 8 samples / cycle (2 biplex inputs), unscrambled"),
    (P(WR, [2, 5, 1, 18, 17, 18, 1, 1, 2, 2, 0, 0, 0, 1, 1, 8, 8, 4, 0, 19, 0, 31]),
     "2 streams, 2 samples / cycle: N_INPUTS 1 forces UNSCRAMBLE off"),
    (P(WR, [1, 6, 2, 12, 11, 18, 0, 1, 2, 2, 1, 1, 2, 2, 1, 8, 8, 4, 1, 22, 0, 63]),
     "no unscrambler, bit growth, input and biplex-direct pipelines"),
    (P(WR, [2, 6, 2, 16, 15, 16, 1, 2, 3, 1, 1, 0, 1, 2, 1, 4, 4, 2, 0, 19, 1, 0b111111]),
     "2 streams, hardcoded shifts, BRAM delays / maps, unscrambled"),
    (P(WR, [2, 5, 2, 10, 9, 18, 1, 1, 2, 2, 1, 0, 0, 1, 0, 8, 8, 4, 0, 19, 0, 31]),
     "full-scale data, random shift, wrap: overflow from both blocks (no FFT check)"),
]
WR_FULL_SCALE = {5}


def gen_fft_wideband_real():
    name, mdir, sets = "fft_wideband_real", TEST_DATA / "fft_wideband_real", []
    from gen_reorder_map import compute_order, unscrambler_map
    for n, (p, desc) in enumerate(WR_TESTS):
        rng = random.Random(f"{name}-{n}")
        dv = wideband_derived(p)
        f, ni, ns, iw = p["FFT_SIZE"], p["N_INPUTS"], p["N_STREAMS"], p["INPUT_BIT_WIDTH"]
        frame = 1 << dv["fb"]
        order = compute_order(unscrambler_map(f - 1, ni - 1)) if dv["unscr"] else 1
        period = order * frame
        cycles = 3 + max(6, 2 * order + 4) * period + 160
        full_scale = n in WR_FULL_SCALE
        a = 1 << (iw - 1 if full_scale else iw - 3)
        st = {"din": [[0] * (ns << ni)] + [[rng.randrange(-a, a) % (1 << iw) for _ in range(ns << ni)]
                                          for _ in range(cycles - 1)],
              "sync": sync_every(cycles, period),
              "shift": ([rng.randrange(1 << f) for _ in range(cycles)] if full_scale
                        else [(1 << f) - 1] * cycles)}
        out = m_fft_wideband_real(p, st)
        chk = "n/a" if full_scale else check_wideband_is_fft(p, st, out)
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.mem"):
            old.unlink()
        write_wideband_real(d, f, ni, p["COEFF_BIT_WIDTH"], bool(p["UNSCRAMBLE"]))
        full = dict(p, MEM_DIR=MEM_REL.format(module=name, n=n))
        (d / "params.json").write_text(json.dumps(dict(full, N_BITS_OUT=dv["w_out"]), indent=2) + "\n")
        for k in ("din", "sync", "shift"):
            write_csv(d / f"sim_{k}.csv", st[k])
        for k in ("dout_re", "dout_im", "sync_out", "of"):
            write_csv(d / f"sim_{k}.csv", out[k])
        check = ("n/a" if chk == "n/a" else "skipped (no numpy)" if chk is None
                 else f"{chk[0]} ({chk[1]:.2f} LSB, {chk[2]})")
        sets.append((full, desc, cycles, check))
    md(mdir, name, WR, sets, ["FFT frames checked"],
       "`fft_wideband_real` computes a 2^FFT_SIZE-point real FFT of "
       "2^N_INPUTS samples per stream per cycle: fft_biplex_real_4x for the "
       "first FFT_SIZE−N_INPUTS stages, fft_direct (MAP_TAIL) for the last "
       "N_INPUTS stages and, with UNSCRAMBLE, fft_unscrambler. The inputs are "
       "random real signals at 1/4 of full scale and `shift` is all ones, "
       "except in the full-scale set (random shift, so both blocks' overflow "
       "flags are exercised); `sync` pulses every "
       "ORDER·2^(FFT_SIZE−N_INPUTS) cycles (ORDER of the unscrambler map, 1 "
       "without it). *FFT frames checked*: numpy check "
       "that every output frame after the first is the lower half of the FFT "
       "of one input frame of each stream (input sample t·2^N_INPUTS + n = "
       "in<s><n> at frame cycle t) divided by 2^FFT_SIZE, every bin exactly "
       "once in a fixed order — natural order (bin = t·2^(N_INPUTS−1) + n) "
       "when unscrambled. The memory files come from "
       "`rtl/FFTs/scripts/gen_fft_mem_files.py wideband_real`; `MEM_DIR` is "
       "relative to `tests/sim_build/FFTs/fft_wideband_real/`.")
    return toml(CATEGORY, name, [(full, desc) for full, desc, *_ in sets], SCRIPT)


# ── test_data.md ────────────────────────────────────────────────────────────

def md(mdir, name, keys, sets, extra, prose):
    lines = [
        f"# {name} test data", "", prose, "",
        "Generated by `test_data/scripts/gen_fft_wideband_test_data.py` "
        "(reference models, not exported from MATLAB). CSV rows are cycles, "
        "one column per array element.", "",
        "| Test # | Directory | " + " | ".join(keys + extra) + " | Cycles | Description |",
        "|" + "---|" * (len(keys) + len(extra) + 4),
    ]
    for n, (p, desc, cycles, *rest) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(p[k]) for k in keys)
                     + "".join(f" | {x}" for x in rest) + f" | {cycles} | {desc} |")
    (mdir / "test_data.md").write_text("\n".join(lines) + "\n")


def main():
    run_cli(__doc__, {"fft_direct": gen_fft_direct, "fft_biplex_real_4x": gen_fft_biplex_real_4x,
                      "fft_wideband_real": gen_fft_wideband_real})


if __name__ == "__main__":
    main()
