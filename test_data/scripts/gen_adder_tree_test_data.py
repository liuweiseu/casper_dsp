#!/usr/bin/env python3
"""Generate test data for rtl/Misc/adder_tree.

The expected outputs come from a reference model of casper_library's
adder_tree as adder_tree_init.m builds it (pairwise reduction, the odd
value of a stage carried on through a delay), with exact fixed-point
arithmetic from gen_fixed_point_test_data.py — not from the RTL. For full
precision (PRECISION = 0) the script also checks independently that dout
is the exact sum of the inputs, STAGES·CSP_LATENCY cycles later.

Writes test_data/Misc/adder_tree/simdataN/{params.json, sim_<port>.csv} and
test_data.md, and prints the [[simulations]] block for tests/simulation.toml.
din has one file per input, sim_din<j>.csv = din[j]; values are raw words.

Usage:
  python3 test_data/scripts/gen_adder_tree_test_data.py
"""

import json
import random
from fractions import Fraction
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli
from gen_butterfly_test_data import delay, write_csv, P, toml
from gen_fixed_point_test_data import corners, quantize, to_value

SCRIPT = Path(__file__).name
MDIR = TEST_DATA_ROOT / "Misc" / "adder_tree"

AT = ["N_INPUTS", "DATA_WIDTH", "BIN_PT", "TYPE", "CSP_LATENCY", "PRECISION", "N_BITS_OUT",
      "BIN_PT_OUT", "QUANTIZATION", "OVERFLOW"]
AT_TESTS = [
    (P(AT, [1, 8, 0, 1, 1, 0, 8, 0, 0, 0]), "1 input: no stage, dout = din"),
    (P(AT, [2, 12, 4, 1, 1, 0, 12, 0, 0, 0]), "2 inputs, full precision"),
    (P(AT, [3, 8, 0, 1, 2, 0, 8, 0, 0, 0]), "3 inputs: one value carried through stage 1, latency 2"),
    (P(AT, [5, 10, 2, 0, 1, 0, 10, 0, 0, 0]), "5 inputs, unsigned, carried values in stages 1 and 2"),
    (P(AT, [7, 18, 17, 1, 0, 0, 18, 0, 0, 0]), "7 inputs, combinational (latency 0)"),
    (P(AT, [8, 16, 8, 1, 1, 0, 16, 0, 0, 0]), "8 inputs: balanced tree"),
    (dict(P(AT, [3, 8, 0, 1, 2, 0, 8, 0, 0, 0]), DVALID_EN=1),
     "set 2 with dvalid_en: random dv_in stalls the adders, the carried input is free"),
    (dict(P(AT, [8, 16, 8, 1, 1, 0, 16, 0, 0, 0]), DVALID_EN=1),
     "set 5 with dvalid_en: balanced tree, every adder stalled by dv_in"),
]
AT_DEFAULTS = {"DVALID_EN": 0}
# PRECISION = 1 sets are not listed: the mapping marks PRECISION != 0 unsupported
# (no standalone Simulink reference); pfb_fir_real covers it. Sets 6 and 7 keep
# the random seeds of their former numbers 8 and 9, so their data is unchanged.
AT_SEED = {6: 8, 7: 9}


def stages(n):
    s = 0
    while (1 << s) < n:
        s += 1
    return s


def gated(values, en, latency, zero):
    """Xilinx AddSub latency chain with an en port: advances only while en = 1."""
    if latency == 0:
        return values
    chain, out = [zero] * latency, []
    for v, e in zip(values, en):
        out.append(chain[-1])
        if e:
            chain = [v] + chain[:-1]
    return out


def m_adder_tree(p, st):
    """Reference model: values are exact Fractions per node, quantized per adder.

    DVALID_EN = 1 (adder_tree_init.m:113-125, 262-267): the raw dv_in gates
    every adder's latency chain; the carried odd values and sync stay free
    (checked against Simulink, MATLAB R2021a).
    """
    w, bp, typ, lat = p["DATA_WIDTH"], p["BIN_PT"], p["TYPE"], p["CSP_LATENCY"]
    cycles = len(st["sync"])
    dv = st["dv_in"] if p.get("DVALID_EN") else None
    # node = (values per cycle, n_bits, bin_pt, signed)
    nodes = [([to_value(row[j], w, bp, typ) for row in st["din"]], w, bp, typ)
             for j in range(p["N_INPUTS"])]
    while len(nodes) > 1:
        n_adds, nxt = len(nodes) // 2, []
        for j in range(n_adds):
            (va, wa, ba, ta), (vb, wb, bb, tb) = nodes[2 * j], nodes[2 * j + 1]
            if p["PRECISION"] == 0:
                fmt = (max(wa - ba, wb - bb) + 1 + bp, bp, typ)
                vals = [x + y for x, y in zip(va, vb)]          # exact, never overflows
            else:
                fmt = (p["N_BITS_OUT"], p["BIN_PT_OUT"], 1)
                vals = [to_value(quantize(x + y, *fmt, p["QUANTIZATION"], p["OVERFLOW"]), *fmt)
                        for x, y in zip(va, vb)]
            nxt.append(((gated(vals, dv, lat, Fraction(0)) if dv else delay(vals, lat, Fraction(0))), *fmt))
        if len(nodes) % 2:
            v, wn, bn, tn = nodes[-1]
            nxt.append((delay(v, lat, Fraction(0)), wn, bn, tn))
        nodes = nxt
    v, wn, bn, tn = nodes[0]
    return {"dout": [quantize(x, wn, bn, tn, 0, 0) for x in v],
            "sync_out": delay(st["sync"], stages(p["N_INPUTS"]) * lat, 0)}, wn


