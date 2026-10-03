"""Generate the model-derived test data of the BasicModules counter and relational.

The original counter (simdata0-4) and relational (simdata0-7) sets were
exported from Simulink and are left untouched; this script only writes the
sets added for the backward-compatible parameters

    counter    RST_VAL  (with ENABLE_SYNC_RST / ENABLE_ENABLE driven)
    relational SIGNED

Each new simdataN gets a params.json (the testbench matches the DUT
parameters against it) and sim_<port>.csv files, row i = value driven
before / read after clock edge i (pre-edge read convention).

Models follow the Xilinx System Generator blocks:

* Counter: start_count is the power-on value, the synchronous reset value
  and, for a count-limited counter, the value loaded after reaching
  count_to (the Simulink-exported counter simdata3/4 wrap to INIT_VAL).
  Reset has priority over enable.
* Relational: a op b on the two's complement (SIGNED=1) or unsigned values.
"""

import json
import random

import numpy as np

from common import TEST_DATA_ROOT, run_cli

COUNTER_DIR = TEST_DATA_ROOT / "BasicModules" / "counter"
RELATIONAL_DIR = TEST_DATA_ROOT / "BasicModules" / "relational"


def write_set(d, params, ports):
    d.mkdir(parents=True, exist_ok=True)
    (d / "params.json").write_text(json.dumps(params, indent=2) + "\n")
    for name, vals in ports.items():
        np.savetxt(d / f"sim_{name}.csv", np.asarray(vals, dtype=np.int64), fmt="%d")


def toml_block(dir_, top, sets, comment):
    lines = [f"# {comment}", "[[simulations]]", f'dir = "{dir_}"', f'top = "{top}"']
    for desc, p in sets:
        lines += [f"# {desc}", "[[simulations.parameters]]"]
        lines += [f"{k} = {v}" for k, v in p.items()]
    return "\n".join(lines)


# --------------------------------------------------------------- counter
def m_counter(p, rst, en):
    """Return dout per cycle (row i = state before edge i)."""
    mask = (1 << p["NBITS"]) - 1
    cnt = p["INIT_VAL"] & mask
    out = []
    for r, e in zip(rst, en):
        out.append(cnt)
        if p["ENABLE_SYNC_RST"] and r:
            cnt = p["RST_VAL"] & mask
        elif not p["ENABLE_ENABLE"] or e:
            step = p["STEP"] if p["COUNT_DIR"] == 0 else -p["STEP"]
            if p["COUNTER_TYPE"] == 1 and cnt == (p["COUNT_TO_VAL"] & mask):
                cnt = p["INIT_VAL"] & mask
            else:
                cnt = (cnt + step) & mask
    return out


def counter_stim(rng, cycles, rst_prob, en_prob):
    rst = [1 if rng.random() < rst_prob else 0 for _ in range(cycles)]
    en = [1 if rng.random() < en_prob else 0 for _ in range(cycles)]
    # a reset held for several cycles and a reset during enable=0
    rst[40:43] = [1, 1, 1]
    en[41] = 0
    return rst, en


COUNTER_SETS = [
    # (simdata index, description, params)
    (5, "count_limit(1), up(0), INIT_VAL=RST_VAL=9, to 17 — Xilinx start_count on power-on/reset/wrap",
     dict(COUNTER_TYPE=1, NBITS=6, COUNT_TO_VAL=17, COUNT_DIR=0, INIT_VAL=9, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, RST_VAL=9)),
    (6, "free_running(0), up(0), RST_VAL=15 — reset to a nonzero value, power-on 0",
     dict(COUNTER_TYPE=0, NBITS=4, COUNT_TO_VAL=0, COUNT_DIR=0, INIT_VAL=0, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, RST_VAL=15)),
    (7, "free_running(0), down(1), RST_VAL=5, no enable port — reset only",
     dict(COUNTER_TYPE=0, NBITS=4, COUNT_TO_VAL=0, COUNT_DIR=1, INIT_VAL=12, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=0, RST_VAL=5)),
    (8, "count_limit(1), down(1), INIT_VAL=20, RST_VAL=3, to 0 — reset value differs from wrap value",
     dict(COUNTER_TYPE=1, NBITS=5, COUNT_TO_VAL=0, COUNT_DIR=1, INIT_VAL=20, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, RST_VAL=3)),
    (9, "free_running(0), up(0), step=3, RST_VAL=0 (default) — clear-to-zero reset with enable",
     dict(COUNTER_TYPE=0, NBITS=8, COUNT_TO_VAL=0, COUNT_DIR=0, INIT_VAL=0, STEP=3,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, RST_VAL=0)),
]


