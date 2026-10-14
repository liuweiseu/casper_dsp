#!/usr/bin/env python3
"""Generate test data for the rtl/Reorder/ modules.

Expected outputs come from Python reference models of casper_library's
reorder, barrel_switcher and square_transposer (reorder_init.m,
barrel_switcher_init.m, square_transposer_init.m), not from the RTL:

  reorder           a read-before-write buffer addressed, in the f-th frame
                    after a sync, with map^f(k) (closed form, computed with
                    rtl/Reorder/scripts/gen_reorder_map.py), plus a check that
                    whole frames come out as out[k] = previous frame[map[k]];
                    with en, frames are counted in enabled samples
  barrel_switcher   dout[k] = din[(k + sel) mod N], N_INPUTS cycles later
  square_transposer lane delays + barrel switcher driven by the sync-reset
                    down counter, plus a check that sync-aligned N x N
                    blocks come out transposed

Writes test_data/Reorder/<module>/simdataN/{params.json, sim_<port>.csv
[, map.mem]} and test_data.md, and prints the [[simulations]] blocks for
tests/simulation.toml. Array ports have one file per element,
sim_<port><j>.csv = element j; values are raw unsigned words.

Usage:
  python3 test_data/scripts/gen_reorder_test_data.py                 # all modules
  python3 test_data/scripts/gen_reorder_test_data.py --module reorder
"""

import json
import random
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli, write_test_data_md  # also puts rtl/.../scripts on sys.path
from gen_butterfly_test_data import delay, write_csv, P, toml
from gen_fft_stage_test_data import m_sync_delay
from gen_reorder_map import bi_real_map, compute_order, map_powers, mem_lines, unscrambler_map

SCRIPT = Path(__file__).name
CATEGORY = "Reorder"
TEST_DATA = TEST_DATA_ROOT / CATEGORY
MAP_REL = "../../../test_data/Reorder/reorder/simdata{n}/map.mem"