def check_exact_sum(p, st, out, w_out):
    """Full precision: dout = sum of the inputs, STAGES·CSP_LATENCY cycles later."""
    lat = stages(p["N_INPUTS"]) * p["CSP_LATENCY"]
    w, bp, typ = p["DATA_WIDTH"], p["BIN_PT"], p["TYPE"]
    for t in range(lat, len(st["sync"])):
        s = sum(to_value(x, w, bp, typ) for x in st["din"][t - lat])
        assert to_value(out["dout"][t], w_out, bp, typ) == s, f"cycle {t}: not the exact sum"
    return len(st["sync"]) - lat


def gen():
    sets = []
    for n, (p, desc) in enumerate(AT_TESTS):
        rng = random.Random(f"adder_tree-{AT_SEED.get(n, n)}")
        cycles, w, ni = 160, p["DATA_WIDTH"], p["N_INPUTS"]
        cs = corners(w)
        din = [[0] * ni]
        din += [[cs[(i + k) % len(cs)] for k in range(ni)] for i in range(2 * len(cs))]
        din += [[cs[i % len(cs)]] * ni for i in range(len(cs))]     # all inputs equal corners
        while len(din) < cycles:
            din.append([rng.randrange(1 << w) for _ in range(ni)])
        sync = [0] + [1 if rng.random() < 0.05 else 0 for _ in range(cycles - 1)]
        st = {"din": din, "sync": sync}
        if p.get("DVALID_EN"):
            st["dv_in"] = [1 if rng.random() < 0.75 else 0 for _ in range(cycles)]
            st["dv_in"][cycles // 2:cycles // 2 + 6] = [0] * 6
        out, w_out = m_adder_tree(p, st)
        checked = (check_exact_sum(p, st, out, w_out)
                   if p["PRECISION"] == 0 and not p.get("DVALID_EN") else "n/a")
        d = MDIR / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        (d / "params.json").write_text(json.dumps(dict(p, N_BITS_OUT_EFF=w_out), indent=2) + "\n")
        write_csv(d / "sim_din.csv", din)
        write_csv(d / "sim_sync.csv", sync)
        if p.get("DVALID_EN"):
            write_csv(d / "sim_dv_in.csv", st["dv_in"])
        write_csv(d / "sim_dout.csv", out["dout"])
        write_csv(d / "sim_sync_out.csv", out["sync_out"])
        sets.append((p, desc, cycles, stages(ni), w_out, checked))
    lines = [
        "# adder_tree test data", "",
        "`adder_tree` sums `N_INPUTS` values pairwise, stage by stage, carrying "
        "the odd value of a stage on through a delay (as `adder_tree_init.m`). "
        "Row 0 is zero, then corner words (0, 1, −1, most negative, most "
        "positive, …) rotated over the inputs, all inputs equal to each "
        "corner word, then random words; `sync` is sparse random pulses.", "",
        "Generated by `test_data/scripts/gen_adder_tree_test_data.py` "
        "(reference model, not exported from MATLAB). For full precision the "
        "script also checks that `dout` is the exact sum of the inputs "
        "STAGES·CSP_LATENCY cycles later (column *Exact-sum cycles checked*). CSV "
        "rows are cycles; `sim_din<j>.csv` holds input `din[j]`. Sets with "
        "`DVALID_EN` = 1 drive a random `sim_dv_in.csv`: casper stalls every "
        "adder on the raw `dv_in` while the carried odd values and `sync` run "
        "free (checked against Simulink, MATLAB R2021a); the exact-sum check "
        "does not apply there.", "",
        "| Test # | Directory | " + " | ".join(AT + list(AT_DEFAULTS)) + " | Stages | dout width | Exact-sum cycles checked | Cycles | Description |",
        "|" + "---|" * (len(AT) + len(AT_DEFAULTS) + 7),
    ]
    for n, (p, desc, cycles, stg, w_out, checked) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(dict(AT_DEFAULTS, **p)[k]) for k in AT + list(AT_DEFAULTS))
                     + f" | {stg} | {w_out} | {checked} | {cycles} | {desc} |")
    (MDIR / "test_data.md").write_text("\n".join(lines) + "\n")
    return toml("Misc", "adder_tree", [(p, d) for p, d, *_ in sets], SCRIPT)


def main():
    run_cli(__doc__, {"adder_tree": gen})


if __name__ == "__main__":
    main()
