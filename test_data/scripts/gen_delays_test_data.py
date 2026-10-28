#!/usr/bin/env python3
"""Generate test data for the rtl/Delays/ modules.

Expected outputs come from cycle-accurate Python reference models written
from each module's documented contract (not from the RTL).

For every module this writes, under test_data/Delays/<module>/:
  simdataN/params.json   DUT parameters of test N (the testbench uses the
                         integer ones to find the data set matching the DUT)
  simdataN/sim_*.csv     one value per clock cycle for every input port and
                         expected output port (raw unsigned words)
  simdataN/rom_init.mem  (rom only) memory image loaded through INIT_FILE
  test_data.md           table of all test configurations

and prints the matching [[simulations]] blocks for tests/simulation.toml.
Only PLATFORM = "GENERIC" (the default) is exercised; PLATFORM is therefore
not part of any parameter set.

Usage:
  python3 test_data/scripts/gen_delays_test_data.py            # all modules
  python3 test_data/scripts/gen_delays_test_data.py --module <name>
"""

import json
import random
from pathlib import Path

from common import TEST_DATA_ROOT, run_cli

SCRIPT = Path(__file__).name
CATEGORY = "Delays"
TEST_DATA = TEST_DATA_ROOT / CATEGORY

# rom INIT_FILE paths are relative to the simulator's working directory,
# which tests/test_runner.py makes tests/sim_build/<Category>/<module>/.
ROM_INIT_REL = "../../../test_data/Delays/rom/simdata{n}/rom_init.mem"
SPRAM_INIT_REL = "../../../test_data/Delays/single_port_ram/simdata{n}/ram_init.mem"


# ── reference models ────────────────────────────────────────────────────────
# Each model returns one output tuple per cycle, following the pre-edge read
# convention: the value for cycle i is what the DUT outputs while input i is
# applied, i.e. before clock edge i updates the registers.

def m_delay_srl(p, stim):
    n, use_en, use_rst = p["DELAY_LEN"], p["USE_ENABLE"], p["USE_RST"]
    state = [0] * n
    out = []
    for din, rst, en in zip(stim["din"], stim["rst"], stim["en"]):
        if n == 0:
            # combinational; cycle 0 reads 0 (see delayed_din)
            out.append((din if out else 0,))
            continue
        out.append((state[-1],))
        if use_rst and rst:
            state = [0] * n
        elif not use_en or en:
            state = [din] + state[:-1]
    return out


def delayed_din(ins, n):
    """din delayed by n cycles; the first n outputs are the zero power-on state.

    For n = 0 (combinational) cycle 0 still reads 0: the first clock edge
    happens at t = 0, before the first input value reaches the output.
    """
    return [((ins[i - n] if i >= n and i > 0 else 0),) for i in range(len(ins))]


def m_pipeline(p, stim):
    return delayed_din(stim["din"], p["CSP_LATENCY"])


def opt(stim, name, default, cycles):
    """Optional input stream (rst / en), or a constant when the set has none."""
    return stim.get(name, [default] * cycles)


