"""Generate the model-derived test data of the BasicModules.

The Simulink-exported sets (counter simdata0-4, relational simdata0-7, and
the original delay / inverter / logical / multiplexer sets) are left
untouched; this script only writes the sets added for the
backward-compatible parameters and ports

    counter     RST_VAL (with ENABLE_SYNC_RST / ENABLE_ENABLE driven),
                ENABLE_LOAD (load / din), COUNT_DIR = 2 (up port)
    relational  SIGNED, USE_ENABLE
    delay       LATENCY = 0, USE_RST, USE_ENABLE
    inverter, logical, multiplexer   USE_ENABLE

Each new simdataN gets a params.json (the testbench matches the DUT
parameters against it) and sim_<port>.csv files, row i = value driven
before / read after clock edge i (pre-edge read convention).

Models follow the Xilinx System Generator block models
(Vivado data/sysgen/block_models/xl*.sgm):

* Counter (xlCounter.sgm): start_count is the power-on value, the
  synchronous reset value and, for a count-limited counter, the value
  loaded after reaching count_to (the Simulink-exported counter simdata3/4
  wrap to INIT_VAL). Priority: rst, then enable gating (count limit wrap,
  then load, then count up/down).
* Delay (xlDelay.sgm): rst clears every stage, then en shifts; with both
  high stage 0 takes din and the rest clear. LATENCY = 0 is a wire.
* Inverter / Logical / Mux / Relational: en gates the pipeline registers.
* Relational: a op b on the two's complement (SIGNED=1) or unsigned values.
"""

import json
import random

import numpy as np

from common import TEST_DATA_ROOT, run_cli

BASIC_DIR = TEST_DATA_ROOT / "BasicModules"
COUNTER_DIR = BASIC_DIR / "counter"
RELATIONAL_DIR = BASIC_DIR / "relational"


def write_set(d, params, ports):
    d.mkdir(parents=True, exist_ok=True)
    (d / "params.json").write_text(json.dumps(params, indent=2) + "\n")
    for name, vals in ports.items():
        arr = np.asarray(vals, dtype=np.int64)
        if arr.ndim == 2:
            # array port: one file per element, sim_<name><j>.csv = element j
            for j in range(arr.shape[1]):
                np.savetxt(d / f"sim_{name}{j}.csv", arr[:, j], fmt="%d")
        else:
            np.savetxt(d / f"sim_{name}.csv", arr, fmt="%d")


def pipe(vals, en, lat):
    """LATENCY-stage register chain whose shift is gated by en (0 = wire)."""
    if lat == 0:
        return list(vals)
    regs, out = [0] * lat, []
    for v, e in zip(vals, en):
        out.append(regs[-1])
        if e:
            regs = [v] + regs[:-1]
    return out


def en_stim(rng, cycles, prob=0.7):
    en = [1 if rng.random() < prob else 0 for _ in range(cycles)]
    en[20:26] = [0] * 6          # a longer hold
    return en


def toml_block(dir_, top, sets, comment):
    lines = [f"# {comment}", "[[simulations]]", f'dir = "{dir_}"', f'top = "{top}"']
    for desc, p in sets:
        lines += [f"# {desc}", "[[simulations.parameters]]"]
        lines += [f"{k} = {v}" for k, v in p.items()]
    return "\n".join(lines)


# --------------------------------------------------------------- counter
def m_counter(p, rst, en, load=None, din=None, up=None):
    """Return dout per cycle (row i = state before edge i), per xlCounter.sgm."""
    n = len(rst)
    load = load or [0] * n
    din = din or [0] * n
    up = up or [1] * n
    mask = (1 << p["NBITS"]) - 1
    rst_val = p.get("RST_VAL", p["INIT_VAL"])
    cnt = p["INIT_VAL"] & mask
    out = []
    for r, e, ld, d, u in zip(rst, en, load, din, up):
        out.append(cnt)
        if p["ENABLE_SYNC_RST"] and r:
            cnt = rst_val & mask
        elif not p["ENABLE_ENABLE"] or e:
            if p["COUNTER_TYPE"] == 1 and cnt == (p["COUNT_TO_VAL"] & mask):
                cnt = p["INIT_VAL"] & mask
            elif p.get("ENABLE_LOAD", 0) and ld:
                cnt = d & mask
            else:
                count_up = u if p["COUNT_DIR"] == 2 else p["COUNT_DIR"] == 0
                step = p["STEP"] if count_up else -p["STEP"]
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