def sync_train_en(rng, en, period, first=3):
    """sync every `period` enabled samples from `first`, plus one early re-sync.

    A sync goes on the cycle of the last sample of a period, or on a later
    en = 0 cycle before the next sample (both close the period).
    """
    cycles = len(en)
    s, t, done = [0] * cycles, first, False
    while t < cycles:
        s[t] = 1
        want = max(2, period // 3 + 1) if not done and t > cycles // 2 else period
        done = done or want != period
        n = 0
        while t + 1 < cycles and n < want:
            t += 1
            n += en[t]
        while t + 1 < cycles and not en[t + 1] and rng.random() < 0.5:
            t += 1
        if t + 1 >= cycles:
            break
    return s


def sync_train(rng, cycles, frame, first=3, early=True):
    """sync every `frame` cycles from `first`, plus one early re-sync."""
    s = [0] * cycles
    t, done = first, not early
    while t < cycles:
        s[t] = 1
        if not done and t > cycles // 2:
            t += max(2, frame // 3 + 1)
            done = True
        else:
            t += frame
    return s


# ── reorder ─────────────────────────────────────────────────────────────────

RO = ["N_INPUTS", "N_BITS", "MAP_LEN", "ORDER", "MAP_LATENCY", "BRAM_LATENCY",
      "FANOUT_LATENCY"]

# (map name, map, N_INPUTS, N_BITS, MAP_LATENCY, BRAM_LATENCY, FANOUT_LATENCY,
#  description[, probability of en = 1]); without the last field en = 1 and no
# sim_en.csv is written
REORDER_TESTS = [
    ("default", [0, 7, 1, 3, 2, 5, 6, 4], 1, 8, 2, 1, 0, "casper's default map (order 4)"),
    ("bi_real even F5", bi_real_map("even", 5), 1, 36, 1, 2, 0,
     "bit-reversal map of bi_real_unscr_4x reorder_even (order 2)"),
    ("bi_real out F4", bi_real_map("out", 4), 4, 18, 3, 2, 1,
     "index-reversal map of reorder_out, 4 streams (rep latency 2)"),
    ("unscrambler F5 n1", unscrambler_map(5, 1), 2, 16, 2, 2, 2,
     "fft_unscrambler map FFTSize 5, 2 groups (order 4)"),
    ("unscrambler F8 n2", unscrambler_map(8, 2), 4, 12, 2, 1, 0,
     "fft_unscrambler map FFTSize 8, 4 groups (order 3)"),
    ("unscrambler F7 n1", unscrambler_map(7, 1), 2, 10, 1, 1, 0,
     "fft_unscrambler map FFTSize 7, 2 groups (order 6)"),
    ("identity 8", list(range(8)), 1, 8, 1, 2, 1, "identity map: plain delay (order 1)"),
    ("bi_real even F2", bi_real_map("even", 2), 2, 8, 2, 1, 0, "2-point map (order 1)"),
    # random en; N_BITS differs from the en = 1 sets (the testbench picks the
    # set by its integer parameters)
    ("default", [0, 7, 1, 3, 2, 5, 6, 4], 1, 10, 2, 1, 0, "casper's default map (order 4), random en", 0.7),
    ("unscrambler F5 n1", unscrambler_map(5, 1), 2, 14, 2, 2, 2,
     "fft_unscrambler map FFTSize 5, 2 groups (order 4), random en", 0.6),
    ("bi_real out F4", bi_real_map("out", 4), 4, 20, 3, 2, 1,
     "index-reversal map of reorder_out, 4 streams (order 2), random en", 0.7),
    ("identity 8", list(range(8)), 1, 6, 1, 2, 1, "identity map: plain delay (order 1), random en", 0.5),
]


def reorder_latencies(p):
    order, rep = p["ORDER"], (p["N_INPUTS"] - 1).bit_length()
    pre = p["MAP_LATENCY"] + (1 if order == 2 else 2)
    return pre + rep, p["BRAM_LATENCY"] + p["FANOUT_LATENCY"]


def m_sync_delay_en(din, en, delay_len):
    """casper sync_delay_en: down counter loaded on din, decremented on en; dout = (cnt == 1)."""
    cnt, out = 0, []
    for x, e in zip(din, en):
        out.append(1 if cnt == 1 else 0)
        cnt = delay_len if x else (cnt - 1 if e and cnt else cnt)
    return out


def m_reorder(p, perm, st):
    """Reference model of reorder (single buffered).

    en (default all 1) gates the step counter and the RAM write; the RAM is
    read every cycle. The counter is cleared by sync (sync wins over en),
    except for ORDER = 1 (delay_bram_en_plus), whose counter ignores sync.
    The delays in front of the RAM are the same for address, data and write
    enable, so the RAM is modelled in input time and its output delayed.
    """
    cycles, n, map_len, order = len(st["sync"]), p["N_INPUTS"], p["MAP_LEN"], p["ORDER"]
    en = st.get("en", [1] * cycles)
    din_dly, out_dly = reorder_latencies(p)
    zero = [0] * n
    en_d = delay(en, din_dly, 0)
    sync_out = delay(m_sync_delay_en(delay(st["sync"], din_dly, 0), en_d, map_len), out_dly, 0)
    valid = delay(en_d, out_dly, 0)
    _, powers = map_powers(perm)
    ram, k, f, ram_out = [zero] * map_len, 0, 0, []
    for t in range(cycles):
        addr = k if order == 1 else powers[(f % order) * map_len + k]
        ram_out.append(ram[addr])                  # read before write
        if en[t]:
            ram[addr] = st["din"][t]
        if st["sync"][t] and order != 1:
            k, f = 0, 0
        elif en[t]:
            k, f = (k + 1) % map_len, f + (1 if k == map_len - 1 else 0)
    return {"dout": delay(ram_out, din_dly + out_dly, zero), "sync_out": sync_out, "valid": valid}


def check_reorder_semantics(p, perm, st, out):
    """Every frame of a regular sync period comes out as the previous frame permuted.

    The frame counter restarts at every sync, so (as in casper) syncs must be
    ORDER·MAP_LEN cycles apart, or a multiple: then frame 0 after a sync
    (identity addresses) follows a frame addressed with map^(ORDER-1). Frames
    are checked inside and across regular sync periods.
    """
    map_len, period = p["MAP_LEN"], p["ORDER"] * p["MAP_LEN"]
    lat = sum(reorder_latencies(p))
    cycles = len(st["sync"])
    en = st.get("en", [1] * cycles)
    # enabled samples only: sample i was taken in cycle when[i] and leaves in
    # cycle when[i] + lat; a sync in cycle t closes the frame after the
    # samples taken up to t, so it sits at index (samples in cycles <= t) - 1
    when = [t for t in range(cycles) if en[t] and t + lat < cycles]
    din = [st["din"][t] for t in when]
    dout = [out["dout"][t + lat] for t in when]
    assert all(out["valid"][t + lat] for t in when), "valid does not mark the samples"
    taken = [0]
    for e in en:
        taken.append(taken[-1] + e)
    syncs = [taken[t + 1] - 1 for t, s in enumerate(st["sync"]) if s]
    checked = 0
    for a, b, c in zip(syncs, syncs[1:], syncs[2:] + [len(din)]):
        if b - a != period:
            continue
        # frames whose previous frame lies inside this regular period,
        # including frame 0 after the closing sync b if it completes before
        # the next sync c
        last = b + 1 if c - b >= map_len else b + 1 - map_len
        for start in range(a + 1 + map_len, last + 1, map_len):
            if start + map_len > len(din):
                break
            prev = din[start - map_len: start]
            for k in range(map_len):
                assert dout[start + k] == prev[perm[k]], "reorder model is not a permutation"
            checked += 1
    assert checked >= 3
    return checked


def gen_reorder():
    name, mdir, sets = "reorder", TEST_DATA / "reorder", []
    for n, (mname, perm, ns, dw, ml, bl, fl, desc, *en_p) in enumerate(REORDER_TESTS):
        rng = random.Random(f"{name}-{n}")
        p = P(RO, [ns, dw, len(perm), compute_order(perm), ml, bl, fl])
        period = p["ORDER"] * p["MAP_LEN"]          # syncs must be ORDER·MAP_LEN apart
        cycles = max(256, 4 * period + 4 * len(perm))
        if en_p:
            cycles = -(-int(cycles / en_p[0]) // 64) * 64
        st = {"din": [[rng.randrange(1 << dw) for _ in range(ns)] for _ in range(cycles)]}
        if en_p:
            st["en"] = [1 if rng.random() < en_p[0] else 0 for _ in range(cycles)]
            st["sync"] = sync_train_en(rng, st["en"], period)
        else:
            st["sync"] = sync_train(rng, cycles, period)
        out = m_reorder(p, perm, st)
        frames = check_reorder_semantics(p, perm, st, out)
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        order, lines = mem_lines(perm)
        (d / "map.mem").write_text("".join(x + "\n" for x in lines))
        full = dict(p, MAP_INIT_FILE=MAP_REL.format(n=n))
        (d / "params.json").write_text(json.dumps(dict(full, MAP=perm), indent=2) + "\n")
        write_csv(d / "sim_din.csv", st["din"])
        write_csv(d / "sim_sync.csv", st["sync"])
        if en_p:
            write_csv(d / "sim_en.csv", st["en"])
        for k in ("dout", "sync_out", "valid"):
            write_csv(d / f"sim_{k}.csv", out[k])
        sets.append((full, desc, mname, cycles, frames))
    lines = [
        "# reorder test data", "",
        "`reorder` permutes every `MAP_LEN`-sample frame: output step k is "
        "sample `map[k]` of the previous frame. Each set uses a map that a "
        "casper block uses (or casper's default); `ORDER` (lcm of the map's "
        "cycle lengths) selects the implementation: 1 = delay line, 2 = "
        "k / map[k] select, > 2 = incrementally updated map copy. The frame "
        "counter restarts at every sync, so (as in casper designs) `sync` "
        "pulses every `ORDER·MAP_LEN` cycles, plus one early re-sync mid-run; "
        "`din` is random. Sets with a random `en` (`sim_en.csv`; the other sets "
        "have none, and the testbench drives `en` = 1) count frames and sync "
        "periods in enabled samples; a sync falls on the last sample of a "
        "period or on an `en` = 0 cycle after it.", "",
        "Generated by `test_data/scripts/gen_reorder_test_data.py`: the "
        "expected outputs model a read-before-write buffer addressed with "
        "map^f(k) in the f-th frame after a sync (closed form, independent of "
        "the RTL's incremental mechanism); `en` gates the step counter, the RAM "
        "write and (delayed) `valid`, and `sync_out` comes from a model of "
        "casper's `sync_delay_en` (`reorder_init.m:151-187`). The script also "
        "checks that the model outputs every regular frame as the previous "
        "frame permuted (column *Frames checked*). `map.mem` comes from "
        "`rtl/Reorder/scripts/gen_reorder_map.py`; `MAP_INIT_FILE` is "
        "relative to the simulator's working directory "
        "`tests/sim_build/Reorder/reorder/`. Not exported from MATLAB: "
        "casper's own Tests/reorder_*_test reference data were made with an "
        "older reorder implementation and a random `en`, so they do not "
        "apply. CSV rows are cycles; `sim_din<j>.csv` / `sim_dout<j>.csv` hold "
        "stream j.", "",
        "| Test # | Directory | " + " | ".join(RO) + " | Map | Frames checked | Cycles | Description |",
        "|" + "---|" * (len(RO) + 6),
    ]
    for n, (full, desc, mname, cycles, frames) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | " + " | ".join(str(full[k]) for k in RO)
                     + f" | {mname} | {frames} | {cycles} | {desc} |")
    write_test_data_md(mdir / "test_data.md", lines)
    return toml(CATEGORY, name, [(full, desc) for full, desc, *_ in sets], SCRIPT)


# ── barrel_switcher / square_transposer ─────────────────────────────────────

def m_barrel(log2n, din, sel, sync):
    n_lanes = 1 << log2n
    rot = [[row[(k + s) % n_lanes] for k in range(n_lanes)] for row, s in zip(din, sel)]
    return {"dout": delay(rot, log2n, [0] * n_lanes), "sync_out": delay(sync, log2n, 0)}


def m_square_transposer(log2n, din, sync):
    n_lanes, cycles = 1 << log2n, len(sync)
    cnt, sel = 0, []
    for t in range(cycles):
        sel.append(cnt)
        cnt = 0 if sync[t] else (cnt - 1) % n_lanes
    pre = [[0] * n_lanes for _ in range(cycles)]
    for q in range(n_lanes):
        col = delay([row[q] for row in din], q, 0)
        for t in range(cycles):
            pre[t][(n_lanes - q) % n_lanes] = col[t]
    bs = m_barrel(log2n, pre, sel, sync)
    out = [[0] * n_lanes for _ in range(cycles)]
    for q in range(n_lanes):
        col = delay([row[q] for row in bs["dout"]], n_lanes - 1 - q, 0)
        for t in range(cycles):
            out[t][q] = col[t]
    return {"dout": out, "sync_out": delay(bs["sync_out"], n_lanes - 1, 0)}


def check_transpose(log2n, din, sync, out):
    """A block starting the cycle after a sync comes out transposed.

    Sample i of input lane q reaches the barrel switcher i + q cycles after
    the block starts, so the counter must run undisturbed for 2N - 1 cycles
    after the sync: the next sync may come no earlier than that.
    """
    n_lanes, lat = 1 << log2n, log2n + (1 << log2n) - 1
    syncs = [t for t, s in enumerate(sync) if s]
    checked = 0
    for a, b in zip(syncs, syncs[1:] + [len(sync)]):
        if b - a < 2 * n_lanes - 1 or a + 2 * n_lanes + lat > len(sync):
            continue
        for i in range(n_lanes):            # input time offset
            for q in range(n_lanes):        # input lane
                assert out[a + 1 + q + lat][i] == din[a + 1 + i][q], "not a transpose"
        checked += 1
    assert checked >= 3
    return checked


ST = ["N_INPUTS", "DATA_WIDTH"]
TRANSPOSER_TESTS = [(1, 8, "2 lanes"), (2, 36, "4 lanes, 36-bit words"), (3, 12, "8 lanes")]
# (log2 lanes, width, description[, ASYNC])
BARREL_TESTS = [(1, 8, "2 lanes"), (2, 16, "4 lanes"), (3, 6, "8 lanes"),
                (2, 16, "4 lanes, async: dvalid = en delayed N_INPUTS", 1)]


def gen_square_transposer():
    name, mdir, sets = "square_transposer", TEST_DATA / "square_transposer", []
    for n, (log2n, dw, desc) in enumerate(TRANSPOSER_TESTS):
        rng = random.Random(f"{name}-{n}")
        lanes, cycles = 1 << log2n, 256
        din = [[rng.randrange(1 << dw) for _ in range(lanes)] for _ in range(cycles)]
        sync = sync_train(rng, cycles, 4 * lanes)
        out = m_square_transposer(log2n, din, sync)
        blocks = check_transpose(log2n, din, sync, out["dout"])
        p = P(ST, [log2n, dw])
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        (d / "params.json").write_text(json.dumps(p, indent=2) + "\n")
        write_csv(d / "sim_din.csv", din)
        write_csv(d / "sim_sync.csv", sync)
        write_csv(d / "sim_dout.csv", out["dout"])
        write_csv(d / "sim_sync_out.csv", out["sync_out"])
        sets.append((p, desc, cycles, blocks))
    lines = [
        "# square_transposer test data", "",
        "`square_transposer` transposes N × N blocks (N = 2^N_INPUTS lanes "
        "× N cycles) with lane delays and a barrel switcher driven by a "
        "sync-reset down counter. `sync` pulses every 4·N cycles plus one "
        "early re-sync; `din` is random.", "",
        "Generated by `test_data/scripts/gen_reorder_test_data.py` (reference "
        "model of `square_transposer_init.m` / `barrel_switcher_init.m`, not "
        "exported from MATLAB); the script also checks that each block "
        "starting the cycle after a sync comes out transposed (column *Blocks "
        "checked*; blocks whose next sync comes less than 2N − 1 cycles later "
        "are skipped, as the counter restarts while they still pass the "
        "barrel switcher). CSV rows are cycles; `sim_din<j>.csv` / "
        "`sim_dout<j>.csv` hold lane j.", "",
        "| Test # | Directory | N_INPUTS | DATA_WIDTH | Blocks checked | Cycles | Description |",
        "|---|---|---|---|---|---|---|",
    ]
    for n, (p, desc, cycles, blocks) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | {p['N_INPUTS']} | {p['DATA_WIDTH']} | "
                     f"{blocks} | {cycles} | {desc} |")
    write_test_data_md(mdir / "test_data.md", lines)
    return toml(CATEGORY, name, [(p, desc) for p, desc, *_ in sets], SCRIPT)


def gen_barrel_switcher():
    name, mdir, sets = "barrel_switcher", TEST_DATA / "barrel_switcher", []
    for n, (log2n, dw, desc, *asy) in enumerate(BARREL_TESTS):
        rng = random.Random(f"{name}-{n}")
        lanes, cycles = 1 << log2n, 128
        din = [[rng.randrange(1 << dw) for _ in range(lanes)] for _ in range(cycles)]
        sel = [rng.randrange(lanes) for _ in range(cycles)]
        sync = [1 if rng.random() < 0.05 else 0 for _ in range(cycles)]
        out = m_barrel(log2n, din, sel, sync)
        p = P(ST, [log2n, dw])
        if asy:
            # async: en only qualifies the data; dvalid = en through a free
            # Delay of N_INPUTS (barrel_switcher_init.m:64-73, 152-161)
            p["ASYNC"] = 1
            out["en"] = [1 if rng.random() < 0.75 else 0 for _ in range(cycles)]
            out["dvalid"] = delay(out["en"], log2n, 0)
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        (d / "params.json").write_text(json.dumps(p, indent=2) + "\n")
        write_csv(d / "sim_din.csv", din)
        write_csv(d / "sim_sel.csv", sel)
        write_csv(d / "sim_sync_in.csv", sync)
        write_csv(d / "sim_dout.csv", out["dout"])
        write_csv(d / "sim_sync_out.csv", out["sync_out"])
        for k in ("en", "dvalid"):
            if k in out:
                write_csv(d / f"sim_{k}.csv", out[k])
        sets.append((p, desc, cycles))
    lines = [
        "# barrel_switcher test data", "",
        "`barrel_switcher` rotates its lanes by `sel`: `dout[k] = din[(k + sel) "
        "mod N]`, `N_INPUTS` cycles later (`sync_out` likewise). `din`, a "
        "new random `sel` every cycle and sparse `sync_in` pulses. The `ASYNC` "
        "= 1 set also drives a random `sim_en.csv` and expects `sim_dvalid.csv` "
        "= `en` delayed `N_INPUTS` (casper async; the data is not gated).", "",
        "Generated by `test_data/scripts/gen_reorder_test_data.py` (reference "
        "model of `barrel_switcher_init.m`, not exported from MATLAB). CSV rows "
        "are cycles; `sim_din<j>.csv` / `sim_dout<j>.csv` hold lane j.", "",
        "| Test # | Directory | N_INPUTS | DATA_WIDTH | ASYNC | Cycles | Description |",
        "|---|---|---|---|---|---|---|",
    ]
    for n, (p, desc, cycles) in enumerate(sets):
        lines.append(f"| {n} | `simdata{n}` | {p['N_INPUTS']} | {p['DATA_WIDTH']} | "
                     f"{p.get('ASYNC', 0)} | {cycles} | {desc} |")
    write_test_data_md(mdir / "test_data.md", lines)
    return toml(CATEGORY, name, [(p, desc) for p, desc, _ in sets], SCRIPT)


def main():
    run_cli(__doc__, {"reorder": gen_reorder, "square_transposer": gen_square_transposer,
                      "barrel_switcher": gen_barrel_switcher})


if __name__ == "__main__":
    main()
