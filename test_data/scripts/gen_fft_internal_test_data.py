#!/usr/bin/env python3
"""Generate test data for the rtl/FFTs/Internal/ modules.

Expected outputs come from Python reference models of casper_library's
complex_conj, hilbert, mirror_spectrum and bi_real_unscr_4x
(complex_conj_init.m, hilbert_init.m, mirror_spectrum_init.m,
bi_real_unscr_4x_init.m), not from the RTL. The fixed-point arithmetic uses
the exact models of gen_fixed_point_test_data.py, the reorders the model of
gen_reorder_test_data.py.

bi_real_unscr_4x is driven with the output of the biplex_core reference model
(gen_biplex_test_data.py) for four random real signals, as in
fft_biplex_real_4x, and the script checks with numpy that every output frame
is the FFT of the four signals (the upper half mirrored), which also fixes
the select polarities of bi_real_unscr_4x and mirror_spectrum.

Writes test_data/FFTs/Internal/<module>/simdataN/{params.json,
sim_<port>.csv[, map_*.mem]} and test_data.md, and prints the [[simulations]]
blocks for tests/simulation.toml. Array ports have one column per lane
(lane 0 first); values are raw two's-complement words.

Usage:
  python3 test_data/scripts/gen_fft_internal_test_data.py
  python3 test_data/scripts/gen_fft_internal_test_data.py --module hilbert
"""

import json
import random
import sys
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli                     # also puts rtl/.../scripts on sys.path
from gen_butterfly_test_data import delay, write_csv, P, toml
from gen_fixed_point_test_data import corners, quantize, to_value
from gen_fft_stage_test_data import m_sync_delay
from gen_biplex_test_data import BC, m_biplex_core, signed
from gen_reorder_test_data import m_reorder
from gen_reorder_map import bi_real_map, compute_order, mem_lines

SCRIPT = Path(__file__).name
CATEGORY = "FFTs/Internal"
TEST_DATA = TEST_DATA_ROOT / "FFTs" / "Internal"
MAP_REL = "../../../../test_data/FFTs/Internal/bi_real_unscr_4x/simdata{n}/"


# ── helpers ─────────────────────────────────────────────────────────────────

def lanes_stim(rng, cycles, n, bits, corner_rows=True):
    """cycles rows of n raw words: row 0 all zero, then corners, then random."""
    cs = corners(bits)
    rows = [[0] * n]
    if corner_rows:
        rows += [[cs[(i + l) % len(cs)] for l in range(n)] for i in range(2 * len(cs))]
    while len(rows) < cycles:
        rows.append([rng.randrange(1 << bits) for _ in range(n)])
    return rows[:cycles]


def per_lane(fn, *ports):
    """Apply fn(values of one lane at one cycle) -> tuple to rows of lanes."""
    out = []
    for rows in zip(*ports):
        out.append([fn(*vals) for vals in zip(*rows)])
    return out


def column(rows, i):
    return [r[i] for r in rows]


def m_counter(rst, bits):
    """casper Counter, free running up, rst: cleared the cycle after rst."""
    cnt, out = 0, []
    for r in rst:
        out.append(cnt)
        cnt = 0 if r else (cnt + 1) % (1 << bits)
    return out


def pack(re, im, b):
    """Complex lanes -> one word, lane n: re at 2n·b, im at (2n+1)·b."""
    w = 0
    for n, (r, i) in enumerate(zip(re, im)):
        w |= r << (2 * n * b) | i << ((2 * n + 1) * b)
    return w


def unpack(w, n_lanes, b):
    m = (1 << b) - 1
    return ([(w >> (2 * n * b)) & m for n in range(n_lanes)],
            [(w >> ((2 * n + 1) * b)) & m for n in range(n_lanes)])


def sync_every(cycles, period, first):
    return [1 if t >= first and (t - first) % period == 0 else 0 for t in range(cycles)]


def write_set(d, params, ports):
    d.mkdir(parents=True, exist_ok=True)
    (d / "params.json").write_text(json.dumps(params, indent=2) + "\n")
    for k, rows in ports.items():
        write_csv(d / f"sim_{k}.csv", rows)


# ── complex_conj ────────────────────────────────────────────────────────────

