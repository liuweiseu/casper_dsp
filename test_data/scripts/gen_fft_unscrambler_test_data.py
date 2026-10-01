#!/usr/bin/env python3
"""Generate test data for rtl/FFTs/fft_unscrambler.

Expected outputs chain the square_transposer and reorder reference models
of gen_reorder_test_data.py, with the map, ORDER, map latency, BRAM map and
fanout latency derived as fft_unscrambler_init.m does (not from the RTL).
As a check of the chain, the script also runs labelled samples through the
model and verifies that every output frame (after sync_out) holds exactly
one aligned input frame, all lanes, permuted the same way each frame.

Writes test_data/FFTs/fft_unscrambler/simdataN/{params.json, sim_<port>.csv,
map.mem} and test_data.md, and prints the [[simulations]] block for
tests/simulation.toml. din / dout have one column per element k = s·G + g
(stream s, group g); values are raw two's-complement words.

Usage:
  python3 test_data/scripts/gen_fft_unscrambler_test_data.py
"""

import json
import random
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli                     # also puts rtl/.../scripts on sys.path
from gen_butterfly_test_data import write_csv, P, toml
from gen_reorder_test_data import m_reorder, m_square_transposer
from gen_reorder_map import compute_order, mem_lines, unscrambler_map

SCRIPT = Path(__file__).name
MDIR = TEST_DATA_ROOT / "FFTs" / "fft_unscrambler"
MAP_REL = "../../../test_data/FFTs/fft_unscrambler/simdata{n}/map.mem"

FU = ["N_STREAMS", "FFT_SIZE", "LOG2_N_GROUPS", "N_BITS_IN", "BRAM_LATENCY", "COEFFS_BIT_LIMIT"]
FU_TESTS = [
    (P(FU, [1, 5, 1, 8, 2, 8]), "2 groups, order 4, distributed map (map latency 1)"),
    (P(FU, [2, 6, 2, 12, 2, 4]), "2 streams × 4 groups, order 2, BRAM map (map latency 2)"),
    (P(FU, [2, 8, 2, 36, 1, 8]), "2 streams × 4 groups, order 3, BRAM map, fanout latency 1"),
    (P(FU, [1, 13, 6, 6, 2, 8]), "64 groups, order 7, map latency 3, fanout latency 1"),
    (P(FU, [1, 5, 1, 8, 1, 6]), "BRAM-map threshold exactly met: 2^(FFT_SIZE-1)·(FFT_SIZE-1) = 2^COEFFS_BIT_LIMIT"),
]


def derived(p):
    """fft_unscrambler_init.m: map, ORDER, BRAM map, map latency, fanout latency."""
    f, n, b = p["FFT_SIZE"], p["LOG2_N_GROUPS"], p["N_BITS_IN"]
    perm = unscrambler_map(f, n)
    half = 2 ** (f - 1)
    bram_map = half * (f - 1) >= 2 ** p["COEFFS_BIT_LIMIT"] and half >= p["BRAM_LATENCY"]
    map_lat = (3 if f - 1 > 11 else 2) if bram_map else 1
    fanout = max(0, (f - n) + (b * n * 2 - 1).bit_length() - 15 + 2)
    return perm, compute_order(perm), int(bram_map), map_lat, fanout


def m_fft_unscrambler(p, st, word_bits=None):
    """st: din_re / din_im rows (N_STREAMS·G elements, k = s·G + g), sync.

    word_bits overrides the packing width only (for labelled runs); the
    derived latencies always follow p.
    """
    ns, n = p["N_STREAMS"], p["LOG2_N_GROUPS"]
    b = word_bits or p["N_BITS_IN"]
    g_n = 1 << n
    perm, order, _, map_lat, fanout = derived(p)
    words = [[sum(re[s * g_n + g] << (2 * s * b) | im[s * g_n + g] << ((2 * s + 1) * b)
                  for s in range(ns)) for g in range(g_n)]
             for re, im in zip(st["din_re"], st["din_im"])]
    tr = m_square_transposer(n, words, st["sync"])
    q = {"N_STREAMS": g_n, "MAP_LEN": len(perm), "ORDER": order, "MAP_LATENCY": map_lat,
         "BRAM_LATENCY": p["BRAM_LATENCY"], "FANOUT_LATENCY": fanout}
    ro = m_reorder(q, perm, {"din": tr["dout"], "sync": tr["sync_out"]})
    mask = (1 << b) - 1
    out = {"dout_re": [], "dout_im": [], "sync_out": ro["sync_out"]}
    for row in ro["dout"]:
        re, im = [0] * (ns * g_n), [0] * (ns * g_n)
        for g, w in enumerate(row):
            for s in range(ns):
                re[s * g_n + g] = (w >> (2 * s * b)) & mask
                im[s * g_n + g] = (w >> ((2 * s + 1) * b)) & mask
        out["dout_re"].append(re)
        out["dout_im"].append(im)
    return out


def sync_train(cycles, period, first=3):
    return [1 if t >= first and (t - first) % period == 0 else 0 for t in range(cycles)]


