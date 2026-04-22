# CASPER DSP Blocks
[![CASPER DSP HDL CI](https://github.com/liuweiseu/casper_dsp/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/liuweiseu/casper_dsp/actions/workflows/ci.yml)  
This is the respo for the [CASPER](https://casper-astro.github.io) DSP blocks in Verilog/Systemverilog, which contains the RTL modules and testbenches.  
The simulation is based on [Verilator](https://www.veripool.org/verilator/) and [Cocotb](https://www.cocotb.org), which are widely used, open-source tools.

## ✅ Simulation-Verified Modules

| # | Category | Module | Description |
|---|----------|--------|-------------|
| 1 | BasicModules | [`constant`](docs/BasicModules/constant.md) | Fixed compile-time constant output |
| 2 | BasicModules | [`counter`](docs/BasicModules/counter.md) | Configurable up/down counter with free-running and count-limit modes |
| 3 | BasicModules | [`delay`](docs/BasicModules/delay.md) | Shift-register pipeline delay |
| 4 | BasicModules | [`inverter`](docs/BasicModules/inverter.md) | Bitwise inverter with optional pipeline delay |
| 5 | BasicModules | [`logical`](docs/BasicModules/logical.md) | Bitwise logical reduction (AND/OR/XOR/etc.) with optional pipeline delay |
| 6 | BasicModules | [`multiplexer`](docs/BasicModules/multiplexer.md) | N-input multiplexer with optional pipeline delay |
| 7 | BasicModules | [`register`](docs/BasicModules/register.md) | Parameterized synchronous register with optional reset and enable |
| 8 | BasicModules | [`relational`](docs/BasicModules/relational.md) | Unsigned comparator (==, !=, <, >, <=, >=) with optional pipeline delay |
| 9 | BasicModules | [`slice`](docs/BasicModules/slice.md) | Combinational bit-field extractor |
| 10 | FlowControl | [`bus_create`](docs/FlowControl/bus_create.md) | Pack multiple equal-width words into a single concatenated bus |
| 11 | FlowControl | [`bus_expand`](docs/FlowControl/bus_expand.md) | Split a wide bus into an array of equal-width words |
| 12 | Misc | [`armed_trigger`](docs/Misc/armed_trigger.md) | One-shot trigger with explicit arm step |
| 13 | Misc | [`bit_reverse`](docs/Misc/bit_reverse.md) | Combinational bit-order reversal |
| 14 | Misc | [`edge_detect`](docs/Misc/edge_detect.md) | Rising/falling/both-edge detector with configurable output polarity |
| 15 | Misc | [`pulse_ext`](docs/Misc/pulse_ext.md) | Rising-edge triggered pulse extender |

## 🚀 Add new modules

The repository uses four parallel directory trees, all mirroring `rtl/` structure:

| Directory | Purpose |
|-----------|---------|
| `rtl/` | RTL source files |
| `testbench/` | Cocotb testbench scripts |
| `test_data/` | CSV simulation input/output data |
| `docs/` | Per-module documentation |

### Steps

1. **RTL** — add the Verilog/SystemVerilog file under `rtl/<Category>/`.  
   Example: [rtl/Templates/simple_adder.v](rtl/Templates/simple_adder.v)

2. **Test data** — create `test_data/<Category>/<module>/` and place CSV files there (e.g. `sim_in.csv`, `sim_out.csv`). For multiple parameter sets use subdirectories `simdata0/`, `simdata1/`, …

3. **Testbench** — create `testbench/<Category>/<module>/test_<module>.py`.  
   Derive the data path dynamically from `__file__` so no path is hardcoded:
   ```python
   _here = Path(__file__).parent
   testdatadir = (_here / "../../../test_data" / _here.parent.name / _here.name).resolve()
   ```
   Example: [testbench/Templates/simple_adder/test_simple_adder.py](testbench/Templates/simple_adder/test_simple_adder.py)

4. **Simulation config** — add a `[[simulations]]` entry to `tests/simulation.toml`. (See the `Simulation Config` section below.)

5. **Documentation** — create `docs/<Category>/<module>.md` describing the module's function, parameters, and ports.

## 📦 Run Simulation
### Requirements
The test is done in a container, so [docker](https://www.docker.com) is the only requirement for running the simulation locally.

### Simulation Config
[tests/simulation.toml](tests/simulation.toml) is used for the simulation configuration, setting which modules will be tested automatically.  
  
Here is an example about testing `bus_create` module with different sets of parameters:  
```[toml]
# test bus_create
[[simulations]]
dir = "FlowControl"
top = "bus_create"
[[simulations.parameters]]
NBITS = 8
NINPUTS = 2
[[simulations.parameters]]
NBITS = 10
NINPUTS = 4
```
### Local simulation

**Run all tests:**
```
sudo ./scripts/run-local-test.sh
```
**Note:** It may take a while when you run the script first time.

**Run a single module or an entire category:**

Besides running all tests at once, you can also simulate a single module or an entire category independently. The argument is matched against the `<Category>/<module>` test IDs defined in `tests/simulation.toml`:

```
sudo ./scripts/run-module-test.sh BasicModules/logical   # single module (exact match)
sudo ./scripts/run-module-test.sh logical                # any module whose ID contains "logical"
sudo ./scripts/run-module-test.sh BasicModules           # entire category
```

If the simulation runs successfully, you should see
```
test-runner-1  | test_runner.py::test_runner[Templates/simple_adder] PASSED               [ 25%]
test-runner-1  | test_runner.py::test_runner[BasicModules/slice] PASSED                   [ 50%]
test-runner-1  | test_runner.py::test_runner[FlowControl/bus_create] PASSED               [ 75%]
test-runner-1  | test_runner.py::test_runner[FlowControl/bus_expand] PASSED               [100%]
...
--- CASPER DSP CI Run Completed Successfully ---
```
The **test results** should be under `tests/results` on your local machine.  
A `vcd` file is generated for each tested module, and the test results can be checked by a online vcd viewer like [this](https://app.surfer-project.org).

### Remote simulation
The CI test for simulation will also be running automatically every time, when pushing the code to Github.  
The test results are also accessable through [Github Artifacts](https://docs.github.com/en/enterprise-cloud@latest/actions/tutorials/store-and-share-data).  
Here is an [example](https://github.com/liuweiseu/casper_dsp/actions/runs/22171786766) about the auto generated test resutls after the CI test runs successfully.