CC = ["N_INPUTS", "N_BITS", "BIN_PT", "LATENCY", "OVERFLOW"]
CC_TESTS = [
    (P(CC, [1, 18, 17, 1, 0]), "casper defaults (Wrap)"),
    (P(CC, [2, 8, 7, 0, 1]), "2 lanes, combinational, Saturate"),
    (P(CC, [4, 12, 4, 2, 0]), "4 lanes, latency 2, Wrap"),
    (P(CC, [3, 6, 5, 1, 1]), "3 lanes, 6-bit, Saturate"),
]


def m_complex_conj(p, re, im):
    b, bp, lat, ovf = p["N_BITS"], p["BIN_PT"], p["LATENCY"], p["OVERFLOW"]
    neg = per_lane(lambda x: quantize(-to_value(x, b, bp, 1), b, bp, 1, 0, ovf), im)
    zero = [0] * len(re[0])
    return delay(re, lat, zero), delay(neg, lat, zero)


def gen_complex_conj():
    name, mdir, sets = "complex_conj", TEST_DATA / "complex_conj", []
    for n, (p, desc) in enumerate(CC_TESTS):
        rng = random.Random(f"{name}-{n}")
        cycles = 128
        re = lanes_stim(rng, cycles, p["N_INPUTS"], p["N_BITS"])
        im = lanes_stim(rng, cycles, p["N_INPUTS"], p["N_BITS"])
        o_re, o_im = m_complex_conj(p, re, im)
        write_set(mdir / f"simdata{n}", p, {"din_re": re, "din_im": im,
                                            "dout_re": o_re, "dout_im": o_im})
        sets.append((p, desc, cycles))
    md_table(mdir, name, CC, sets,
             "`complex_conj` delays the real part and negates the imaginary part "
             "(bus_negate, Truncate, `OVERFLOW` 0 = Wrap / 1 = Saturate) with "
             "latency `LATENCY`. Row 0 is zero, then corner words (0, 1, −1, most "
             "negative, …) on every lane, then random words.")
    return toml(CATEGORY, name, [(p, d) for p, d, _ in sets], SCRIPT)


# ── hilbert ─────────────────────────────────────────────────────────────────

HB = ["N_INPUTS", "BIT_WIDTH", "BIN_PT_IN", "ADD_LATENCY", "CONV_LATENCY"]
HB_TESTS = [
    (P(HB, [1, 18, 17, 1, 1]), "casper defaults"),
    (P(HB, [2, 8, 7, 2, 0]), "2 lanes, combinational convert"),
    (P(HB, [3, 12, 10, 0, 1]), "3 lanes, combinational adders"),
    (P(HB, [1, 6, 5, 0, 0]), "fully combinational, 6-bit"),
]


def m_hilbert(p, a_re, a_im, b_re, b_im):
    bw, bp = p["BIT_WIDTH"], p["BIN_PT_IN"]
    lat = p["ADD_LATENCY"] + p["CONV_LATENCY"]

    def v(x):
        return to_value(x, bw, bp, 1)

    def half(x):                     # bus_scale(-1) + bus_convert (round even, wrap)
        return quantize(x / 2, bw, bp, 1, 2, 0)

    zero = [0] * len(a_re[0])
    out = {
        "even_re": per_lane(lambda ar, br: half(v(ar) + v(br)), a_re, b_re),
        "even_im": per_lane(lambda ai, bi: half(v(ai) - v(bi)), a_im, b_im),
        "odd_re":  per_lane(lambda ai, bi: half(v(ai) + v(bi)), a_im, b_im),
        "odd_im":  per_lane(lambda ar, br: half(v(br) - v(ar)), a_re, b_re),
    }
    return {k: delay(rows, lat, zero) for k, rows in out.items()}


def gen_hilbert():
    name, mdir, sets = "hilbert", TEST_DATA / "hilbert", []
    for n, (p, desc) in enumerate(HB_TESTS):
        rng = random.Random(f"{name}-{n}")
        cycles = 160
        ins = {k: lanes_stim(rng, cycles, p["N_INPUTS"], p["BIT_WIDTH"])
               for k in ("a_re", "a_im", "b_re", "b_im")}
        # all pairs of corner words on (a, b)
        cs = corners(p["BIT_WIDTH"])
        for i, (x, y) in enumerate((x, y) for x in cs for y in cs):
            t = 1 + 2 * len(cs) + i
            for k, val in (("a_re", x), ("a_im", y), ("b_re", y), ("b_im", x)):
                ins[k][t] = [val] * p["N_INPUTS"]
        out = m_hilbert(p, ins["a_re"], ins["a_im"], ins["b_re"], ins["b_im"])
        write_set(mdir / f"simdata{n}", p, {**ins, **out})
        sets.append((p, desc, cycles))
    md_table(mdir, name, HB, sets,
             "`hilbert` computes `even = (a + conj(b))/2` and `odd = (a − "
             "conj(b))/(2j)` per lane: full-precision sums, then a halving "
             "bus_convert with round-half-even and wrap. Row 0 is zero, then "
             "corner words, all pairs of corner words on (a, b), then random "
             "words; the corners include the one case that wraps (`b_re` "
             "maximum, `a_re` most negative).")
    return toml(CATEGORY, name, [(p, d) for p, d, _ in sets], SCRIPT)