def m_single_port_ram(p, stim, image=None):
    """Xilinx Single Port RAM as simulated in Simulink (all mask options).

    MEM_TYPE 0 Distributed memory / 1 Block RAM / 2 Ultra RAM, WRITE_MODE
    0 Read After Write / 1 Read Before Write / 2 No Read On Write, LATENCY
    pipeline stages (0: combinational read). Stage 0 takes the read word on an
    enabled edge (No Read On Write keeps it on a write); stages 1.. shift on
    enabled edges, or on every edge with Ultra RAM or Block RAM +
    OPTIMIZE_LATENCY. rst acts on the last stage only, whatever en is: Block
    RAM loads INIT_REG (also its power-on value); Ultra RAM clears it
    (latency 1: only when enabled) and masks dout to 0 on the next cycle;
    Distributed memory has no rst. An enabled write still happens. Ultra RAM
    ignores the memory image. An address >= DEPTH reads 0 and does not write.
    """
    cycles = len(stim["we"])
    depth = p.get("DEPTH", 1 << p["ADDR_WIDTH"])
    mt, wm, lat = p.get("MEM_TYPE", 1), p.get("WRITE_MODE", 1), p.get("LATENCY", 1)
    uram = mt == 2
    use_rst = bool(p.get("RST")) and mt != 0
    free = uram or (mt == 1 and p.get("OPTIMIZE_LATENCY", 0))
    init = p.get("INIT_REG", 0) if (use_rst and not uram) else 0
    mem = [0] * depth
    if image and not uram:
        mem[:len(image)] = image[:depth]
    pipe = [0] * lat
    if lat:
        pipe[-1] = init
    mask = 0
    out = []
    rsts = opt(stim, "rst", 0, cycles) if use_rst else [0] * cycles
    ens = opt(stim, "en", 1, cycles) if p.get("EN") else [1] * cycles
    for we, addr, din, rst, en in zip(stim["we"], stim["addr"], stim["din"], rsts, ens):
        rd = mem[addr] if addr < depth else 0
        if lat == 0:
            out.append((rd,))
            if we and addr < depth:
                mem[addr] = din
            continue
        out.append((0 if mask else pipe[-1],))
        new = list(pipe)
        for k in range(1, lat):
            if en or free:
                new[k] = pipe[k - 1]
        if en:
            new[0] = rd if not we else din if wm == 0 else rd if wm == 1 else pipe[0]
            if we and addr < depth:
                mem[addr] = din
        if rst:
            if not uram:
                new[-1] = init
            elif en or lat > 1:
                new[-1] = 0
        mask = int(uram and rst)
        pipe = new
    return out


def m_dual_port_ram(p, stim):
    """Xilinx Dual Port RAM, latency 1, Read Before Write on both ports (built block).

    A disabled port (enx = 0) neither reads nor writes and holds its output;
    rstx loads INIT_X whether or not the port is enabled. Outputs show
    INIT_A / INIT_B in the first cycle only: the output registers power up to
    0, so a port whose first edge is disabled reads 0 until it is enabled.
    """
    cycles = len(stim["we_a"])
    mem = [0] * (1 << p["ADDR_WIDTH"])
    ia, ib = p.get("INIT_A", 0), p.get("INIT_B", 0)
    da, db = 0, 0
    ena = opt(stim, "ena", 1, cycles) if p.get("EN_A") else [1] * cycles
    enb = opt(stim, "enb", 1, cycles) if p.get("EN_B") else [1] * cycles
    rsta = opt(stim, "rsta", 0, cycles) if p.get("RST_A") else [0] * cycles
    rstb = opt(stim, "rstb", 0, cycles) if p.get("RST_B") else [0] * cycles
    out = []
    for t, (we_a, addr_a, din_a, we_b, addr_b, din_b) in enumerate(zip(
            stim["we_a"], stim["addr_a"], stim["din_a"],
            stim["we_b"], stim["addr_b"], stim["din_b"])):
        out.append((ia, ib) if t == 0 else (da, db))
        ra, rb = mem[addr_a], mem[addr_b]    # READ_FIRST on both ports
        da = ia if rsta[t] else (ra if ena[t] else da)
        db = ib if rstb[t] else (rb if enb[t] else db)
        if ena[t] and we_a:
            mem[addr_a] = din_a
        if enb[t] and we_b:
            mem[addr_b] = din_b
    return out


def m_rom(p, stim, image):
    """Xilinx ROM, latency 1 (built block): en = 0 freezes dout; rst loads
    INIT_REG whatever en is. dout shows INIT_REG in the first cycle only: the
    output register powers up to 0, so a disabled first edge leaves 0."""
    cycles = len(stim["addr"])
    dout = 0
    rsts = opt(stim, "rst", 0, cycles) if p.get("RST") else [0] * cycles
    ens = opt(stim, "en", 1, cycles) if p.get("EN") else [1] * cycles
    out = []
    for t, (addr, rst, en) in enumerate(zip(stim["addr"], rsts, ens)):
        out.append((p.get("INIT_REG", 0) if t == 0 else dout,))
        if rst:
            dout = p.get("INIT_REG", 0)
        elif en:
            dout = image[addr]
    return out


