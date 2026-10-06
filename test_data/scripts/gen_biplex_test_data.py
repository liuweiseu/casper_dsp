#!/usr/bin/env python3
"""Generate test data for rtl/FFTs/biplex_core.

The expected outputs chain the fft_stage_n reference model of
test_data/scripts/gen_fft_stage_test_data.py over stages 1 .. FFT_SIZE, with every
stage's parameters derived as biplex_core_init.m does. The twiddle tables
come from rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py.

As an independent check of the whole chain, main() also verifies (with
numpy, when available) that the reference model computes an FFT: for a
frame of inputs the fixed-point outputs must match numpy's FFT of each
stream (scaled by the shifts), in a fixed output order, to within the
rounding error.

Writes test_data/FFTs/biplex_core/simdataN/{params.json, sim_<port>.csv,
twiddle_stage<s>.mem} and test_data.md, and prints the [[simulations]]
block for tests/simulation.toml.

Usage:
  python3 test_data/scripts/gen_biplex_test_data.py
"""

import json
import random
import sys
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli                         # also puts rtl/.../scripts on sys.path
from gen_twiddle_coeffs import mem_lines, twiddle_table             # rtl/FFTs/Twiddle/scripts/
from gen_butterfly_test_data import write_csv, P, toml
from gen_fft_stage_test_data import m_fft_stage, stage_coeffs
import gen_twiddle_test_data as tw

SCRIPT = Path(__file__).name
MDIR = TEST_DATA_ROOT / "FFTs" / "biplex_core"
COEFF_REL = "../../../test_data/FFTs/biplex_core/simdata{n}/"

BC = ["N_INPUTS", "FFT_SIZE", "INPUT_BIT_WIDTH", "BIN_PT_IN", "COEFF_BIT_WIDTH",
      "ADD_LATENCY", "MULT_LATENCY", "BRAM_LATENCY", "CONV_LATENCY", "QUANTIZATION",
      "OVERFLOW", "DELAYS_BIT_LIMIT", "MAX_FANOUT", "BITGROWTH", "MAX_BITS",
      "HARDCODE_SHIFTS", "SHIFT_SCHEDULE"]

BIPLEX_TESTS = [
    (P(BC, [1, 3, 18, 17, 18, 1, 2, 2, 1, 1, 0, 8, 4, 0, 20, 0, 3]), 256,
     "8-point, casper defaults, dynamic shift"),
    (P(BC, [1, 4, 18, 17, 18, 1, 2, 1, 1, 2, 1, 1, 1, 0, 20, 0, 0]), 512,
     "16-point, RAM delays in stages 1–2 (DELAYS_BIT_LIMIT 1), round even + saturate"),
    (P(BC, [2, 4, 12, 11, 12, 1, 1, 1, 0, 1, 0, 8, 4, 1, 14, 0, 0]), 512,
     "16-point, 2 lanes, bit growth capped at MAX_BITS 14"),
    (P(BC, [1, 5, 16, 15, 18, 2, 3, 2, 2, 1, 1, 2, 2, 0, 20, 1, 0b10101]), 1024,
     "32-point, hardcoded shift schedule 10101, RAM delays in stages 1–2"),
]


def stage_params(p, s):
    """fft_stage_n parameters of stage s, as biplex_core_init.m derives them."""
    f, iw = p["FFT_SIZE"], p["INPUT_BIT_WIDTH"]
    w_in = min(p["MAX_BITS"], iw + s - 1) if p["BITGROWTH"] else iw
    grow = 1 if p["BITGROWTH"] and w_in + 1 <= p["MAX_BITS"] else 0
    return {
        "N_INPUTS": p["N_INPUTS"], "FFT_SIZE": f, "FFT_STAGE": s,
        "INPUT_BIT_WIDTH": w_in, "BIN_PT_IN": p["BIN_PT_IN"],
        "COEFF_BIT_WIDTH": p["COEFF_BIT_WIDTH"], "BITGROWTH": grow,
        "DOWNSHIFT": 1 if p["HARDCODE_SHIFTS"] and (p["SHIFT_SCHEDULE"] >> (s - 1)) & 1 else 0,
        "HARDCODE_SHIFTS": p["HARDCODE_SHIFTS"],
        "ADD_LATENCY": p["ADD_LATENCY"], "MULT_LATENCY": p["MULT_LATENCY"],
        "BRAM_LATENCY": p["BRAM_LATENCY"], "CONV_LATENCY": p["CONV_LATENCY"],
        "QUANTIZATION": p["QUANTIZATION"], "OVERFLOW": p["OVERFLOW"],
        "DELAYS_BRAM": 1 if (f - s > p["DELAYS_BIT_LIMIT"]
                             and 2 ** (f - s) > p["BRAM_LATENCY"]) else 0,
        "MAX_FANOUT": p["MAX_FANOUT"],
    }