# Load / up-down sets. RST_VAL is omitted from simulation.toml (the DUT
# default RST_VAL = INIT_VAL applies) but recorded in params.json.
COUNTER_LOAD_SETS = [
    (10, "free_running(0), up_down(2), up port toggling, rst + enable",
     dict(COUNTER_TYPE=0, NBITS=4, COUNT_TO_VAL=0, COUNT_DIR=2, INIT_VAL=6, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, ENABLE_LOAD=0)),
    (11, "count_limit(1), up_down(2), INIT_VAL=3 to 13, step=2 — limit compare in both directions",
     dict(COUNTER_TYPE=1, NBITS=5, COUNT_TO_VAL=13, COUNT_DIR=2, INIT_VAL=3, STEP=2,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, ENABLE_LOAD=0)),
    (12, "free_running(0), up(0), load port, rst + enable — load gated by enable",
     dict(COUNTER_TYPE=0, NBITS=6, COUNT_TO_VAL=0, COUNT_DIR=0, INIT_VAL=0, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=1, ENABLE_LOAD=1)),
    (13, "count_limit(1), down(1), INIT_VAL=10 to 0, load port, rst, no enable — wrap beats load",
     dict(COUNTER_TYPE=1, NBITS=5, COUNT_TO_VAL=0, COUNT_DIR=1, INIT_VAL=10, STEP=1,
          ENABLE_SYNC_RST=1, ENABLE_ENABLE=0, ENABLE_LOAD=1)),
]


def gen_counter():
    rng = random.Random(20261002)
    sets = []
    for idx, desc, p in COUNTER_SETS:
        rst, en = counter_stim(rng, 300, 0.04, 0.8)
        write_set(COUNTER_DIR / f"simdata{idx}", p,
                  {"rst": rst, "enable": en, "dout": m_counter(p, rst, en)})
        sets.append((desc, p))

    rng = random.Random(20261004)
    for idx, desc, p in COUNTER_LOAD_SETS:
        cycles = 300
        rst, en = counter_stim(rng, cycles, 0.03, 0.8)
        mask = (1 << p["NBITS"]) - 1
        load = [1 if rng.random() < 0.08 else 0 for _ in range(cycles)]
        if p["ENABLE_LOAD"]:
            load[60] = 1; en[60] = 0      # load while disabled: ignored
            load[61] = 1; rst[61] = 1     # load during reset: reset wins
        din = [rng.randrange(mask + 1) for _ in range(cycles)]
        up = []
        u = 1
        for _ in range(cycles):
            if rng.random() < 0.08:
                u ^= 1
            up.append(u)
        if not p["ENABLE_LOAD"]:
            load = [0] * cycles
        if p["COUNT_DIR"] != 2:
            up = [1] * cycles
        if p["COUNTER_TYPE"] == 1 and p["ENABLE_LOAD"]:
            # load exactly when the counter sits at COUNT_TO_VAL: the wrap wins
            ref = m_counter(p, rst, en, load, din, up)
            hits = [i for i in range(100, cycles) if ref[i] == p["COUNT_TO_VAL"]]
            for i in hits[:3]:
                load[i] = 1
        full = dict(p, RST_VAL=p["INIT_VAL"])
        write_set(COUNTER_DIR / f"simdata{idx}", full,
                  {"rst": rst, "enable": en, "load": load, "din": din, "up": up,
                   "dout": m_counter(full, rst, en, load, din, up)})
        sets.append((desc, p))
    return toml_block("BasicModules", "counter", sets,
                      "counter RST_VAL / load / up-down sets (append to the counter entry)")


# ------------------------------------------------------------ relational
OPS = [lambda a, b: a == b, lambda a, b: a != b, lambda a, b: a < b,
       lambda a, b: a > b, lambda a, b: a <= b, lambda a, b: a >= b]
COMP_NAMES = ["eq", "ne", "lt", "gt", "le", "ge"]


def to_signed(v, n):
    return v - (1 << n) if v >> (n - 1) else v


def m_relational(p, a, b, en=None):
    n, lat = p["NBITS"], p["LATENCY"]
    conv = (lambda v: to_signed(v, n)) if p["SIGNED"] else (lambda v: v)
    res = [int(OPS[p["COMP"]](conv(x), conv(y))) for x, y in zip(a, b)]
    return pipe(res, en or [1] * len(res), lat)


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

    # USE_ENABLE set
    idx, desc = 17, "gt, SIGNED=1, NBITS=5, LATENCY=2, USE_ENABLE=1 — en holds the pipeline"
    p = dict(NBITS=5, COMP=3, LATENCY=2, SIGNED=1, USE_ENABLE=1)
    a = [rng.randrange(32) for _ in range(300)]
    b = [x if rng.random() < 0.15 else rng.randrange(32) for x in a]
    en = en_stim(rng, 300)
    write_set(RELATIONAL_DIR / f"simdata{idx}", p,
              {"a": a, "b": b, "en": en, "out": m_relational(p, a, b, en)})
    sets.append((desc, p))
    return toml_block("BasicModules", "relational", sets,
                      "relational SIGNED / USE_ENABLE sets (append to the relational entry)")