def m_delay_bram(p, stim):
    """din delayed DELAY_LEN cycles; with ASYNC a delay of DELAY_LEN enabled
    samples that holds while en = 0 (delay_bram_init.m:104-158: counter, RAM
    and output stages all gated by en; checked against Simulink)."""
    if not p.get("ASYNC"):
        return delayed_din(stim["din"], p["DELAY_LEN"])
    n, sr, out = p["DELAY_LEN"], [0] * p["DELAY_LEN"], []
    for d, e in zip(stim["din"], stim["en"]):
        out.append((sr[-1],))
        if e:
            sr = [d] + sr[:-1]
    return out


def s_delay_bram(rng, p, cycles):
    """din, plus a random en for ASYNC sets (~70 % high, a few long gaps)."""
    s = s_din(rng, p["BITWIDTH"], cycles)
    if p.get("ASYNC"):
        en = [1 if rng.random() < 0.75 else 0 for _ in range(cycles)]
        for start in (cycles // 4, cycles // 2):
            en[start:start + 8] = [0] * 8
        s["en"] = en
    return s


# ── stimulus ────────────────────────────────────────────────────────────────

def s_delay_srl(rng, p, cycles):
    w = p["BITWIDTH"]
    rst = [1 if rng.random() < 0.05 else 0 for _ in range(cycles)]
    rst[cycles // 2] = 1          # at least one reset mid-run
    return {
        "din": [rng.randrange(1 << w) for _ in range(cycles)],
        "rst": rst,
        "en":  [1 if rng.random() < 0.7 else 0 for _ in range(cycles)],
    }


def s_din(rng, width, cycles):
    return {"din": [rng.randrange(1 << width) for _ in range(cycles)]}


def s_options(rng, p, cycles, names):
    """Random streams for the enabled optional ports: {param: port}.

    Drawn after the other stimulus, so sets without options are unchanged.
    en is mostly 1, rst rare (plus one reset mid-run).
    """
    s = {}
    for param, port in names.items():
        if not p.get(param):
            continue
        if param.startswith("EN"):
            s[port] = [1 if rng.random() < 0.7 else 0 for _ in range(cycles)]
        else:
            s[port] = [1 if rng.random() < 0.06 else 0 for _ in range(cycles)]
            s[port][cycles // 2] = 1
    return s


def s_single_port_ram(rng, p, cycles):
    dw, aw = p["DATA_WIDTH"], p["ADDR_WIDTH"]
    depth = p.get("DEPTH", 1 << aw)
    # write-heavy first half (fills the memory), read-heavy second half
    we = [int(rng.random() < (0.75 if i < cycles // 2 else 0.25)) for i in range(cycles)]
    s = {
        "we": we,
        "addr": [rng.randrange(depth) for _ in range(cycles)],
        "din": [rng.randrange(1 << dw) for _ in range(cycles)],
    }
    s = dict(s, **s_options(rng, p, cycles, {"RST": "rst", "EN": "en"}))
    if p.get("MEM_TYPE", 1) == 0:
        s.pop("rst", None)        # Distributed memory has no rst port
    return s


def s_spram_sweep(stim, depth):
    """Start with an enabled, reset-free read of every address in order (shows
    the power-on contents)."""
    for i in range(min(depth, len(stim["we"]))):
        stim["we"][i], stim["addr"][i] = 0, i
        for port, value in (("en", 1), ("rst", 0)):
            if port in stim:
                stim[port][i] = value


def s_dual_port_ram(rng, p, cycles):
    dw, aw = p["DATA_WIDTH"], p["ADDR_WIDTH"]
    s = {k: [] for k in ["we_a", "addr_a", "din_a", "we_b", "addr_b", "din_b"]}
    for _ in range(cycles):
        we_a, we_b = rng.randrange(2), rng.randrange(2)
        addr_a, addr_b = rng.randrange(1 << aw), rng.randrange(1 << aw)
        # cross-port collisions are undefined by the contract: avoid them
        if addr_a == addr_b and (we_a or we_b):
            addr_b = (addr_a + 1) % (1 << aw)
        for k, v in [("we_a", we_a), ("addr_a", addr_a), ("din_a", rng.randrange(1 << dw)),
                     ("we_b", we_b), ("addr_b", addr_b), ("din_b", rng.randrange(1 << dw))]:
            s[k].append(v)
    return dict(s, **s_options(rng, p, cycles, {"EN_A": "ena", "EN_B": "enb",
                                                 "RST_A": "rsta", "RST_B": "rstb"}))


def s_rom(rng, p, cycles):
    aw = p["ADDR_WIDTH"]
    # sequential sweep of every address, then random reads
    addrs = [i % (1 << aw) for i in range(1 << aw)]
    addrs += [rng.randrange(1 << aw) for _ in range(cycles - len(addrs))]
    return {"addr": addrs[:cycles]}


def s_rom_options(rng, p, cycles):
    """ROM stimulus plus the enabled rst / en streams (drawn after the image)."""
    return s_options(rng, p, cycles, {"RST": "rst", "EN": "en"})


# ── test configurations ─────────────────────────────────────────────────────

def P(names, values):
    return dict(zip(names, values))


SRL = ["BITWIDTH", "DELAY_LEN", "USE_ENABLE", "USE_RST"]
PIPE = ["BITWIDTH", "CSP_LATENCY"]   # casper pipeline mask: csp_latency
RAM = ["DATA_WIDTH", "ADDR_WIDTH"]
BRAM = ["BITWIDTH", "DELAY_LEN"]

MODULES = {
    "delay_srl": dict(
        inputs=["din", "rst", "en"], outputs=["dout"],
        stim=s_delay_srl, model=m_delay_srl,
        prose="`delay_srl` delays `din` by `DELAY_LEN` (enabled) cycles, with "
              "an optional synchronous reset and clock enable. `rst` pulses "
              "(~5 % of cycles, plus one forced mid-run) and `en` (~70 % high) "
              "are random.",
        tests=[
            (P(SRL, [8, 4, 1, 1]), 256, "enable + reset"),
            (P(SRL, [8, 4, 0, 1]), 256, "reset only (en ignored)"),
            (P(SRL, [8, 4, 1, 0]), 256, "enable only (rst ignored)"),
            (P(SRL, [16, 16, 0, 0]), 256, "plain 16-stage shift register"),
            (P(SRL, [1, 1, 1, 1]), 256, "1-bit, single stage"),
            (P(SRL, [8, 0, 1, 1]), 256, "DELAY_LEN = 0: combinational pass-through"),
        ]),
    "pipeline": dict(
        inputs=["din"], outputs=["dout"],
        stim=lambda rng, p, c: s_din(rng, p["BITWIDTH"], c), model=m_pipeline,
        prose="`pipeline` delays `din` by `CSP_LATENCY` cycles (no reset / enable).",
        tests=[
            (P(PIPE, [8, 0]), 256, "CSP_LATENCY = 0: combinational pass-through"),
            (P(PIPE, [8, 1]), 256, "single register"),
            (P(PIPE, [8, 3]), 256, "3-stage pipeline"),
            (P(PIPE, [12, 8]), 256, "8-stage pipeline, 12-bit"),
            (P(PIPE, [1, 5]), 256, "1-bit, 5 stages"),
        ]),
    "single_port_ram": dict(
        inputs=["we", "addr", "din"], outputs=["dout"],
        stim=s_single_port_ram, model=m_single_port_ram,
        prose="`single_port_ram` is the Xilinx Single Port RAM with every mask "
              "option (memory type, write mode, latency, rst / en, "
              "optimize_latency, depth, initial contents), modelled as the "
              "block simulates in Simulink (see `docs/Delays/single_port_ram.md`). "
              "The first half of each run is write-heavy (75 % writes) to fill "
              "the memory, the second half read-heavy (25 % writes); every write "
              "is also a read-during-write of the same address. Sets with "
              "`RST` / `EN` drive random `sim_rst.csv` (rare, plus one "
              "mid-run) / `sim_en.csv` (70 % high); Distributed memory sets "
              "have no `sim_rst.csv` (the block has no rst port). Tests 6 and "
              "later start with an enabled read of every address in order, and "
              "those with an `INIT_FILE` load `ram_init.mem` from their "
              "directory (random raw words, one hex word per line; a file "
              "shorter than `DEPTH` leaves the other words 0). The other sets "
              "leave the options at their defaults (not in `params.json`).",
        tests=[
            (P(RAM, [8, 4]), 512, "16 × 8"),
            (P(RAM, [16, 6]), 512, "64 × 16"),
            (P(RAM, [1, 3]), 256, "8 × 1"),
            (P(RAM, [32, 8]), 1024, "256 × 32"),
            (dict(P(RAM, [8, 4]), RST=1, EN=1, INIT_REG=0xA5), 512,
             "16 × 8 with rst / en ports, init_reg 0xA5"),
            (dict(P(RAM, [6, 3]), EN=1), 256, "8 × 6 with the en port only"),
            (dict(P(RAM, [8, 4]), WRITE_MODE=0, RST=1, EN=1, INIT_REG=0x5A), 400,
             "Read After Write (mask default), rst / en, initVector"),
            (dict(P(RAM, [8, 4]), WRITE_MODE=2, RST=1, EN=1, INIT_REG=0x33), 400,
             "No Read On Write, rst / en, initVector"),
            (dict(P(RAM, [8, 4]), LATENCY=2, RST=1, EN=1, INIT_REG=0x77), 400,
             "latency 2, Read Before Write, rst / en"),
            (dict(P(RAM, [8, 4]), LATENCY=3, WRITE_MODE=2, RST=1, EN=1, INIT_REG=0xC8), 400,
             "latency 3, No Read On Write, rst / en"),
            (dict(P(RAM, [8, 4]), LATENCY=3, WRITE_MODE=0, RST=1, EN=1, INIT_REG=0x0F, OPTIMIZE_LATENCY=1), 400,
             "latency 3, optimize_latency (stages 1, 2 ignore en), Read After Write"),
            (dict(P(RAM, [8, 4]), MEM_TYPE=0, LATENCY=0), 300,
             "Distributed memory, latency 0 (combinational read), initVector"),
            (dict(P(RAM, [8, 4]), MEM_TYPE=0, WRITE_MODE=0, EN=1), 400,
             "Distributed memory, latency 1, Read After Write, en"),
            (dict(P(RAM, [10, 5]), MEM_TYPE=0, LATENCY=2, RST=1, EN=1, INIT_REG=0x155), 400,
             "Distributed memory, latency 2, en; rst checked but no port (no effect)"),
            (dict(P(RAM, [8, 4]), MEM_TYPE=2, RST=1, EN=1, INIT_REG=0x44), 400,
             "Ultra RAM, latency 1, rst / en (init_reg and initVector ignored)"),
            (dict(P(RAM, [8, 4]), MEM_TYPE=2, LATENCY=3, WRITE_MODE=2, RST=1, EN=1), 400,
             "Ultra RAM, latency 3, No Read On Write, rst / en (stages 1, 2 ignore en)"),
            (dict(P(RAM, [8, 4]), MEM_TYPE=2, LATENCY=2, WRITE_MODE=0, EN=1), 400,
             "Ultra RAM, latency 2, Read After Write, en only"),
            (dict(P(RAM, [8, 5]), DEPTH=24, LATENCY=2, RST=1, EN=1, INIT_REG=0x99), 400,
             "depth 24 (not a power of two), latency 2, 10-word initVector"),
            (dict(P(RAM, [8, 4]), LATENCY=2, WRITE_MODE=2, RST=1, EN=1, INIT_REG=0x21, OPTIMIZE_LATENCY=1), 400,
             "latency 2, optimize_latency, No Read On Write"),
            (dict(P(RAM, [12, 6]), LATENCY=4, WRITE_MODE=0, RST=1, EN=1, INIT_REG=0xABC), 600,
             "64 × 12, latency 4, Read After Write, rst / en, initVector"),
        ]),
    "dual_port_ram": dict(
        inputs=["we_a", "addr_a", "din_a", "we_b", "addr_b", "din_b"],
        outputs=["dout_a", "dout_b"],
        stim=s_dual_port_ram, model=m_dual_port_ram,
        prose="`dual_port_ram` is a true dual-port, common-clock RAM (READ_FIRST "
              "on each port, 1-cycle registered reads). Both ports read and "
              "write at random (50 % writes each); cross-port collisions "
              "(same address with a write), which the contract leaves "
              "undefined, are removed from the stimulus by moving port B to "
              "the next address. Sets with `RST_x` / `EN_x` drive random "
              "`sim_rstx.csv` / `sim_enx.csv` as Xilinx `xlDPBRAMXPM.sgm` "
              "(latency 1): a disabled port neither reads nor writes and holds "
              "its output, `rstx` loads `INIT_X` even on a disabled port, and "
              "the outputs show `INIT_A` / `INIT_B` in cycle 0 only, then 0 "
              "until the port's first enabled read (checked against Simulink); the other sets "
              "leave the options at 0 (not in `params.json`).",
        tests=[
            (P(RAM, [8, 4]), 512, "16 × 8"),
            (P(RAM, [16, 6]), 512, "64 × 16"),
            (P(RAM, [32, 5]), 512, "32 × 32"),
            (dict(P(RAM, [8, 4]), RST_A=1, RST_B=1, EN_A=1, EN_B=1, INIT_A=0x5A, INIT_B=0x3C), 512,
             "16 × 8 with rsta / rstb / ena / enb, init_a 0x5A, init_b 0x3C"),
            (dict(P(RAM, [12, 5]), EN_B=1, RST_A=1, INIT_A=0x123), 512,
             "32 × 12 with enb and rsta only, init_a 0x123"),
        ]),
    "rom": dict(
        inputs=["addr"], outputs=["dout"],
        stim=s_rom, model=None,
        prose="`rom` reads a memory image loaded from `INIT_FILE` with a "
              "1-cycle registered read. Each run first sweeps every address in "
              "order, then reads at random. The image is `rom_init.mem` in the "
              "same directory (random words, one hex word per line); "
              "`INIT_FILE` is its path relative to the simulator's working "
              "directory `tests/sim_build/Delays/rom/`. Test 3 has no "
              "`INIT_FILE`, so every word must read as 0. Sets with `RST` / "
              "`EN` drive random `sim_rst.csv` / `sim_en.csv` as Xilinx "
              "block (latency 1, checked against Simulink): `en` = 0 freezes "
              "`dout`, `rst` loads `INIT_REG` whatever `en` is; `dout` shows "
              "`INIT_REG` in cycle 0 only, then 0 until the first enabled read.",
        tests=[
            (P(RAM, [8, 4]), 256, "16 × 8"),
            (P(RAM, [16, 8]), 512, "256 × 16"),
            (P(RAM, [18, 5]), 256, "32 × 18 (twiddle-coefficient width)"),
            (P(RAM, [8, 3]), 64, "no INIT_FILE: all words 0"),
            (dict(P(RAM, [8, 4]), RST=1, EN=1, INIT_REG=0x3C), 256,
             "16 × 8 with rst / en ports, init_reg 0x3C"),
        ]),
    "delay_bram": dict(
        inputs=["din"], outputs=["dout"],
        stim=s_delay_bram, model=m_delay_bram,
        prose="`delay_bram` delays `din` by `DELAY_LEN` cycles using a RAM "
              "(read-first single-port RAM plus an address counter that wraps "
              "at `DELAY_LEN`−1), or a register pipeline when `DELAY_LEN` < 2. "
              "Sets with `ASYNC` = 1 drive a random `sim_en.csv` (about 75 % high, "
              "plus two 8-cycle gaps): casper's async mode stalls the counter, the "
              "RAM and its output, so `dout` is `din` delayed by `DELAY_LEN` "
              "enabled samples and holds while `en` = 0 (checked against Simulink, "
              "MATLAB R2021a). `BRAM_LATENCY` only matters to Simulink.",
        tests=[
            (P(BRAM, [8, 2]), 256, "shortest RAM-based delay (1-word address range)"),
            (P(BRAM, [8, 5]), 256, "address range 4 (power of two)"),
            (P(BRAM, [8, 16]), 256, "address range 15 (not a power of two)"),
            (P(BRAM, [16, 100]), 512, "100-cycle delay"),
            (P(BRAM, [18, 1000]), 2500, "1000-cycle delay"),
            (P(BRAM, [4, 1]), 256, "DELAY_LEN = 1: register fallback"),
            (P(BRAM, [4, 0]), 256, "DELAY_LEN = 0: combinational fallback"),
            (dict(P(BRAM, [8, 16]), BRAM_LATENCY=2, ASYNC=1), 400,
             "async, bram_latency 2: random en stalls the delay line (16 enabled samples)"),
            (dict(P(BRAM, [8, 20]), BRAM_LATENCY=3, ASYNC=1), 400,
             "async, bram_latency 3, 20 enabled samples"),
        ]),
}

# rom test 3 has no init file; the others get one
ROM_NO_INIT = {3}
# single_port_ram tests with an INIT_FILE: test -> number of words in the image
# (fewer than DEPTH leaves the other words 0, as a short initVector does)
SPRAM_INIT = {6: 16, 7: 16, 11: 16, 14: 16, 17: 10, 19: 64}


# ── writers ─────────────────────────────────────────────────────────────────

def full_params(name, n, params):
    """Parameter set as written to params.json / simulation.toml."""
    if name == "rom":
        return dict(params, INIT_FILE="" if n in ROM_NO_INIT else ROM_INIT_REL.format(n=n))
    if name == "single_port_ram" and n in SPRAM_INIT:
        return dict(params, INIT_FILE=SPRAM_INIT_REL.format(n=n))
    return dict(params)


def write_module(name, spec):
    mdir = TEST_DATA / name
    for n, (params, cycles, _) in enumerate(spec["tests"]):
        rng = random.Random(f"{name}-{n}")
        d = mdir / f"simdata{n}"
        d.mkdir(parents=True, exist_ok=True)
        stim = spec["stim"](rng, params, cycles)
        if name == "rom":
            dw, aw = params["DATA_WIDTH"], params["ADDR_WIDTH"]
            if n in ROM_NO_INIT:
                image = [0] * (1 << aw)
            else:
                image = [rng.randrange(1 << dw) for _ in range(1 << aw)]
                digits = (dw + 3) // 4
                (d / "rom_init.mem").write_text("".join(f"{v:0{digits}x}\n" for v in image))
            stim.update(s_rom_options(rng, params, cycles))
            results = m_rom(params, stim, image)
        elif name == "single_port_ram" and n >= 6:
            # tests 6..: optional memory image and an initial read sweep
            dw, depth = params["DATA_WIDTH"], params.get("DEPTH", 1 << params["ADDR_WIDTH"])
            image = None
            if n in SPRAM_INIT:
                image = [rng.randrange(1 << dw) for _ in range(SPRAM_INIT[n])]
                (d / "ram_init.mem").write_text("".join(f"{v:0{(dw + 3) // 4}x}\n" for v in image))
            s_spram_sweep(stim, depth)
            results = m_single_port_ram(params, stim, image)
        else:
            results = spec["model"](params, stim)
        (d / "params.json").write_text(json.dumps(full_params(name, n, params), indent=2) + "\n")
        for port in spec["inputs"] + [k for k in stim if k not in spec["inputs"]]:
            (d / f"sim_{port}.csv").write_text("".join(f"{v}\n" for v in stim[port]))
        for k, port in enumerate(spec["outputs"]):
            (d / f"sim_{port}.csv").write_text("".join(f"{r[k]}\n" for r in results))
    (mdir / "test_data.md").write_text(test_data_md(name, spec))


OPTION_DEFAULTS = {"ASYNC": 0, "BRAM_LATENCY": 2, "RST": 0, "EN": 0, "INIT_REG": 0, "DEPTH": "2^ADDR_WIDTH",
                   "MEM_TYPE": 1, "WRITE_MODE": 1, "LATENCY": 1, "OPTIMIZE_LATENCY": 0, "RST_A": 0, "RST_B": 0, "EN_A": 0,
                   "EN_B": 0, "INIT_A": 0, "INIT_B": 0}


def test_data_md(name, spec):
    keys = list(dict.fromkeys(k for params, _, _ in spec["tests"] for k in params))
    ins = ", ".join(f"`sim_{p}.csv`" for p in spec["inputs"])
    outs = ", ".join(f"`sim_{p}.csv`" for p in spec["outputs"])
    lines = [
        f"# {name} test data",
        "",
        spec["prose"],
        "",
        "Generated by `test_data/scripts/gen_delays_test_data.py` from cycle-accurate "
        "Python reference models of the documented behavior (not exported "
        "from MATLAB). Each `simdataN/` holds a `params.json` with the DUT "
        "parameters (the testbench uses the integer ones to select the data "
        f"set), input values {ins} and expected output values {outs}, one "
        "per clock cycle. Expected outputs follow the pre-edge read "
        "convention: the value for cycle i is sampled after clock edge i but "
        "reflects the state before it, so the first latency cycles show the "
        "zero power-on state.",
        "",
        "Only `PLATFORM = \"GENERIC\"` (the default) is simulated here. The "
        "XILINX implementation is checked against GENERIC separately with "
        "Vivado xsim (`platform/xilinx/sim/run_xsim_equiv.sh`).",
        "",
        "| Test # | Directory | " + " | ".join(keys) + " | Cycles | Description |",
        "|" + "---|" * (len(keys) + 4),
    ]
    for n, (params, cycles, desc) in enumerate(spec["tests"]):
        vals = " | ".join(str(params.get(k, OPTION_DEFAULTS.get(k))) for k in keys)
        lines.append(f"| {n} | `simdata{n}` | {vals} | {cycles} | {desc} |")
    return "\n".join(lines) + "\n"


def toml_value(v):
    return f'"{v}"' if isinstance(v, str) else str(v)


def toml_block(name, spec):
    lines = [f"# test {name}", "[[simulations]]", f'dir = "{CATEGORY}"', f'top = "{name}"',
             f'test_data_script = "{SCRIPT}"']
    for n, (params, _, desc) in enumerate(spec["tests"]):
        lines.append(f"# {desc}")
        lines.append("[[simulations.parameters]]")
        for k, v in full_params(name, n, params).items():
            if name == "rom" and k == "INIT_FILE" and v == "":
                continue  # default: no init file
            lines.append(f"{k} = {toml_value(v)}")
    return "\n".join(lines)


def generator(name):
    def gen():
        write_module(name, MODULES[name])
        return toml_block(name, MODULES[name])
    return gen


def main():
    run_cli(__doc__, {name: generator(name) for name in MODULES})


if __name__ == "__main__":
    main()