def check_frames(p, cycles, period):
    """Labelled run: each output frame is one aligned input frame, permuted alike."""
    ns, g_n = p["N_STREAMS"], 1 << p["LOG2_N_GROUPS"]
    map_len = len(derived(p)[0])
    # label = t · (ns·G) + element in the real part (wide words), im = -label
    lab = [[t * ns * g_n + k for k in range(ns * g_n)] for t in range(cycles)]
    st = {"din_re": lab, "din_im": [[x + 1 for x in r] for r in lab],
          "sync": sync_train(cycles, period)}
    out = m_fft_unscrambler(p, st, word_bits=40)
    in_start = st["sync"].index(1) + 1
    pattern, checked = None, 0
    for so in [t + 1 for t, s in enumerate(out["sync_out"]) if s]:
        for fs in range(so, cycles - map_len + 1, map_len):
            labels = [out["dout_re"][fs + i][k] for i in range(map_len) for k in range(ns * g_n)]
            assert all(out["dout_im"][fs + i][k] == out["dout_re"][fs + i][k] + 1
                       for i in range(map_len) for k in range(ns * g_n)), "re / im split"
            times = sorted({x // (ns * g_n) for x in labels})
            t0 = times[0]
            if t0 < in_start:                    # still the power-on contents
                continue
            assert times == list(range(t0, t0 + map_len)), "output frame is not one input frame"
            assert (t0 - in_start) % map_len == 0, "frame not aligned to the input sync"
            assert sorted(labels) == list(range(t0 * ns * g_n, (t0 + map_len) * ns * g_n))
            rel = [x - t0 * ns * g_n for x in labels]
            assert pattern in (None, rel), "permutation differs between frames"
            pattern = rel
            checked += 1
        break                                    # frames after the first sync_out
    assert checked >= 2, "too few frames"
    return checked


def gen():
    sets = []
    for n, (p, desc) in enumerate(FU_TESTS):
        rng = random.Random(f"fft_unscrambler-{n}")
        perm, order, bram_map, map_lat, fanout = derived(p)
        period = order * len(perm)
        cycles = 3 + 2 * period + 2 * len(perm) + 64
        elems = p["N_STREAMS"] << p["LOG2_N_GROUPS"]
        st = {k: [[0] * elems] + [[rng.randrange(1 << p["N_BITS_IN"]) for _ in range(elems)]
                                  for _ in range(cycles - 1)] for k in ("din_re", "din_im")}
        st["sync"] = sync_train(cycles, period)
        out = m_fft_unscrambler(p, st)
        frames = check_frames(p, cycles, period)
        d = MDIR / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        full = dict(p, MAP_INIT_FILE=MAP_REL.format(n=n))
        (d / "params.json").write_text(json.dumps(dict(full, ORDER=order, BRAM_MAP=bram_map,
                                                       MAP_LATENCY=map_lat, FANOUT_LATENCY=fanout),
                                                  indent=2) + "\n")
        (d / "map.mem").write_text("".join(x + "\n" for x in mem_lines(perm)[1]))
        for k in ("din_re", "din_im", "sync"):
            write_csv(d / f"sim_{k}.csv", st[k])
        for k in ("dout_re", "dout_im", "sync_out"):
            write_csv(d / f"sim_{k}.csv", out[k])
        sets.append((full, desc, cycles, order, bram_map, map_lat, fanout, frames))
    lines = [
        "# fft_unscrambler test data", "",
        "`fft_unscrambler` packs each group's `N_STREAMS` signals into one word, "
        "transposes the `2^LOG2_N_GROUPS` words with a square_transposer and "
        "reorders them with casper's unscrambler map. `sync` pulses every "
        "`ORDER · 2^(FFT_SIZE−LOG2_N_GROUPS)` cycles, as the reorder requires; "
        "`din` is random (row 0 zero).", "",
        "Generated by `test_data/scripts/gen_fft_unscrambler_test_data.py`: the "
        "square_transposer and reorder reference models of "
        "`gen_reorder_test_data.py` chained, with the map, ORDER, BRAM map, map "
        "latency and fanout latency derived as `fft_unscrambler_init.m` does "
        "(columns on the right; derived inside the RTL too). The script also "
        "checks with labelled samples that every output frame is one aligned "
        "input frame, permuted the same way each time (column *Frames "
        "checked*). Not exported from MATLAB. `map.mem` comes from "
        "`rtl/Reorder/scripts/gen_reorder_map.py --unscrambler`; "
        "`MAP_INIT_FILE` is relative to `tests/sim_build/FFTs/fft_unscrambler/`. "
        "CSV rows are cycles; din / dout have one column per element "
        "`s·G + g`.", "",
        "| Test # | Directory | " + " | ".join(FU) + " | ORDER | BRAM map | Map latency | "
        "Fanout latency | Frames checked | Cycles | Description |",
        "|" + "---|" * (len(FU) + 9),
    ]
    for n, (full, desc, cycles, order, bm, ml, fo, frames) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(full[k]) for k in FU)
                     + f" | {order} | {bm} | {ml} | {fo} | {frames} | {cycles} | {desc} |")
    (MDIR / "test_data.md").write_text("\n".join(lines) + "\n")
    return toml("FFTs", "fft_unscrambler", [(full, desc) for full, desc, *_ in sets], SCRIPT)


def main():
    run_cli(__doc__, {"fft_unscrambler": gen})


if __name__ == "__main__":
    main()