def gen_counter():
    rng = random.Random(20261002)
    sets = []
    for idx, desc, p in COUNTER_SETS:
        rst, en = counter_stim(rng, 300, 0.04, 0.8)
        write_set(COUNTER_DIR / f"simdata{idx}", p,
                  {"rst": rst, "enable": en, "dout": m_counter(p, rst, en)})
        sets.append((desc, p))
    return toml_block("BasicModules", "counter", sets,
                      "counter RST_VAL sets (append to the counter entry)")


# ------------------------------------------------------------ relational
OPS = [lambda a, b: a == b, lambda a, b: a != b, lambda a, b: a < b,
       lambda a, b: a > b, lambda a, b: a <= b, lambda a, b: a >= b]
COMP_NAMES = ["eq", "ne", "lt", "gt", "le", "ge"]


def to_signed(v, n):
    return v - (1 << n) if v >> (n - 1) else v


def m_relational(p, a, b):
    n, lat = p["NBITS"], p["LATENCY"]
    conv = (lambda v: to_signed(v, n)) if p["SIGNED"] else (lambda v: v)
    res = [int(OPS[p["COMP"]](conv(x), conv(y))) for x, y in zip(a, b)]
    return [0] * lat + res[:len(res) - lat]


def gen_relational():
    rng = random.Random(20261003)
    sets = []
    specs = [(8 + c, f"{COMP_NAMES[c]}, SIGNED=1, NBITS=4, LATENCY=1 — all 256 input pairs",
              dict(NBITS=4, COMP=c, LATENCY=1, SIGNED=1)) for c in range(6)]
    specs += [
        (14, "lt, SIGNED=1, NBITS=4, LATENCY=0 — combinational, all 256 input pairs",
         dict(NBITS=4, COMP=2, LATENCY=0, SIGNED=1)),
        (15, "ge, SIGNED=1, NBITS=7, LATENCY=2 — random inputs, multi-stage pipeline",
         dict(NBITS=7, COMP=5, LATENCY=2, SIGNED=1)),
        # NBITS=5 so it does not shadow the Simulink-exported simdata2
        (16, "lt, SIGNED=0 (explicit), NBITS=5, LATENCY=1 — all 1024 input pairs",
         dict(NBITS=5, COMP=2, LATENCY=1, SIGNED=0)),
    ]
    for idx, desc, p in specs:
        n = p["NBITS"]
        if n <= 5:
            pairs = [(x, y) for x in range(1 << n) for y in range(1 << n)]
            rng.shuffle(pairs)
            a, b = [x for x, _ in pairs], [y for _, y in pairs]
        else:
            a = [rng.randrange(1 << n) for _ in range(300)]
            b = [x if rng.random() < 0.15 else rng.randrange(1 << n) for x in a]
        write_set(RELATIONAL_DIR / f"simdata{idx}", p,
                  {"a": a, "b": b, "out": m_relational(p, a, b)})
        sets.append((desc, p))
    return toml_block("BasicModules", "relational", sets,
                      "relational SIGNED sets (append to the relational entry)")


if __name__ == "__main__":
    run_cli(__doc__, {"counter": gen_counter, "relational": gen_relational})
