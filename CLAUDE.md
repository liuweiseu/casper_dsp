# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CASPER DSP Blocks — a library of Verilog/SystemVerilog RTL modules for radio astronomy DSP, simulated with [Verilator](https://www.veripool.org/verilator/) and tested via [Cocotb](https://www.cocotb.org) + pytest. All simulation runs inside Docker.

## Running Simulations

**Full test suite (local):**
```bash
sudo ./scripts/run-local-test.sh
```
This builds the Docker image, runs all tests, and cleans up. Test results (`.vcd`, `.xml`) land in `tests/results/`.

VCD waveforms can be viewed at https://app.surfer-project.org.

## Adding a New Module

1. **RTL**: Place the Verilog/SystemVerilog file under `rtl/<Category>/`. See existing directories under `rtl/` for available categories.

2. **Testbench**: Create `testbench/<Category>/<module_name>/test_<module_name>.py`. The directory hierarchy must mirror `rtl/`.
   - Input/expected-output data goes in CSV files alongside the test script (e.g., `sim_in.csv`, `sim_out.csv`). Multiple parameter sets use subdirectories (`simdata0/`, `simdata1/`, …).
   - Tests are `async` cocotb functions decorated with `@cocotb.test()`. Load CSV data with `np.loadtxt`, drive inputs before `RisingEdge`, sample outputs after.

3. **Register in `tests/simulation.toml`**: Add a `[[simulations]]` entry. If the module is parameterized, add one `[[simulations.parameters]]` block per parameter combination.

## Key Infrastructure

| Path | Purpose |
|------|---------|
| `tests/simulation.toml` | Declares which modules are tested and with what parameters |
| `tests/test_runner.py` | pytest entry point — reads `simulation.toml`, calls cocotb runner |
| `tests/prepare_dump.py` | Pre-test script that injects `$dumpfile`/`$dumpvars` into RTL source to produce VCD output |
| `container/Dockerfile` | Two-stage image: compiles Verilator from source, installs cocotb/pytest |
| `container/docker-compose.local.yml` | Local compose; mounts `tests/results/` for output |

**Important:** `prepare_dump.py` mutates RTL source files in-place before simulation to inject VCD dump blocks. This is expected behavior — the injected lines are not committed.

## RTL Module Conventions

- Parameterized modules use `parameter` / `parameter int` at the top.
- Reset is synchronous (`always_ff @(posedge clk)` with `rst` input).
- VCD output path follows `tests/results/<Category>/<module>/<module>[_N].vcd`.
- The `SIM` macro is defined during simulation builds (use `ifdef SIM` for sim-only blocks if needed).

## Module Categories

Categories are organized by function. See the `rtl/` directory for the current set of categories and their contents.
