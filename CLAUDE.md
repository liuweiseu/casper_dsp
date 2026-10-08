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

2. **Test data**: Create `test_data/<Category>/<module_name>/` and place CSV input/output files there. Multiple parameter sets use subdirectories (`simdata0/`, `simdata1/`, …).
   - Every CSV is named `sim_<port>.csv`, where `<port>` is the exact name of the DUT port it drives or checks (e.g. `sim_din.csv`, `sim_dout.csv` for ports `din`/`dout`). Do not use generic names such as `sim_in.csv`/`sim_out.csv` unless the port really is called `in`/`out`.
   - Every CSV holds exactly one signal, one value per line. An array port (e.g. `din [N]`, or a packed `[N-1:0][W-1:0]` array) gets one file per element: `sim_din0.csv`, `sim_din1.csv`, …, file j = `din[j]` (also when N = 1). Testbenches load them with `testbench/csv_ports.py` (`load_rows` stacks the element files into rows; `load_packed` packs them for a packed array port); generators write them by passing one list per row (e.g. `write_csv` in `test_data/scripts/gen_butterfly_test_data.py`).

   Also create a `test_data.md` in that directory documenting the test configurations:
   - Start with `# <module_name> test data` and a brief prose description.
   - If the CSV data was exported from a MATLAB Simulink block, add the line **`CSV data exported from the corresponding MATLAB Simulink block.`** (bold, on its own line) after the prose description and before the table.
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
     for i in range(len(sim_dout)):
         await RisingEdge(dut.clk)
         actual = int(dut.dout.value)
         assert actual == sim_dout[i]
     ```

4. **Register in `tests/simulation.toml`**: Add a `[[simulations]]` entry. If the module is parameterized, add one `[[simulations.parameters]]` block per parameter combination.
   - Entries are sorted **alphabetically by directory name, then alphabetically by module name** within each directory. Always insert in the correct sorted position rather than appending to the end.

5. **Documentation**: Create `docs/<Category>/<module_name>.md` summarising the module's function, parameters, and ports. Also add a row to the "Simulation-Verified Modules" table in `README.md`.

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
| `tools/` | Developer utilities outside the simulation flow (not copied into the test image), e.g. `check_simulink_mapping.py` |
| `container/Dockerfile` | Two-stage image: compiles Verilator from source, installs cocotb/pytest |
| `container/docker-compose.local.yml` | Local compose; mounts `tests/results/` for output |

### How a test run works (non-obvious details)

- The Docker image **copies** `rtl/`, `tests/`, `testbench/` → `tests/testbench/`, and `test_data/` → `tests/test_data/` into `/work`. Only `tests/results/` is mounted back to the host, so source changes need an image rebuild (the scripts run `docker compose build` each time). `platform/` is **not** copied into the image, so a `PLATFORM` parameter would fail in the container until the Dockerfile is updated.
- `tests/run_test.sh` runs `prepare_dump.py --dir ../rtl`, which injects a `$dumpfile`/`$dumpvars` block before `endmodule` in **every** RTL file. It edits the copies inside the container, never the host tree.
- `test_runner.py` compiles **all** files under `rtl/` for every test, whatever `top` is. A syntax error or duplicate module name in any file breaks every test.
- cocotb's Verilator build passes no `-Wno-fatal`, so any Verilator warning (e.g. `PINMISSING`, `WIDTHTRUNC`) is fatal. When adding an optional input port to a shared module, give it a default value (`input logic en = 1'b1`) so existing instances can leave it unconnected, as the `BasicModules` `en`/`rst`/`load` ports do. Check with `verilator --lint-only -DSIM --top-module <top> $(find rtl -name "*.v" -o -name "*.sv")`.
- The testbench is imported as `testbench.<dir>.<top>.test_<top>`, so the directory and file names must match `dir`/`top` in `simulation.toml` exactly.
- For parameterized entries, the runner finds the RTL file by filename (`<top>.` substring) and rewrites its `.vcd` filename to `<top>_<i>.vcd` before each build. RTL files must be named `<top>.v`/`<top>.sv`.
- A `PLATFORM = "XILINX"` or `"ALTERA"` key in `[[simulations.parameters]]` adds the vendor models from `lib_path` (the `[xilinx]`/`[altera]` tables at the top of `simulation.toml`) to the sources.
- CI (`.github/workflows/ci.yml`) runs the same container on pushes to `master`/`dev` and PRs to `master`, and uploads `tests/results/` as an artifact.

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
- Parameter names are the casper_library mask variable names in upper case (camelCase → UPPER_SNAKE, e.g. `csp_latency` → `CSP_LATENCY`, `DelayLen` → `DELAY_LEN`).
- A module with a casper_library Simulink block records every difference from that block in an **HDL-Simulink Mapping** section at the end of its header comment: TOML between `// @simulink-mapping begin` and `// @simulink-mapping end` (strip the leading `// `). Fields: `block`, `deviations`, `params` (numeric value → mask option text, verbatim; or, for an edit field, an optional `expr` in Verilog syntax over the module's parameters giving the mask value, e.g. `depth`: `expr = '2**ADDR_WIDTH'`), `hdl_only`, `mask_missing`, `ports` (`renamed` HDL → Simulink, `missing`, `extra`). Validate with `python3 tools/check_simulink_mapping.py`; `--dump` prints every block as JSON (plus `hdl_defaults`, each module's parameter defaults evaluated from the RTL), and `-o FILE` saves the output (JSON or check report) to a file. See `tools/check_simulink_mapping.py` for the schema.

## Module Categories

Categories are organized by function. See the `rtl/` directory for the current set of categories and their contents.