def m_biplex_core(p, st):
    cycles = len(st["sync"])
    cur = {"in1_re": st["pol1_re"], "in1_im": st["pol1_im"],
           "in2_re": st["pol2_re"], "in2_im": st["pol2_im"],
           "of_in": [0] * cycles, "sync": st["sync"], "shift": st["shift"]}
    for s in range(1, p["FFT_SIZE"] + 1):
        out = m_fft_stage(stage_params(p, s), cur)
        cur = {"in1_re": out["out1_re"], "in1_im": out["out1_im"],
               "in2_re": out["out2_re"], "in2_im": out["out2_im"],
               "of_in": out["of"], "sync": out["sync_out"], "shift": st["shift"]}
    return {"out1_re": cur["in1_re"], "out1_im": cur["in1_im"],
            "out2_re": cur["in2_re"], "out2_im": cur["in2_im"],
            "of": cur["of_in"], "sync_out": cur["sync"]}


def signed(x, w):
    return x - (1 << w) if x >= 1 << (w - 1) else x


def check_is_fft(p):
    """Independent check: the reference model computes a (bit-reversed) FFT.

    One frame of random data (small amplitude, so nothing overflows, and all
    shifts on) goes through the model; afterwards each output cycle k of the
    frame must equal numpy's FFT bin bit_rev(k) of pol1 / pol2 divided by
    2^FFT_SIZE, to within a few output LSBs. Returns the worst error in LSBs.
    """
    import numpy as np
    f, iw, bp = p["FFT_SIZE"], p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"]
    npts = 1 << f
    rng = random.Random("fft-check")
    amp = 1 << (iw - 3)
    frame = {k: [rng.randrange(-amp, amp) for _ in range(npts)]
             for k in ["pol1_re", "pol1_im", "pol2_re", "pol2_im"]}
    lead = 3
    cycles = lead + 1 + 8 * npts
    st = {k: [[0] for _ in range(cycles)] for k in frame}
    for k, vals in frame.items():
        for i, v in enumerate(vals):
            st[k][lead + 1 + i] = [v % (1 << iw)]
    st["sync"] = [0] * cycles
    st["sync"][lead] = 1
    st["shift"] = [(1 << f) - 1] * cycles
    q = dict(p, N_INPUTS=1, OVERFLOW=0, HARDCODE_SHIFTS=0)
    out = m_biplex_core(q, st)
    t0 = out["sync_out"].index(1) + 1                 # first output of the frame
    w_out = stage_params(q, f)["INPUT_BIT_WIDTH"] + stage_params(q, f)["BITGROWTH"]
    x1 = (np.array(frame["pol1_re"]) + 1j * np.array(frame["pol1_im"])) / 2 ** bp
    x2 = (np.array(frame["pol2_re"]) + 1j * np.array(frame["pol2_im"])) / 2 ** bp
    # every stage halves (shift on), except stages that grow a bit instead
    n_shifts = sum(1 - stage_params(q, s)["BITGROWTH"] for s in range(1, f + 1))
    spec = {1: np.fft.fft(x1) / 2 ** n_shifts, 2: np.fft.fft(x2) / 2 ** n_shifts}
    half = npts // 2
    worst = 0.0
    for k in range(npts):
        # biplex output order (casper): the first half-frame carries pol1,
        # the second pol2; in cycle k, out1 holds bin bit_rev(k mod N/2,
        # FFT_SIZE-1) and out2 that bin + N/2
        pol = 1 if k < half else 2
        j = k % half
        b = int(format(j, f"0{f - 1}b")[::-1], 2) if f > 1 else 0
        for port, bin_ in (("out1", b), ("out2", b + half)):
            got = (signed(out[f"{port}_re"][t0 + k][0], w_out)
                   + 1j * signed(out[f"{port}_im"][t0 + k][0], w_out)) / 2 ** bp
            worst = max(worst, abs(got - spec[pol][bin_]) * 2 ** bp)
    return worst