# ── mirror_spectrum ─────────────────────────────────────────────────────────

MS = ["N_INPUTS", "FFT_SIZE", "INPUT_BIT_WIDTH", "BIN_PT_IN", "BRAM_LATENCY",
      "NEGATE_LATENCY", "NEGATE_MODE"]
MS_TESTS = [
    (P(MS, [1, 3, 18, 17, 2, 1, 0]), "casper defaults"),
    (P(MS, [2, 4, 12, 11, 5, 0, 0]), "2 lanes, negate latency 0 (as in bi_real_unscr_4x)"),
    (P(MS, [4, 2, 8, 7, 1, 0, 1]), "4 lanes (replicate latency 2), dsp48e negate (latency 3)"),
]


def ms_ports():
    ins = [f"{p}{i}_{c}" for i in range(4) for p in ("din", "reo_in") for c in ("re", "im")]
    outs = [f"dout{i}_{c}" for i in range(4) for c in ("re", "im")]
    return ins, outs


def m_mirror_spectrum(p, st):
    n, f = p["N_INPUTS"], p["FFT_SIZE"]
    rep = (n - 1).bit_length()
    dly = 1 + p["BRAM_LATENCY"] + p["NEGATE_LATENCY"]
    cc = 3 if p["NEGATE_MODE"] == 1 else p["NEGATE_LATENCY"]
    zero = [0] * n
    sync0 = delay(st["sync"], dly - rep, 0)
    upper = [1 if c > 1 << (f - 1) else 0 for c in m_counter(sync0, f)]
    sel = delay(upper, rep, 0)
    out = {"sync_out": delay(sync0, 1 + rep, 0)}
    q = P(CC, [n, p["INPUT_BIT_WIDTH"], p["BIN_PT_IN"], cc, 0])
    for i in range(4):
        c_re, c_im = m_complex_conj(q, st[f"reo_in{i}_re"], st[f"reo_in{i}_im"])
        for part, conj in (("re", c_re), ("im", c_im)):
            d = delay(st[f"din{i}_{part}"], dly, zero)
            out[f"dout{i}_{part}"] = delay([c if s else x for s, x, c in zip(sel, d, conj)], 1, zero)
    return out


def gen_mirror_spectrum():
    name, mdir, sets = "mirror_spectrum", TEST_DATA / "mirror_spectrum", []
    ins, _ = ms_ports()
    for n, (p, desc) in enumerate(MS_TESTS):
        rng = random.Random(f"{name}-{n}")
        frame = 1 << p["FFT_SIZE"]
        cycles = max(128, 8 * frame)
        st = {k: lanes_stim(rng, cycles, p["N_INPUTS"], p["INPUT_BIT_WIDTH"]) for k in ins}
        sync = sync_every(cycles, frame, 3)
        # one early re-sync mid-run: the counter restarts
        t = cycles // 2 + frame // 3
        sync[t] = 1
        sync = sync[:t + 1] + sync_every(cycles - t - 1, frame, frame - 1)
        st["sync"] = sync
        out = m_mirror_spectrum(p, st)
        write_set(mdir / f"simdata{n}", p, {**st, **out})
        sets.append((p, desc, cycles))
    md_table(mdir, name, MS, sets,
             "`mirror_spectrum` passes `din<i>` for frame counts 0 … "
             "2^(FFT_SIZE−1) and outputs `conj(reo_in<i>)` above that (casper "
             "Relational a>b). `sync` pulses every 2^FFT_SIZE cycles plus one "
             "early re-sync mid-run that restarts the frame counter; data are "
             "random words with corner words at the start (so the Wrap of the "
             "negate is exercised).")
    return toml(CATEGORY, name, [(p, d) for p, d, _ in sets], SCRIPT)


