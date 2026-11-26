#!/usr/bin/env python3
"""Generate test data for the rtl/PFBs/ modules.

first_tap_real / tap_real / last_tap_real: reference models of the taps'
internal diagrams in casper_library_pfbs.slx (data and sync advance by
delay per hop, the multiplier works on the tap's own undelayed input with
the lowest coefficient slice, the rest of the coefficient bus is forwarded
without delay). As an independent check of that structure the script runs
a whole chain — pfb_coeff_gen's tables, first_tap_real, tap_real ×
(TotalTaps-2), last_tap_real, exact sum — on integer data and compares
every output with the windowed-presum PFB computed from its definition,
y_c(f) = Σ_{j ≡ c mod 2^PFBSize} h[j]·x[(f-TotalTaps+1)·2^PFBSize + j],
for several PFBSize / TotalTaps / n_inputs / n_pol_blocks; it also checks
that any other per-hop delay than 2^(PFBSize-n_inputs)·n_pol_blocks fails.

pfb_fir_real: the whole block as pfb_fir_real_init.m wires it, from the
models above plus adder_tree (gen_adder_tree_test_data.py), Scale and
Convert. End-to-end checks on every output frame (n_pol_blocks = 1, periodic
sync): the output equals, bit for bit, the windowed presum computed exactly
from its definition with the quantized coefficients, then scaled and
converted (so the Wrap-mode bit growth never loses a bit), and it is within
a few output LSBs of the same PFB computed in floating point with the
unquantized window·sinc coefficients.

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
from gen_pfb_coeffs import (all_coeffs, pfb_fir_real_params, quantize_coeff, tap_table,
                            write_pfb_fir_real, write_tables)
from gen_adder_tree_test_data import AT, m_adder_tree
from gen_fixed_point_test_data import quantize, to_value
from gen_fft_stage_test_data import m_sync_delay

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
        "`sim_coeff<j>.csv` holds tap j + 1 (`coeff[j]`).", "",
        "| Test # | Directory | " + " | ".join(CG) + " | Filter length checked | Cycles | Description |",
        "|" + "---|" * (len(CG) + 5),
    ]
    for n, (full, desc, cycles, taps) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(full[k]) for k in CG)
                     + f" | {taps} | {cycles} | {desc} |")
    (MDIR / "test_data.md").write_text("\n".join(lines) + "\n")
    return toml("PFBs", "pfb_coeff_gen", [(full, desc) for full, desc, *_ in sets], SCRIPT)


# ── taps ────────────────────────────────────────────────────────────────────

def signed(v, w):
    return v - (1 << w) if v >= 1 << (w - 1) else v


def product(a, wa, b, wb):
    """Full-precision signed product as a raw (wa+wb)-bit word."""
    return (signed(a, wa) * signed(b, wb)) % (1 << (wa + wb))


def m_tap_real(p, st):
    dw, cw, nc = p["DATA_WIDTH"], p["COEFF_WIDTH"], p["N_COEFFS"]
    return {"dout": delay(st["din"], p["DELAY"], 0),
            "sync_out": m_sync_delay(st["sync"], p["DELAY"]),
            "coeff_out": [c >> cw for c in st["coeff"]],
            "taps_out": delay([product(d, dw, c & ((1 << cw) - 1), cw)
                               for d, c in zip(st["din"], st["coeff"])], p["MULT_LATENCY"], 0)}


def first_tap_as_tap(p):
    return {"MULT_LATENCY": p["MULT_LATENCY"], "COEFF_WIDTH": p["COEFF_BIT_WIDTH"],
            "COEFF_FRAC_WIDTH": p["COEFF_BIT_WIDTH"] - 1,
            "DELAY": (1 << (p["PFB_SIZE"] - p["N_INPUTS"])) * p["N_POL_BLOCKS"],
            "DATA_WIDTH": p["BIT_WIDTH_IN"], "BRAM_LATENCY": p["BRAM_LATENCY"],
            "N_COEFFS": p["TOTAL_TAPS"]}


def m_last_tap_real(p, st):
    bw, cbw = p["BIT_WIDTH_IN"], p["COEFF_BIT_WIDTH"]
    return {"tap_out": delay([product(d, bw, c, cbw) for d, c in zip(st["din"], st["coeff"])],
                             p["MULT_LATENCY"], 0),
            "sync_out": delay(st["sync"], p["MULT_LATENCY"], 0)}


def tap_stimulus(rng, cycles, dw, bus_w, sync_period):
    din = [0] + [rng.randrange(1 << dw) for _ in range(cycles - 1)]
    coeff = [0] + [rng.randrange(1 << bus_w) for _ in range(cycles - 1)]
    m = 1 << (dw - 1)
    for i, v in enumerate([m, m - 1, m + 1, (1 << dw) - 1, 1]):   # corner data words
        din[1 + i] = v
        coeff[1 + i] = (1 << bus_w) - 1 if i % 2 else 1 << (bus_w - 1)
    sync = [1 if t >= 3 and (t - 3) % sync_period == 0 else 0 for t in range(cycles)]
    sync[cycles // 2 + sync_period // 3] = 1                      # one early re-sync
    return {"din": din, "coeff": coeff, "sync": sync}


def check_tap_chain_is_wola(configs=((4, 4, 0, 1), (5, 4, 1, 1), (5, 3, 1, 2), (4, 8, 2, 1), (6, 2, 0, 3)),
                            cbw=18, window_type="hamming"):
    """Chain first_tap_real → tap_real… → last_tap_real (+ exact sum) = windowed-presum PFB.

    Returns (outputs checked, configurations). Also asserts that hop delays
    other than 2^(PFBSize-n_inputs)·n_pol_blocks give wrong outputs.
    """
    total_checked = 0
    for pfb, taps, ni, npol in configs:
        rng = random.Random(f"chain-{pfb}-{taps}-{ni}-{npol}")
        n_ch, blk = 1 << pfb, 1 << (pfb - ni)
        hop = blk * npol
        h = [quantize_coeff(v, cbw) for v in all_coeffs(pfb, taps, window_type, 1.0)]
        nfr = 3 * taps + 2
        x = [[rng.randrange(-500, 500) for _ in range(nfr * n_ch)] for _ in range(npol)]
        cycles = nfr * npol * blk
        sync = [1 if t % blk == blk - 1 else 0 for t in range(cycles)]   # counter 0 at block starts

        def run_chain(n, hop_delay):
            stream = [0] * cycles
            for f in range(nfr):
                for pl in range(npol):
                    for k in range(blk):
                        stream[(f * npol + pl) * blk + k] = x[pl][f * n_ch + k * (1 << ni) + n]
            tabs = [[signed(v, cbw) for v in tap_table(pfb, taps, window_type, ni, n, 1.0, a, cbw)]
                    for a in range(1, taps + 1)]
            k_of = [0] + [(0 if sync[t - 1] else None) for t in range(1, cycles)]
            for t in range(1, cycles):
                if k_of[t] is None:
                    k_of[t] = (k_of[t - 1] + 1) % blk
            # bus: ROM 1 = MSB, so the LSB slice (tap 1) is ROM TotalTaps
            out = []
            for t in range(cycles):
                bus = [tabs[a][k_of[t]] for a in range(taps)]          # bus[a] = ROM a+1
                acc, data = 0, t
                for tap in range(taps):                                # tap+1 = tap number
                    i = t - tap * hop_delay
                    acc += (stream[i] if i >= 0 else 0) * bus[taps - 1 - tap]
                out.append(acc)
            return out

        for n in range(1 << ni):
            good, bad = run_chain(n, hop), [run_chain(n, d) for d in (hop - 1, hop + 1, 0)]
            for t in range(cycles):
                b, k = divmod(t, blk)
                f, pl = divmod(b, npol)
                if f < taps:
                    continue
                c = k * (1 << ni) + n
                ref = sum(h[j] * x[pl][(f - taps + 1) * n_ch + j] for j in range(c, taps * n_ch, n_ch))
                assert good[t] == ref, f"tap chain is not a PFB (cfg {pfb, taps, ni, npol})"
                total_checked += 1
            for wrong in bad:
                assert any(wrong[t] != good[t] for t in range(taps * npol * blk, cycles)), \
                    "a wrong hop delay was not detected"
    return total_checked, len(configs)


FT = ["PFB_SIZE", "N_INPUTS", "N_POL_BLOCKS", "COEFF_BIT_WIDTH", "TOTAL_TAPS", "BIT_WIDTH_IN",
      "MULT_LATENCY", "BRAM_LATENCY"]
FT_TESTS = [
    (P(FT, [6, 1, 1, 8, 4, 8, 2, 2]), "casper mask defaults: delay 32, 4 taps"),
    (P(FT, [5, 0, 2, 18, 3, 18, 3, 1]), "1 input, 2 serial polarisations: delay 64"),
    (P(FT, [4, 2, 1, 12, 2, 10, 1, 2]), "2 taps (forwards one coefficient), delay 4"),
]
TR = ["MULT_LATENCY", "COEFF_WIDTH", "COEFF_FRAC_WIDTH", "DELAY", "DATA_WIDTH", "BRAM_LATENCY",
      "N_COEFFS"]
TR_TESTS = [
    (P(TR, [2, 12, 11, 4, 8, 1, 3]), "tap_real mask defaults (coeff_frac_width as pfb_fir_real sets it)"),
    (P(TR, [1, 18, 17, 16, 18, 2, 2]), "18-bit data and coefficients, delay 16, one coefficient forwarded"),
    (P(TR, [3, 10, 9, 32, 12, 2, 5]), "5 coefficients on the bus, delay 32"),
    (P(TR, [0, 8, 7, 2, 8, 1, 2]), "combinational multiplier, delay 2"),
]
LT = ["BIT_WIDTH_IN", "COEFF_BIT_WIDTH", "MULT_LATENCY"]
LT_TESTS = [
    (P(LT, [8, 8, 2]), "mask defaults"),
    (P(LT, [18, 18, 3]), "18-bit data and coefficients"),
    (P(LT, [12, 10, 0]), "combinational multiplier"),
]


def tap_md(name, keys, sets, prose):
    mdir = TEST_DATA_ROOT / "PFBs" / name
    lines = [f"# {name} test data", "", prose, "",
             "Generated by `test_data/scripts/gen_pfb_test_data.py` (reference model of "
             "the block's internal diagram in casper_library_pfbs.slx, not exported "
             "from MATLAB). Data and coefficient words are random, with corner "
             "words (most negative × most negative, …) at the start; `sync` pulses "
             "periodically plus one early re-sync. CSV rows are cycles; values are "
             "raw words.", "",
             "| Test # | Directory | " + " | ".join(keys) + " | Cycles | Description |",
             "|" + "---|" * (len(keys) + 4)]
    for n, (p, desc, cycles) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(p[k]) for k in keys)
                     + f" | {cycles} | {desc} |")
    (mdir / "test_data.md").write_text("\n".join(lines) + "\n")


def write_tap_set(name, n, p, ports):
    d = TEST_DATA_ROOT / "PFBs" / name / f"simdata{n}"
    d.mkdir(parents=True, exist_ok=True)
    (d / "params.json").write_text(json.dumps(p, indent=2) + "\n")
    for k, v in ports.items():
        write_csv(d / f"sim_{k}.csv", v)


def gen_tap_real():
    sets = []
    checked, n_cfg = check_tap_chain_is_wola()
    for n, (p, desc) in enumerate(TR_TESTS):
        rng = random.Random(f"tap_real-{n}")
        cycles = max(128, 6 * p["DELAY"])
        st = tap_stimulus(rng, cycles, p["DATA_WIDTH"], p["N_COEFFS"] * p["COEFF_WIDTH"], 2 * p["DELAY"])
        write_tap_set("tap_real", n, p, {**st, **m_tap_real(p, st)})
        sets.append((p, desc, cycles))
    tap_md("tap_real", TR, sets,
           "`tap_real` multiplies its own input sample by the lowest COEFF_WIDTH "
           "bits of the coefficient bus, forwards the rest of the bus without "
           "delay and delays data and sync by DELAY. Chain check: a whole "
           "first_tap_real → tap_real → last_tap_real chain was compared with the "
           "windowed-presum PFB definition on integer data: "
           f"{checked} outputs in {n_cfg} configurations (PFBSize 4–6, 2–8 taps, "
           "n_inputs 0–2, n_pol_blocks 1–3) matched exactly, and per-hop delays "
           "of delay−1, delay+1 and 0 were all detected as wrong.")
    return toml("PFBs", "tap_real", [(p, d) for p, d, _ in sets], SCRIPT)


def gen_first_tap_real():
    sets = []
    for n, (p, desc) in enumerate(FT_TESTS):
        rng = random.Random(f"first_tap_real-{n}")
        q = first_tap_as_tap(p)
        cycles = max(128, 6 * q["DELAY"])
        st = tap_stimulus(rng, cycles, p["BIT_WIDTH_IN"], p["TOTAL_TAPS"] * p["COEFF_BIT_WIDTH"], 2 * q["DELAY"])
        write_tap_set("first_tap_real", n, p, {**st, **m_tap_real(q, st)})
        sets.append((p, desc, cycles))
    tap_md("first_tap_real", FT, sets,
           "`first_tap_real` is tap_real with DELAY = 2^(PFB_SIZE−N_INPUTS)·N_POL_BLOCKS "
           "and the full TOTAL_TAPS-coefficient bus of pfb_coeff_gen (it uses the "
           "lowest slice, ROM TOTAL_TAPS).")
    return toml("PFBs", "first_tap_real", [(p, d) for p, d, _ in sets], SCRIPT)


def gen_last_tap_real():
    sets = []
    for n, (p, desc) in enumerate(LT_TESTS):
        rng = random.Random(f"last_tap_real-{n}")
        cycles = 128
        st = tap_stimulus(rng, cycles, p["BIT_WIDTH_IN"], p["COEFF_BIT_WIDTH"], 16)
        write_tap_set("last_tap_real", n, p, {**st, **m_last_tap_real(p, st)})
        sets.append((p, desc, cycles))
    tap_md("last_tap_real", LT, sets,
           "`last_tap_real` multiplies its input sample by the last coefficient "
           "on the bus and delays sync by MULT_LATENCY (for the adder_tree); "
           "nothing is forwarded.")
    return toml("PFBs", "last_tap_real", [(p, d) for p, d, _ in sets], SCRIPT)


# ── pfb_fir_real ────────────────────────────────────────────────────────────

FR = ["PFB_SIZE", "TOTAL_TAPS", "WINDOW_TYPE", "N_INPUTS", "N_POL_BLOCKS", "MAKE_BIPLEX",
      "BIT_WIDTH_IN", "BIT_WIDTH_OUT", "COEFF_BIT_WIDTH", "ADD_LATENCY", "MULT_LATENCY",
      "BRAM_LATENCY", "FAN_LATENCY", "CONV_LATENCY", "QUANTIZATION", "FWIDTH", "COEFFS_SHARE"]
FR_TESTS = [
    (P(FR, [5, 2, "hamming", 1, 1, 0, 8, 0, 18, 1, 2, 2, 1, 1, 1, 1.0, 0]), False,
     "casper mask defaults (BitWidthOut 0: full adder width)"),
    (P(FR, [4, 4, "hann", 1, 1, 1, 10, 12, 16, 1, 2, 2, 1, 1, 2, 1.0, 0]), False,
     "2 pols (MakeBiplex), 4 taps, 12-bit output rounded to even"),
    (P(FR, [4, 4, "hann", 1, 1, 1, 10, 12, 16, 1, 2, 2, 1, 1, 2, 1.0, 1]), False,
     "as test 1 with coeffs_share: pol 2 uses pol 1's coefficients (same outputs)"),
    (P(FR, [6, 8, "blackman", 2, 1, 0, 12, 0, 18, 2, 3, 2, 2, 2, 1, 0.8, 0]), False,
     "64 channels, 8 taps, 4 inputs, fwidth 0.8"),
    (P(FR, [3, 3, "rectwin", 0, 2, 1, 8, 19, 12, 0, 0, 1, 0, 0, 1, 2.0, 0]), True,
     "2 serial pol blocks, odd taps, combinational adders / multipliers / convert, "
     "BitWidthOut 19 > adder binary point 18: forced Truncate drops one bit (mask says "
     "round), early re-sync"),
]


def fr_derived(p):
    d = pfb_fir_real_params(p["PFB_SIZE"], p["TOTAL_TAPS"], p["WINDOW_TYPE"], p["FWIDTH"],
                            p["BIT_WIDTH_IN"], p["COEFF_BIT_WIDTH"], p["BIT_WIDTH_OUT"])
    d["OUT_QUANT"] = 0 if d["BIT_WIDTH_OUT"] > d["ADDER_BIN_PT_OUT"] else p["QUANTIZATION"]
    return d


def m_pfb_fir_real(p, st):
    """st: din rows (POLS·2^N_INPUTS raw words, element (p-1)·2^n_inputs + n-1), sync."""
    d = fr_derived(p)
    t_, cbw, bw = p["TOTAL_TAPS"], p["COEFF_BIT_WIDTH"], p["BIT_WIDTH_IN"]
    ni, pols = 1 << p["N_INPUTS"], 2 if p["MAKE_BIPLEX"] else 1
    share = p["MAKE_BIPLEX"] and p["COEFFS_SHARE"]
    cg_dly = p["BRAM_LATENCY"] + 1 + p["FAN_LATENCY"]
    cycles = len(st["sync"])
    hop = (1 << (p["PFB_SIZE"] - p["N_INPUTS"])) * p["N_POL_BLOCKS"]
    pw = bw + cbw
    cg, outs = {}, [[0] * (pols * ni) for _ in range(cycles)]
    sync_out = None
    for pl in range(pols):
        for n in range(ni):
            col = [row[pl * ni + n] for row in st["din"]]
            if pl == 1 and share:
                data, bus = delay(col, cg_dly, 0), cg[(0, n)]["bus"]
            else:
                cgp = {"PFB_SIZE": p["PFB_SIZE"], "N_INPUTS": p["N_INPUTS"], "BRAM_LATENCY": p["BRAM_LATENCY"],
                       "FAN_LATENCY": p["FAN_LATENCY"]}
                tabs = [tap_table(p["PFB_SIZE"], t_, p["WINDOW_TYPE"], p["N_INPUTS"], n, p["FWIDTH"], a, cbw)
                        for a in range(1, t_ + 1)]
                o = m_pfb_coeff_gen(cgp, {"din": col, "sync": st["sync"]}, tabs)
                bus = [sum(c << ((t_ - 1 - a) * cbw) for a, c in enumerate(row)) for row in o["coeff"]]
                data = o["dout"]
                cg[(pl, n)] = {"bus": bus, "sync": o["sync_out"]}
            # taps
            first_sync = cg[(0, 0)]["sync"]
            prods = []
            tp = {"MULT_LATENCY": p["MULT_LATENCY"], "COEFF_WIDTH": cbw, "DELAY": hop,
                  "DATA_WIDTH": bw, "N_COEFFS": t_}
            cur = {"din": data, "sync": first_sync, "coeff": bus}
            for t in range(t_ - 1):
                o = m_tap_real(dict(tp, N_COEFFS=t_ - t), cur)
                prods.append(o["taps_out"])
                cur = {"din": o["dout"], "sync": o["sync_out"], "coeff": o["coeff_out"]}
            o = m_last_tap_real({"BIT_WIDTH_IN": bw, "COEFF_BIT_WIDTH": cbw,
                                 "MULT_LATENCY": p["MULT_LATENCY"]}, cur)
            prods.append(o["tap_out"])
            ap = P(AT, [t_, pw, pw - 2, 1, p["ADD_LATENCY"], 1, d["ADDER_N_BITS_OUT"],
                        d["ADDER_BIN_PT_OUT"], 0, 0])
            ao, aw = m_adder_tree(ap, {"din": [list(r) for r in zip(*prods)], "sync": o["sync_out"]})
            bp_scaled = d["ADDER_BIN_PT_OUT"] - d["SCALE_FACTOR"]
            nbo = d["BIT_WIDTH_OUT"]
            conv = [quantize(to_value(v, aw, bp_scaled, 1), nbo, nbo - 1, 1, d["OUT_QUANT"], 0)
                    for v in ao["dout"]]
            conv = delay(conv, p["CONV_LATENCY"], 0)
            for tt in range(cycles):
                outs[tt][pl * ni + n] = conv[tt]
            if pl == 0 and n == 0:
                sync_out = delay(ao["sync_out"], p["CONV_LATENCY"], 0)
    return {"dout": outs, "sync_out": sync_out}


def fr_stimulus(rng, p, early_resync):
    ni, pols = 1 << p["N_INPUTS"], 2 if p["MAKE_BIPLEX"] else 1
    blk = 1 << (p["PFB_SIZE"] - p["N_INPUTS"])
    period = blk * p["N_POL_BLOCKS"]
    cycles = (p["TOTAL_TAPS"] + 6) * period + 64
    bw = p["BIT_WIDTH_IN"]
    din = [[0] * (pols * ni)] + [[rng.randrange(1 << bw) for _ in range(pols * ni)]
                                 for _ in range(cycles - 1)]
    sync = [1 if t >= 3 and (t - 3) % period == 0 else 0 for t in range(cycles)]
    if early_resync:
        sync[cycles // 2 + blk // 3] = 1
    return {"din": din, "sync": sync}


def check_pfb_fir_real(p, st, out):
    """Exact and floating-point end-to-end checks (n_pol_blocks = 1, periodic sync)."""
    d = fr_derived(p)
    f_, t_, ni_b = p["PFB_SIZE"], p["TOTAL_TAPS"], p["N_INPUTS"]
    ni, pols, n_ch, blk = 1 << ni_b, 2 if p["MAKE_BIPLEX"] else 1, 1 << f_, 1 << (f_ - ni_b)
    bw, cbw, nbo = p["BIT_WIDTH_IN"], p["COEFF_BIT_WIDTH"], d["BIT_WIDTH_OUT"]
    cycles = len(st["sync"])
    hq = [quantize_coeff(v, cbw) for v in all_coeffs(f_, t_, p["WINDOW_TYPE"], p["FWIDTH"])]
    hf = all_coeffs(f_, t_, p["WINDOW_TYPE"], p["FWIDTH"])
    s0 = st["sync"].index(1) + 1                      # first input frame
    n_in_frames = (cycles - s0) // blk
    # global sample stream of each pol: frame g, channel c = k·2^n_inputs + n
    x = [[signed(st["din"][s0 + g * blk + c // ni][pl * ni + c % ni], bw)
          for g in range(n_in_frames) for c in range(n_ch)] for pl in range(pols)]
    starts = [t + 1 for t, v in enumerate(out["sync_out"]) if v and t + 1 + blk <= cycles]
    lag, frames, worst = None, 0, 0.0
    bp_out = nbo - 1
    for so in starts:
        # which input frame does this output frame belong to? (latency is fixed)
        cand = None
        for f in range(t_ - 1, n_in_frames):
            ok = True
            for pl in range(pols):
                for c in range(n_ch):
                    acc = sum(hq[j] * x[pl][(f - t_ + 1) * n_ch + j] for j in range(c, t_ * n_ch, n_ch))
                    val = acc / 2 ** (bw - 1 + cbw - 1) * 2 ** d["SCALE_FACTOR"]
                    exp = quantize(val, nbo, bp_out, 1, d["OUT_QUANT"], 0)
                    if out["dout"][so + c // ni][pl * ni + c % ni] != exp:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                cand = f
                break
        if cand is None:
            continue                                  # pipeline still filling
        assert lag in (None, so - (s0 + cand * blk)), "frame latency changes"
        lag = so - (s0 + cand * blk)
        frames += 1
        for pl in range(pols):
            for c in range(n_ch):
                accf = sum(hf[j] * x[pl][(cand - t_ + 1) * n_ch + j] / 2 ** (bw - 1)
                           for j in range(c, t_ * n_ch, n_ch)) * 2 ** d["SCALE_FACTOR"]
                got = to_value(out["dout"][so + c // ni][pl * ni + c % ni], nbo, bp_out, 1)
                worst = max(worst, abs(float(got) - accf))
    assert frames >= 3, "too few output frames match the exact windowed presum"
    # bound: coefficient rounding (T taps · ½ coefficient LSB · |x| ≤ 1), scaled,
    # plus one output LSB of conversion
    bound = t_ * 0.5 * 2.0 ** -(cbw - 1) * 2.0 ** d["SCALE_FACTOR"] + 2.0 ** -bp_out
    assert worst <= bound, f"output differs from the floating-point PFB by {worst:.3g} > {bound:.3g}"
    return frames, worst / bound


def gen_pfb_fir_real():
    name, sets = "pfb_fir_real", []
    mdir = TEST_DATA_ROOT / "PFBs" / name
    outs_by_set = {}
    for n, (p, early, desc) in enumerate(FR_TESTS):
        rng = random.Random(f"{name}-{n if n != 2 else 1}")     # test 2 = test 1's data
        st = fr_stimulus(rng, p, early)
        out = m_pfb_fir_real(p, st)
        outs_by_set[n] = out
        if p["N_POL_BLOCKS"] == 1 and not early:
            frames, worst = check_pfb_fir_real(p, st, out)
            check = f"{frames} frames exact; float error {worst:.0%} of bound"
        else:
            check = "n/a (bit-exact only)"
        d = fr_derived(p)
        dd = mdir / f"simdata{n}"
        dd.mkdir(parents=True, exist_ok=True)
        for old in dd.glob("*.mem"):
            old.unlink()
        write_pfb_fir_real(dd, p["PFB_SIZE"], p["TOTAL_TAPS"], p["WINDOW_TYPE"], p["N_INPUTS"],
                           p["FWIDTH"], p["COEFF_BIT_WIDTH"])
        full = dict(p, BIT_GROWTH=d["BIT_GROWTH"], ADDER_N_BITS_OUT=d["ADDER_N_BITS_OUT"],
                    ADDER_BIN_PT_OUT=d["ADDER_BIN_PT_OUT"], SCALE_FACTOR=d["SCALE_FACTOR"],
                    COEFF_DIR=f"../../../test_data/PFBs/{name}/simdata{n}/")
        (dd / "params.json").write_text(json.dumps(full, indent=2) + "\n")
        write_csv(dd / "sim_din.csv", st["din"])
        write_csv(dd / "sim_sync.csv", st["sync"])
        write_csv(dd / "sim_dout.csv", out["dout"])
        write_csv(dd / "sim_sync_out.csv", out["sync_out"])
        sets.append((full, desc, len(st["sync"]), check))
    assert outs_by_set[1] == outs_by_set[2], "coeffs_share changes the outputs"
    keys = FR + ["BIT_GROWTH", "ADDER_N_BITS_OUT", "SCALE_FACTOR"]
    lines = [
        "# pfb_fir_real test data", "",
        "`pfb_fir_real` is the whole real-input PFB FIR: per polarisation and "
        "input a pfb_coeff_gen, first_tap_real → tap_real × (TotalTaps−2) → "
        "last_tap_real, an adder_tree, Scale and Convert. The inputs are random "
        "full-scale words; `sync` pulses every 2^(PFB_SIZE−N_INPUTS)·N_POL_BLOCKS "
        "cycles (test 4 adds an early re-sync). BIT_GROWTH, ADDER_N_BITS_OUT and "
        "SCALE_FACTOR come from `rtl/PFBs/scripts/gen_pfb_coeffs.py` (as "
        "pfb_fir_real_init.m); the ROM files from the same script; `COEFF_DIR` "
        "is relative to `tests/sim_build/PFBs/pfb_fir_real/`.", "",
        "Generated by `test_data/scripts/gen_pfb_test_data.py` (reference "
        "model, not exported from MATLAB). *End-to-end check*: every output "
        "frame equals, bit for bit, the windowed presum computed from its "
        "definition with the quantized coefficients (then scaled and converted), "
        "and its difference from the floating-point PFB with the unquantized "
        "coefficients stays within the coefficient-rounding bound (TotalTaps · "
        "½ coefficient LSB, scaled, plus one output LSB; the column gives the "
        "worst error as a fraction of it). Test 2 (coeffs_share) uses test 1's inputs "
        "and the script checks that its outputs are identical. CSV rows are "
        "cycles; element (p−1)·2^N_INPUTS + n−1 is pol<p>_in<n> / pol<p>_out<n>.", "",
        "| Test # | Directory | " + " | ".join(keys) + " | End-to-end check | Cycles | Description |",
        "|" + "---|" * (len(keys) + 5),
    ]
    for n, (full, desc, cycles, check) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(full[k]) for k in keys)
                     + f" | {check} | {cycles} | {desc} |")
    (mdir / "test_data.md").write_text("\n".join(lines) + "\n")
    return toml("PFBs", name, [(full, desc) for full, desc, *_ in sets], SCRIPT)


def main():
    run_cli(__doc__, {"pfb_coeff_gen": gen_pfb_coeff_gen, "first_tap_real": gen_first_tap_real,
                      "tap_real": gen_tap_real, "last_tap_real": gen_last_tap_real,
                      "pfb_fir_real": gen_pfb_fir_real})


if __name__ == "__main__":
    main()