def gen_biplex():
    sets = []
    for n, (p, cycles, desc) in enumerate(BIPLEX_TESTS):
        rng = random.Random(f"biplex_core-{n}")
        iw, lanes, f = p["INPUT_BIT_WIDTH"], p["N_INPUTS"], p["FFT_SIZE"]
        st = {k: [[rng.randrange(1 << iw) for _ in range(lanes)] for _ in range(cycles)]
              for k in ["pol1_re", "pol1_im", "pol2_re", "pol2_im"]}
        st["sync"] = tw.sync_pulses(cycles, 1 << f)
        st["shift"], t = [], 0
        while t < cycles:
            hold, v = rng.randrange(20, 80), rng.randrange(1 << f)
            st["shift"] += [v] * hold
            t += hold
        st["shift"] = st["shift"][:cycles]
        out = m_biplex_core(p, st)

        d = MDIR / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        for s in range(3, f + 1):
            (d / f"twiddle_stage{s}.mem").write_text("".join(
                line + "\n" for line in mem_lines(
                    twiddle_table(stage_coeffs({"FFT_STAGE": s}), f, p["COEFF_BIT_WIDTH"]),
                    p["COEFF_BIT_WIDTH"])))
        full = dict(p, COEFF_DIR=COEFF_REL.format(n=n))
        stages = [stage_params(p, s) for s in range(1, f + 1)]
        (d / "params.json").write_text(json.dumps(dict(full, STAGES=stages), indent=2) + "\n")
        for k in ["pol1_re", "pol1_im", "pol2_re", "pol2_im", "sync", "shift"]:
            write_csv(d / f"sim_{k}.csv", st[k])
        for k in ["out1_re", "out1_im", "out2_re", "out2_im", "of", "sync_out"]:
            write_csv(d / f"sim_{k}.csv", out[k])
        sets.append((full, desc, cycles))

    lines = [
        "# biplex_core test data", "",
        "`biplex_core` chains `FFT_SIZE` `fft_stage_n` stages. `sync` pulses "
        "once per `2^FFT_SIZE`-cycle frame plus one early re-sync; the `shift` "
        "bus holds random values for 20–79 cycles at a time. Inputs are "
        "full-scale random words, so overflow flags and wrap / saturation "
        "are exercised too.", "",
        "Generated by `test_data/scripts/gen_biplex_test_data.py`: the `fft_stage_n` "
        "reference model of `test_data/scripts/gen_fft_stage_test_data.py` chained over "
        "the stages, each stage's parameters derived as `biplex_core_init.m` "
        "does (recorded under `STAGES` in `params.json`). Not exported from "
        "MATLAB. The script also checks, with numpy, that this chained model "
        "computes the FFT of each stream in bit-reversed order to within the "
        "rounding error. `twiddle_stage<s>.mem` (stages ≥ 3) come from "
        "`rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py`; `COEFF_DIR` is relative to the "
        "simulator's working directory `tests/sim_build/FFTs/biplex_core/`. "
        "CSV rows are cycles, lane ports have one file per lane "
        "(`sim_<port><j>.csv` = lane j), bus ports "
        "are integers; raw unsigned bit patterns with the pre-edge read "
        "convention.", "",
        "| Test # | Directory | " + " | ".join(BC) + " | Cycles | Description |",
        "|" + "---|" * (len(BC) + 4),
    ]
    for n, (full, desc, cycles) in enumerate(sets):
        vals = [(bin(full[k]) if k == "SHIFT_SCHEDULE" else str(full[k])) for k in BC]
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(vals) + f" | {cycles} | {desc} |")
    (MDIR / "test_data.md").write_text("\n".join(lines) + "\n")
    return toml("FFTs", "biplex_core", [(full, desc) for full, desc, _ in sets], SCRIPT)


def fft_check(args, _names):
    if args.skip_fft_check:
        return
    for p, _, desc in BIPLEX_TESTS:
        err = check_is_fft(p)
        print(f"# FFT check ({desc}): worst error {err:.2f} LSB", file=sys.stderr)
        assert err < 2 * p["FFT_SIZE"], "reference model is not an FFT"


def main():
    run_cli(__doc__, {"biplex_core": gen_biplex},
            extra_args=lambda ap: ap.add_argument(
                "--skip-fft-check", action="store_true",
                help="skip the numpy check that the reference model is an FFT"),
            after=fft_check)


if __name__ == "__main__":
    main()
