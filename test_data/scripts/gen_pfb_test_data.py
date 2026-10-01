#!/usr/bin/env python3
"""Generate test data for the rtl/PFBs/ modules.

pfb_coeff_gen: the expected outputs come from a reference model of
pfb_coeff_gen_init.m (counter reset by sync, one ROM per tap behind a
fan_latency delay, Register on the concatenated bus, din / sync delayed
bram_latency+1+fan_latency), with the ROM tables of
rtl/PFBs/scripts/gen_pfb_coeffs.py — not from the RTL. As an independent
check of the table arithmetic (pfb_coeff_gen_calc.m), the script
reassembles the tables of every input nput and tap into the full
TotalTaps·2^PFBSize-point filter and checks that it is symmetric about its
centre, which holds only with casper's half-sample time axis
t = 0.5 : 1 : alltaps-0.5.

Writes test_data/PFBs/<module>/simdataN/{params.json, sim_<port>.csv, *.mem}
and test_data.md, and prints the [[simulations]] blocks for
tests/simulation.toml.

Usage:
  python3 test_data/scripts/gen_pfb_test_data.py
"""

import json
import random
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli                     # also puts rtl/.../scripts on sys.path
from gen_butterfly_test_data import delay, write_csv, P, toml
from gen_pfb_coeffs import tap_table, write_tables

SCRIPT = Path(__file__).name
MDIR = TEST_DATA_ROOT / "PFBs" / "pfb_coeff_gen"
MEM_REL = "../../../test_data/PFBs/pfb_coeff_gen/simdata{n}/"

CG = ["PFB_SIZE", "COEFF_BIT_WIDTH", "TOTAL_TAPS", "WINDOW_TYPE", "BRAM_LATENCY", "N_INPUTS",
      "NPUT", "FWIDTH", "FAN_LATENCY", "DIN_WIDTH"]
CG_TESTS = [
    (P(CG, [5, 18, 4, "hamming", 2, 1, 0, 1.0, 1, 8]), "casper-style: 32 channels, 4 taps, 2 inputs, input 0"),
    (P(CG, [5, 18, 4, "hamming", 2, 1, 1, 1.0, 2, 9]), "same filter, input 1, fan latency 2"),
    (P(CG, [4, 12, 2, "hann", 1, 0, 0, 1.0, 0, 6]), "1 input, 2 taps, hann, minimum latencies"),
    (P(CG, [6, 16, 8, "blackman", 3, 2, 3, 0.8, 2, 10]), "8 taps, 4 inputs (input 3), blackman, fwidth 0.8"),
    (P(CG, [3, 10, 3, "rectwin", 1, 1, 1, 2.0, 1, 7]), "odd tap count, rectangular window, fwidth 2"),
    (P(CG, [6, 18, 4, "kaiser", 2, 2, 2, 1.0, 1, 11]), "kaiser (beta 0.5), 4 inputs (input 2)"),
]


def m_counter(rst, bits):
    cnt, out = 0, []
    for r in rst:
        out.append(cnt)
        cnt = 0 if r else (cnt + 1) % (1 << bits)
    return out


def m_pfb_coeff_gen(p, st, tables):
    """tables[a-1] = raw words of ROM a."""
    b, fan = p["BRAM_LATENCY"], p["FAN_LATENCY"]
    dly = b + 1 + fan
    addr = delay(m_counter(st["sync"], p["PFB_SIZE"] - p["N_INPUTS"]), fan, 0)
    coeff_cols = []
    for tab in tables:
        rom_q = [0] + [tab[x] for x in addr[:-1]]          # rom: registered read, powers up 0
        coeff_cols.append(delay(delay(rom_q, b - 1, 0), 1, 0))
    return {"dout": delay(st["din"], dly, 0), "sync_out": delay(st["sync"], dly, 0),
            "coeff": [list(r) for r in zip(*coeff_cols)]}


