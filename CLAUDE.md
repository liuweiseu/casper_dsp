# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CASPER DSP Blocks — a library of Verilog/SystemVerilog RTL modules for radio astronomy DSP, simulated with [Verilator](https://www.veripool.org/verilator/) and tested via [Cocotb](https://www.cocotb.org) + pytest. All simulation runs inside Docker.

## Running Simulations

**Full test suite (local):**
```bash
sudo ./scripts/run-local-test.sh
```

**Single module (or subset):**
```bash
sudo ./scripts/run-module-test.sh BasicModules/logical   # exact match
sudo ./scripts/run-module-test.sh logical                # substring match
sudo ./scripts/run-module-test.sh BasicModules           # entire category
```
The argument is passed to pytest's `-k` filter. Test IDs follow the `<Category>/<module>` format from `simulation.toml`.

Test results (`.vcd`, `.xml`) land in `tests/results/`. VCD waveforms can be viewed at https://app.surfer-project.org.

## Adding a New Module

1. **RTL**: Place the Verilog/SystemVerilog file under `rtl/<Category>/`. See existing directories under `rtl/` for available categories.

2. **Test data**: Create `test_data/<Category>/<module_name>/` and place CSV input/output files there (e.g., `sim_in.csv`, `sim_out.csv`). Multiple parameter sets use subdirectories (`simdata0/`, `simdata1/`, …).

   Also create a `test_data.md` in that directory documenting the test configurations:
   - Start with `# <module_name> test data` and a brief prose description.
   - For modules with multiple `simdataN` subdirectories, include a Markdown table with these columns **in order**:
     1. `Test #` — 0-indexed integer matching the `simdataN` number (first column)
     2. `Directory` — backtick-quoted name, e.g. `` `simdata0` ``
     3. One column per module parameter
     4. `Cycles` — number of simulation cycles in that data set (if applicable)
     5. `Description` — brief plain-English summary (last column)
   - For modules with a single fixed configuration (no subdirectories), use a two-column `Parameter` / `Value` table instead, and describe the data set in prose.
   - If the testbench derives expected output directly from DUT parameters and requires no CSV files, state this in prose and list the parameter combinations exercised via `simulation.toml` in a table with a `Test #` first column.

3. **Testbench**: Create `testbench/<Category>/<module_name>/test_<module_name>.py`. The directory hierarchy must mirror `rtl/`.
   - Tests are `async` cocotb functions decorated with `@cocotb.test()`. Load CSV data with `np.loadtxt`, drive inputs before `RisingEdge`, sample outputs after.
   - Derive the test data path from `__file__` — do not hardcode it:
     ```python
     _here = Path(__file__).parent
     testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()
     ```
   - The standard loop pattern is `await RisingEdge` then read — never read an output before the first clock edge. `expected[0]` must correspond to the value read after the first rising edge (which, due to cocotb's pre-NB-read convention, reflects the module's initial state):
     ```python
     for i in range(len(sim_out)):
         await RisingEdge(dut.clk)
         actual = int(dut.out.value)
         assert actual == sim_out[i]
     ```

4. **Register in `tests/simulation.toml`**: Add a `[[simulations]]` entry. If the module is parameterized, add one `[[simulations.parameters]]` block per parameter combination.
   - Entries are sorted **alphabetically by directory name, then alphabetically by module name** within each directory. Always insert in the correct sorted position rather than appending to the end.

5. **Documentation**: Create `docs/<Category>/<module_name>.md` summarising the module's function, parameters, and ports.

## Key Infrastructure

| Path | Purpose |
|------|---------|
| `rtl/` | RTL source files, organised by category |
| `testbench/` | Cocotb testbench scripts, mirroring `rtl/` structure |
| `test_data/` | CSV simulation input/output data, mirroring `rtl/` structure |
| `docs/` | Per-module documentation (function, parameters, ports), mirroring `rtl/` structure |
| `platform/xilinx/` | Xilinx UNISIM behavioural simulation models (.v/.sv) |
| `platform/altera/` | Altera behavioural simulation models (.v/.sv) |
| `tests/simulation.toml` | Declares which modules are tested and with what parameters |
| `tests/test_runner.py` | pytest entry point — reads `simulation.toml`, calls cocotb runner |
| `tests/prepare_dump.py` | Pre-test script that injects `$dumpfile`/`$dumpvars` into RTL source to produce VCD output |
| `container/Dockerfile` | Two-stage image: compiles Verilator from source, installs cocotb/pytest |
| `container/docker-compose.local.yml` | Local compose; mounts `tests/results/` for output |

**Important:** `prepare_dump.py` mutates RTL source files in-place before simulation to inject VCD dump blocks. This is expected behavior — the injected lines are not committed.

## Reusing BasicModules

When implementing a module outside of `BasicModules`, prefer instantiating existing `BasicModules` primitives rather than duplicating logic. For example:

- Use `register` for any flip-flop storage or pipeline register stage.
- Use `logical` for bitwise AND/OR/XOR/etc. reduction with optional pipelining.
- Use `delay` to add a fixed number of pipeline stages to a signal.
- Use `counter`, `constant`, `multiplexer`, `inverter`, `slice`, etc. where applicable.

Check `rtl/BasicModules/` for the current set of available primitives before writing new RTL.

## RTL Module Conventions

- Parameterized modules use `parameter` / `parameter int` at the top.
- Reset is synchronous (`always_ff @(posedge clk)` with `rst` input).
- VCD output path follows `tests/results/<Category>/<module>/<module>[_N].vcd`.
- The `SIM` macro is defined during simulation builds (use `ifdef SIM` for sim-only blocks if needed).

## Module Categories

Categories are organized by function. See the `rtl/` directory for the current set of categories and their contents.