# ── bi_real_unscr_4x ────────────────────────────────────────────────────────

BR = ["N_INPUTS", "FFT_SIZE", "N_BITS", "BIN_PT", "ADD_LATENCY", "CONV_LATENCY",
      "BRAM_LATENCY", "BRAM_MAP", "BRAM_DELAYS"]
BR_TESTS = [
    (P(BR, [1, 3, 18, 17, 1, 1, 2, 0, 0]), "casper defaults"),
    (P(BR, [2, 4, 12, 11, 2, 1, 1, 1, 0]), "2 lanes, BRAM map (map latency 3)"),
    (P(BR, [1, 5, 16, 15, 1, 2, 2, 0, 1]), "BRAM half-frame delays"),
    (P(BR, [1, 2, 8, 7, 0, 0, 1, 0, 0]), "smallest FFT (even map is the identity), combinational hilbert"),
    (P(BR, [4, 8, 18, 17, 1, 1, 2, 0, 0]),
     "4 lanes, 256-point: fanout latency 1, sync_delay and delay_bram (half frame > 52)"),
]
BR_FRAMES = 7


def bi_real_derived(p):
    f, w = p["FFT_SIZE"], 2 * p["N_BITS"] * p["N_INPUTS"]
    map_lat = 3 if p["BRAM_MAP"] else 1
    fanout = max(0, f + (w - 1).bit_length() - 15)
    return map_lat, fanout


def m_bi_real_unscr_4x(p, st):
    n, f, b = p["N_INPUTS"], p["FFT_SIZE"], p["N_BITS"]
    half, lat_h = 1 << (f - 1), p["ADD_LATENCY"] + p["CONV_LATENCY"]
    map_lat, fanout = bi_real_derived(p)
    maps = {k: bi_real_map(k, f) for k in ("even", "odd", "out")}

    def ro(which, streams, din, sync):
        q = {"N_STREAMS": streams, "MAP_LEN": half, "ORDER": compute_order(maps[which]),
             "MAP_LATENCY": map_lat, "BRAM_LATENCY": p["BRAM_LATENCY"], "FANOUT_LATENCY": fanout}
        return m_reorder(q, maps[which], {"din": din, "sync": sync})

    even_w = [[pack(r, i, b)] for r, i in zip(st["even_re"], st["even_im"])]
    odd_w = [[pack(r, i, b)] for r, i in zip(st["odd_re"], st["odd_im"])]
    e = ro("even", 1, even_w, st["sync"])
    o = ro("odd", 1, odd_w, st["sync"])
    reo_e = column(e["dout"], 0)
    odd_d = delay(column(o["dout"], 0), 1, 0)
    count = m_counter(e["sync_out"], f)
    r0 = [1 if c == half else 0 for c in count]
    r1 = [1 if c == 0 else 0 for c in count]
    mux = [delay([od if s else ev for s, ev, od in zip(r0, reo_e, odd_d)], 1, 0),
           delay([ev if s else od for s, ev, od in zip(r1, reo_e, odd_d)], 1, 0),
           delay([od if s else ev for s, ev, od in zip(r1, reo_e, odd_d)], 1, 0),
           delay([ev if s else od for s, ev, od in zip(r0, reo_e, odd_d)], 1, 0)]
    split = [[unpack(w, n, b) for w in m] for m in mux]
    hp = P(HB, [n, b, p["BIN_PT"], p["ADD_LATENCY"], p["CONV_LATENCY"]])
    hil = []
    for h in range(2):
        a, bb = split[2 * h], split[2 * h + 1]
        hil.append(m_hilbert(hp, [x[0] for x in a], [x[1] for x in a],
                             [x[0] for x in bb], [x[1] for x in bb]))
    words = [[pack(r, i, b) for r, i in zip(hil[h][f"{o}_re"], hil[h][f"{o}_im"])]
             for h in range(2) for o in ("even", "odd")]
    ch = [delay(words[0], half, 0), delay(words[1], half, 0), words[2], words[3]]
    sync_d2 = delay(e["sync_out"], lat_h + 1, 0)
    ms_sync = m_sync_delay(sync_d2, half) if half > 52 else delay(sync_d2, half, 0)
    r = ro("out", 4, [list(x) for x in zip(*ch)], ms_sync)
    reo_d = delay(r["dout"], 1, [0] * 4)
    ms = {"sync": ms_sync}
    for i in range(4):
        ms[f"din{i}_re"], ms[f"din{i}_im"] = map(list, zip(*[unpack(w, n, b) for w in ch[i]]))
        ms[f"reo_in{i}_re"], ms[f"reo_in{i}_im"] = map(
            list, zip(*[unpack(row[i], n, b) for row in reo_d]))
    mp = P(MS, [n, f, b, p["BIN_PT"], p["BRAM_LATENCY"] + map_lat + 2 + fanout, 0, 0])
    m = m_mirror_spectrum(mp, ms)
    out = {"sync_out": m["sync_out"]}
    for i in range(4):
        out[f"pol{i + 1}_out_re"] = m[f"dout{i}_re"]
        out[f"pol{i + 1}_out_im"] = m[f"dout{i}_im"]
    return out


