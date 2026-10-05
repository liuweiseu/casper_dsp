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
    return delayed_din(stim["din"], p["LATENCY"])


def m_single_port_ram(p, stim):
    mem = [0] * (1 << p["ADDR_WIDTH"])
    dout = 0
    out = []
    for we, addr, din in zip(stim["we"], stim["addr"], stim["din"]):
        out.append((dout,))
        dout = mem[addr]            # READ_FIRST: old contents
        if we:
            mem[addr] = din
    return out


def m_dual_port_ram(p, stim):
    mem = [0] * (1 << p["ADDR_WIDTH"])
    da = db = 0
    out = []
    for we_a, addr_a, din_a, we_b, addr_b, din_b in zip(
            stim["we_a"], stim["addr_a"], stim["din_a"],
            stim["we_b"], stim["addr_b"], stim["din_b"]):
        out.append((da, db))
        da, db = mem[addr_a], mem[addr_b]   # READ_FIRST on both ports
        if we_a:
            mem[addr_a] = din_a
        if we_b:
            mem[addr_b] = din_b
    return out


def m_rom(p, stim, image):
    dout = 0
    out = []
    for addr in stim["addr"]:
        out.append((dout,))
        dout = image[addr]
    return out


def m_delay_bram(p, stim):
    return delayed_din(stim["din"], p["DELAY_LEN"])


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


def s_single_port_ram(rng, p, cycles):
    dw, aw = p["DATA_WIDTH"], p["ADDR_WIDTH"]
    # write-heavy first half (fills the memory), read-heavy second half
    we = [int(rng.random() < (0.75 if i < cycles // 2 else 0.25)) for i in range(cycles)]
    return {
        "we": we,
        "addr": [rng.randrange(1 << aw) for _ in range(cycles)],
        "din": [rng.randrange(1 << dw) for _ in range(cycles)],
    }


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
    return s


def s_rom(rng, p, cycles):
    aw = p["ADDR_WIDTH"]
    # sequential sweep of every address, then random reads
    addrs = [i % (1 << aw) for i in range(1 << aw)]
    addrs += [rng.randrange(1 << aw) for _ in range(cycles - len(addrs))]
    return {"addr": addrs[:cycles]}


# ── test configurations ─────────────────────────────────────────────────────

def P(names, values):
    return dict(zip(names, values))


SRL = ["BITWIDTH", "DELAY_LEN", "USE_ENABLE", "USE_RST"]
PIPE = ["BITWIDTH", "LATENCY"]
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
        prose="`pipeline` delays `din` by `LATENCY` cycles (no reset / enable).",
        tests=[
            (P(PIPE, [8, 0]), 256, "LATENCY = 0: combinational pass-through"),
            (P(PIPE, [8, 1]), 256, "single register"),
            (P(PIPE, [8, 3]), 256, "3-stage pipeline"),
            (P(PIPE, [12, 8]), 256, "8-stage pipeline, 12-bit"),
            (P(PIPE, [1, 5]), 256, "1-bit, 5 stages"),
        ]),
    "single_port_ram": dict(
        inputs=["we", "addr", "din"], outputs=["dout"],
        stim=s_single_port_ram, model=m_single_port_ram,
        prose="`single_port_ram` is a READ_FIRST single-port RAM with a "
              "1-cycle registered read. The first half of each run is "
              "write-heavy (75 % writes) to fill the memory, the second half "
              "read-heavy (25 % writes); every write is also a "
              "read-during-write of the same address.",
        tests=[
            (P(RAM, [8, 4]), 512, "16 × 8"),
            (P(RAM, [16, 6]), 512, "64 × 16"),
            (P(RAM, [1, 3]), 256, "8 × 1"),
            (P(RAM, [32, 8]), 1024, "256 × 32"),
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
              "the next address.",
        tests=[
            (P(RAM, [8, 4]), 512, "16 × 8"),
            (P(RAM, [16, 6]), 512, "64 × 16"),
            (P(RAM, [32, 5]), 512, "32 × 32"),
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
              "`INIT_FILE`, so every word must read as 0.",
        tests=[
            (P(RAM, [8, 4]), 256, "16 × 8"),
            (P(RAM, [16, 8]), 512, "256 × 16"),
            (P(RAM, [18, 5]), 256, "32 × 18 (twiddle-coefficient width)"),
            (P(RAM, [8, 3]), 64, "no INIT_FILE: all words 0"),
        ]),
    "delay_bram": dict(
        inputs=["din"], outputs=["dout"],
        stim=lambda rng, p, c: s_din(rng, p["BITWIDTH"], c), model=m_delay_bram,
        prose="`delay_bram` delays `din` by `DELAY_LEN` cycles using a RAM "
              "(read-first single-port RAM plus an address counter that wraps "
              "at `DELAY_LEN`−1), or a register pipeline when `DELAY_LEN` < 2.",
        tests=[
            (P(BRAM, [8, 2]), 256, "shortest RAM-based delay (1-word address range)"),
            (P(BRAM, [8, 5]), 256, "address range 4 (power of two)"),
            (P(BRAM, [8, 16]), 256, "address range 15 (not a power of two)"),
            (P(BRAM, [16, 100]), 512, "100-cycle delay"),
            (P(BRAM, [18, 1000]), 2500, "1000-cycle delay"),
            (P(BRAM, [4, 1]), 256, "DELAY_LEN = 1: register fallback"),
            (P(BRAM, [4, 0]), 256, "DELAY_LEN = 0: combinational fallback"),
        ]),
}

# rom test 3 has no init file; the others get one
ROM_NO_INIT = {3}


# ── writers ─────────────────────────────────────────────────────────────────

def full_params(name, n, params):
    """Parameter set as written to params.json / simulation.toml."""
    if name == "rom":
        return dict(params, INIT_FILE="" if n in ROM_NO_INIT else ROM_INIT_REL.format(n=n))
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
            results = m_rom(params, stim, image)
        else:
            results = spec["model"](params, stim)
        (d / "params.json").write_text(json.dumps(full_params(name, n, params), indent=2) + "\n")
        for port in spec["inputs"]:
            (d / f"sim_{port}.csv").write_text("".join(f"{v}\n" for v in stim[port]))
        for k, port in enumerate(spec["outputs"]):
            (d / f"sim_{port}.csv").write_text("".join(f"{r[k]}\n" for r in results))
    (mdir / "test_data.md").write_text(test_data_md(name, spec))


def test_data_md(name, spec):
    keys = list(spec["tests"][0][0].keys())
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
        vals = " | ".join(str(params[k]) for k in keys)
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