# ----------------------------------------------------------------- delay
def m_delay(p, din, rst, en):
    """xlDelay.sgm: rst clears every stage, then en shifts (stage 0 <- din)."""
    lat = p["LATENCY"]
    if lat == 0:
        return list(din)
    regs, out = [0] * lat, []
    for d, r, e in zip(din, rst, en):
        r = r and p["USE_RST"]
        e = e or not p["USE_ENABLE"]
        out.append(regs[-1])
        if r:
            regs = [0] * lat
        if e:
            regs = [d] + regs[:-1]
    return out


DELAY_SETS = [
    (1, "LATENCY=0 — wire", dict(LATENCY=0, BITWIDTH=4, USE_RST=0, USE_ENABLE=0)),
    (2, "LATENCY=3, rst + en — includes rst and en high together",
     dict(LATENCY=3, BITWIDTH=4, USE_RST=1, USE_ENABLE=1)),
    (3, "LATENCY=2, en only", dict(LATENCY=2, BITWIDTH=5, USE_RST=0, USE_ENABLE=1)),
    (4, "LATENCY=1, rst only", dict(LATENCY=1, BITWIDTH=3, USE_RST=1, USE_ENABLE=0)),
]


def gen_delay():
    d0 = BASIC_DIR / "delay" / "simdata0"
    p0 = dict(LATENCY=1, BITWIDTH=3, USE_RST=0, USE_ENABLE=0)
    (d0 / "params.json").write_text(json.dumps(p0, indent=2) + "\n")   # data kept as is
    sets = [("LATENCY=1, BITWIDTH=3 — original set", dict(LATENCY=1, BITWIDTH=3))]
    rng = random.Random(20261005)
    for idx, desc, p in DELAY_SETS:
        cycles = 200
        din = [rng.randrange(1 << p["BITWIDTH"]) for _ in range(cycles)]
        rst = [1 if rng.random() < 0.06 else 0 for _ in range(cycles)]
        en = en_stim(rng, cycles)
        rst[30], en[30] = 1, 1          # rst and en together
        rst[31], en[31] = 0, 1
        rst[50], en[50] = 1, 0          # rst while disabled
        ports = {"din": din}
        if p["USE_RST"]:
            ports["rst"] = rst
        if p["USE_ENABLE"]:
            ports["en"] = en
        ports["dout"] = m_delay(p, din, rst, en)
        write_set(BASIC_DIR / "delay" / f"simdata{idx}", p, ports)
        sets.append((desc, p))
    return toml_block("BasicModules", "delay", sets, "test delay")


# ------------------------------------- inverter / logical / multiplexer en
def gen_inverter():
    rng = random.Random(20261006)
    p = dict(NBITS=4, LATENCY=2, USE_ENABLE=1)
    din = [rng.randrange(16) for _ in range(200)]
    en = en_stim(rng, 200)
    write_set(BASIC_DIR / "inverter" / "simdata3", p,
              {"din": din, "en": en, "dout": pipe([~x & 15 for x in din], en, 2)})
    return toml_block("BasicModules", "inverter",
                      [("LATENCY=2, USE_ENABLE=1 — en holds the pipeline", p)],
                      "inverter USE_ENABLE set (append to the inverter entry)")


def gen_logical():
    rng = random.Random(20261007)
    p = dict(NBITS=4, NINPUTS=3, LATENCY=2, FUNC=2, USE_ENABLE=1)
    din = [[rng.randrange(16) for _ in range(3)] for _ in range(200)]
    en = en_stim(rng, 200)
    res = [row[0] | row[1] | row[2] for row in din]
    write_set(BASIC_DIR / "logical" / "simdata8", p,
              {"din": din, "en": en, "dout": pipe(res, en, 2)})
    return toml_block("BasicModules", "logical",
                      [("OR, 3-input, LATENCY=2, USE_ENABLE=1 — en holds the pipeline", p)],
                      "logical USE_ENABLE set (append to the logical entry)")


def gen_multiplexer():
    rng = random.Random(20261008)
    p = dict(NBITS=8, NINPUTS=4, LATENCY=2, USE_ENABLE=1)
    din = [[rng.randrange(256) for _ in range(4)] for _ in range(200)]
    sel = [rng.randrange(4) for _ in range(200)]
    en = en_stim(rng, 200)
    res = [row[s] for row, s in zip(din, sel)]
    write_set(BASIC_DIR / "multiplexer" / "simdata4", p,
              {"din": din, "sel": sel, "en": en, "dout": pipe(res, en, 2)})
    return toml_block("BasicModules", "multiplexer",
                      [("4-input, LATENCY=2, USE_ENABLE=1 — en holds the pipeline", p)],
                      "multiplexer USE_ENABLE set (append to the multiplexer entry)")


if __name__ == "__main__":
    run_cli(__doc__, {"counter": gen_counter, "relational": gen_relational,
                      "delay": gen_delay, "inverter": gen_inverter,
                      "logical": gen_logical, "multiplexer": gen_multiplexer})