def bi_real_stimulus(p, rng):
    """Four random real signals through the biplex_core model (fft_biplex_real_4x).

    Returns (bi_real inputs, the real input frames, n_shifts).
    """
    n, f, b, bp = p["N_INPUTS"], p["FFT_SIZE"], p["N_BITS"], p["BIN_PT"]
    npts = 1 << f
    bc = P(BC, [n, f, b, bp, 18, 1, 2, 2, 1, 1, 0, 8, 4, 0, 20, 0, 0])
    lead = 3
    cycles = lead + 1 + BR_FRAMES * npts + 128      # + pipeline fill of both blocks
    amp = 1 << (b - 3)
    pols = [[[rng.randrange(-amp, amp) for _ in range(n)] for _ in range(cycles)] for _ in range(4)]
    for pl in pols:
        pl[0] = [0] * n
    st = {"pol1_re": pols[0], "pol1_im": pols[1], "pol2_re": pols[2], "pol2_im": pols[3]}
    st = {k: [[v % (1 << b) for v in row] for row in rows] for k, rows in st.items()}
    st["sync"] = sync_every(cycles, npts, lead)
    st["shift"] = [(1 << f) - 1] * cycles
    out = m_biplex_core(bc, st)
    stim = {"sync": out["sync_out"], "even_re": out["out1_re"], "even_im": out["out1_im"],
            "odd_re": out["out2_re"], "odd_im": out["out2_im"]}
    return stim, pols, st["sync"], f        # every stage halves: n_shifts = FFT_SIZE


def check_bi_real_is_fft(p, pols, in_sync, out, n_shifts):
    """Every output frame is the FFT of one input frame of each real signal.

    pol<i>_out bin k (cycle k after sync_out) must equal numpy's FFT of input
    signal i (pol1 = re z1, pol2 = im z1, pol3 = re z2, pol4 = im z2) of some
    earlier frame, scaled by 2^-n_shifts, to within a few LSBs; the frame
    offset must be the same for all frames. Returns (frames checked, worst
    error in LSBs).
    """
    try:
        import numpy as np
    except ImportError:
        print("# numpy not available: FFT check of bi_real_unscr_4x skipped", file=sys.stderr)
        return None, None
    n, f, b, bp = p["N_INPUTS"], p["FFT_SIZE"], p["N_BITS"], p["BIN_PT"]
    npts = 1 << f
    starts_in = [t + 1 for t, s in enumerate(in_sync) if s and t + npts < len(in_sync)]
    starts_out = [t + 1 for t, s in enumerate(out["sync_out"]) if s and t + npts < len(in_sync)]
    assert len(starts_out) >= 2, "too few output frames"

    def spectrum(i, start, lane):
        x = np.array([signed(pols[i][start + k][lane] % (1 << b), b) for k in range(npts)]) / 2 ** bp
        return np.fft.fft(x) / 2 ** n_shifts

    def got(i, start, lane):
        re, im = out[f"pol{i + 1}_out_re"], out[f"pol{i + 1}_out_im"]
        return np.array([signed(re[start + k][lane], b) + 1j * signed(im[start + k][lane], b)
                         for k in range(npts)]) / 2 ** bp

    offset, worst = None, 0.0
    # skip the first output frame (pipeline still filling)
    for so in starts_out[1:]:
        cands = [si for si in starts_in if si < so]
        errs = {si: max(np.max(np.abs(got(i, so, l) - spectrum(i, si, l)))
                        for i in range(4) for l in range(n)) * 2 ** bp for si in cands}
        best = min(errs, key=errs.get)
        assert errs[best] < 4, f"output frame at {so} is not an FFT (error {errs[best]:.1f} LSB)"
        lag = so - best
        assert offset in (None, lag), "frame latency changes"
        offset, worst = lag, max(worst, errs[best])
    return len(starts_out) - 1, worst