def check_symmetric(p):
    """Reassemble the full filter from all inputs / taps; it must be symmetric."""
    f, t, ni, cbw = p["PFB_SIZE"], p["TOTAL_TAPS"], p["N_INPUTS"], p["COEFF_BIT_WIDTH"]
    full = [None] * (t << f)
    for nput in range(1 << ni):
        for a in range(1, t + 1):
            tab = tap_table(f, t, p["WINDOW_TYPE"], ni, nput, p["FWIDTH"], a, cbw)
            for i, v in enumerate(tab):
                full[(a - 1) * (1 << f) + nput + i * (1 << ni)] = v
    assert None not in full, "tables do not cover the filter"
    assert full == full[::-1], "filter is not symmetric (half-sample time axis broken)"
    return len(full)


def gen_pfb_coeff_gen():
    sets = []
    for n, (p, desc) in enumerate(CG_TESTS):
        rng = random.Random(f"pfb_coeff_gen-{n}")
        frame = 1 << (p["PFB_SIZE"] - p["N_INPUTS"])
        cycles = max(128, 6 * frame + 32)
        sync = [1 if t >= 3 and (t - 3) % frame == 0 else 0 for t in range(cycles)]
        t_early = cycles // 2 + frame // 3                 # one early re-sync
        sync[t_early] = 1
        st = {"din": [rng.randrange(1 << p["DIN_WIDTH"]) for _ in range(cycles)], "sync": sync}
        st["din"][0] = 0
        d = MDIR / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        for old in d.glob("*.mem"):
            old.unlink()
        write_tables(d, p["PFB_SIZE"], p["TOTAL_TAPS"], p["WINDOW_TYPE"], p["N_INPUTS"], p["NPUT"],
                     p["FWIDTH"], p["COEFF_BIT_WIDTH"])
        tables = [tap_table(p["PFB_SIZE"], p["TOTAL_TAPS"], p["WINDOW_TYPE"], p["N_INPUTS"],
                            p["NPUT"], p["FWIDTH"], a, p["COEFF_BIT_WIDTH"])
                  for a in range(1, p["TOTAL_TAPS"] + 1)]
        out = m_pfb_coeff_gen(p, st, tables)
        taps = check_symmetric(p)
        full = dict(p, COEFF_DIR=MEM_REL.format(n=n))
        (d / "params.json").write_text(json.dumps(full, indent=2) + "\n")
        write_csv(d / "sim_din.csv", st["din"])
        write_csv(d / "sim_sync.csv", st["sync"])
        for k in ("dout", "sync_out", "coeff"):
            write_csv(d / f"sim_{k}.csv", out[k])
        sets.append((full, desc, cycles, taps))
    lines = [
        "# pfb_coeff_gen test data", "",
        "`pfb_coeff_gen` reads one coefficient ROM per tap, addressed by a "
        "sync-reset counter, and delays `din` / `sync` to match. `sync` pulses "
        "every 2^(PFB_SIZE−N_INPUTS) cycles plus one early re-sync mid-run "
        "(the counter restarts); `din` is random.", "",
        "Generated by `test_data/scripts/gen_pfb_test_data.py` (reference "
        "model of `pfb_coeff_gen_init.m`, not exported from MATLAB). The ROM "
        "tables (`pfb_coeff_n<NPUT>_t<a>.mem`) come from "
        "`rtl/PFBs/scripts/gen_pfb_coeffs.py`; `COEFF_DIR` is relative to "
        "`tests/sim_build/PFBs/pfb_coeff_gen/`. The script also reassembles "
        "the tables of all inputs and taps into the full filter and checks "
        "that it is symmetric (column *Filter length checked*), which holds "
        "only with casper's half-sample time axis. CSV rows are cycles; "
        "`sim_coeff.csv` has one column per tap (tap 1 first).", "",
        "| Test # | Directory | " + " | ".join(CG) + " | Filter length checked | Cycles | Description |",
        "|" + "---|" * (len(CG) + 5),
    ]
    for n, (full, desc, cycles, taps) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(full[k]) for k in CG)
                     + f" | {taps} | {cycles} | {desc} |")
    (MDIR / "test_data.md").write_text("\n".join(lines) + "\n")
    return toml("PFBs", "pfb_coeff_gen", [(full, desc) for full, desc, *_ in sets], SCRIPT)


def main():
    run_cli(__doc__, {"pfb_coeff_gen": gen_pfb_coeff_gen})


if __name__ == "__main__":
    main()
