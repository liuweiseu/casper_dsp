# CASPER DSP Blocks
[![CASPER DSP HDL CI](https://github.com/liuweiseu/casper_dsp/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/liuweiseu/casper_dsp/actions/workflows/ci.yml)  
This is the respo for the [CASPER](https://casper-astro.github.io) DSP blocks in Verilog/Systemverilog, which contains the RTL modules and testbenches.  
The simulation is based on [Verilator](https://www.veripool.org/verilator/) and [Cocotb](https://www.cocotb.org), which are widely used, open-source tools.

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

**Run a single module or subset:**
```
sudo ./scripts/run-module-test.sh BasicModules/logical   # exact match
sudo ./scripts/run-module-test.sh logical                # substring match
sudo ./scripts/run-module-test.sh BasicModules           # entire category
```
The argument matches against the `<Category>/<module>` test IDs defined in `tests/simulation.toml`.

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