def gen_bi_real_unscr_4x():
    name, mdir, sets = "bi_real_unscr_4x", TEST_DATA / "bi_real_unscr_4x", []
    for n, (p, desc) in enumerate(BR_TESTS):
        rng = random.Random(f"{name}-{n}")
        stim, pols, in_sync, n_shifts = bi_real_stimulus(p, rng)
        out = m_bi_real_unscr_4x(p, stim)
        if p["FFT_SIZE"] == 2:
            # casper quirk: the even map is the identity (order 1), and an
            # order-1 reorder is one cycle slower than the order-2 odd one
            # (reorder_init.m pre_delay), so even and odd are misaligned and
            # casper's own block does not compute an FFT here
            frames, worst = "n/a", None
        else:
            frames, worst = check_bi_real_is_fft(p, pols, in_sync, out, n_shifts)
        d = mdir / f"simdata{n}"
        full = dict(p, MAP_DIR=MAP_REL.format(n=n))
        write_set(d, full, {**stim, **out})
        for which in ("even", "odd", "out"):
            _, lines = mem_lines(bi_real_map(which, p["FFT_SIZE"]))
            (d / f"map_{which}.mem").write_text("".join(x + "\n" for x in lines))
        checked = ("skipped (no numpy)" if frames is None else
                   "not an FFT (casper quirk, see above)" if frames == "n/a" else
                   f"{frames} ({worst:.2f} LSB)")
        sets.append((full, desc, len(stim["sync"]), checked))
    md_table(mdir, name, BR, sets,
             "`bi_real_unscr_4x` turns a biplex FFT of `z1 = pol1 + j·pol2`, `z2 = "
             "pol3 + j·pol4` into the full spectra of the four real signals. The "
             "inputs are the output of the biplex_core reference model "
             "(`gen_biplex_test_data.py`, all stages shifting, no bit growth) "
             f"for {BR_FRAMES} frames of four random real signals, as in "
             "fft_biplex_real_4x. The script checks with numpy that every "
             "output frame after the first is the FFT of one input frame of each "
             "signal, the same number of frames earlier each time (column "
             "*FFT frames checked*, worst error in output LSBs). For `FFT_SIZE` = 2 "
             "casper's block is not an FFT: the even map is the identity, and "
             "an order-1 reorder is one cycle slower than the order-2 odd one "
             "(`reorder_init.m` pre_delay), so even and odd are misaligned; "
             "the data reproduce that behaviour bit-exactly. `map_even.mem`, "
             "`map_odd.mem` and `map_out.mem` come from "
             "`rtl/Reorder/scripts/gen_reorder_map.py --bi-real`; `MAP_DIR` is "
             "relative to the simulator's working directory "
             "`tests/sim_build/FFTs/Internal/bi_real_unscr_4x/`.",
             extra="FFT frames checked")
    return toml(CATEGORY, name, [(p, d) for p, d, *_ in sets], SCRIPT)


# ── test_data.md ────────────────────────────────────────────────────────────

def md_table(mdir, name, keys, sets, prose, extra=None):
    lines = [
        f"# {name} test data", "", prose, "",
        "Generated by `test_data/scripts/gen_fft_internal_test_data.py` "
        "(reference model, not exported from MATLAB). CSV rows are cycles, one "
        "column per lane.", "",
        "| Test # | Directory | " + " | ".join(keys) + (f" | {extra}" if extra else "")
        + " | Cycles | Description |",
        "|" + "---|" * (len(keys) + 4 + (1 if extra else 0)),
    ]
    for n, (p, desc, cycles, *rest) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(p[k]) for k in keys)
                     + "".join(f" | {x}" for x in rest) + f" | {cycles} | {desc} |")
    (mdir / "test_data.md").write_text("\n".join(lines) + "\n")


def main():
    run_cli(__doc__, {"complex_conj": gen_complex_conj, "hilbert": gen_hilbert,
                      "mirror_spectrum": gen_mirror_spectrum,
                      "bi_real_unscr_4x": gen_bi_real_unscr_4x})


if __name__ == "__main__":
    main()
