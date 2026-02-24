# CASPER DSP Blocks
[![CASPER DSP HDL CI](https://github.com/liuweiseu/casper_dsp/actions/workflows/ci.yml/badge.svg?branch=master)](https://github.com/liuweiseu/casper_dsp/actions/workflows/ci.yml)
This is the respo for the [CASPER](https://casper-astro.github.io) DSP blocks in Verilog(Systemverilog).  
It contains the RTL modules and testbenches, which are based on [Verilator](https://www.veripool.org/verilator/) and [Cocotb](https://www.cocotb.org).

## 🚀 Add new modules
### RTL Modules
The RTL code has to be added under the `rtl` directory. Subdirectories could be created for the new RTL modules.
An example is `rtl/Templates/simple_adder.v`.
### Testbench
The testbench has to be created under the `testbench` directory. There are a few rules for the testbench:
1. The structure of the testbench directory has to be the same as that of the rtl structure.  
    For example, if the rtl module is `rtl/Templates/simple_adder.v`, the testbench has to be in `testbench/Templates/simple_addr`.
2. (Optional) The test script name has to be started with `test_`.
    For example, if the testbench is written for `simple_adder.v`, the testbench script has to be `test_simple_addr.py`.
**Note:** 
(1) As we use `cocotb`, the testbench is written in Python, which is easy and convenient to use.  
(2) If you want to test the new module, please make sure the modue info is added to `tests/simulation.toml`. (See the `Simulation Config` section)

## 📦 Run Simulation
### Requirements
The test is done in a container, so [docker](https://www.docker.com) is the only requirement for running the simulation locally.

### Simulation Config
`tests/simulation.toml` is used for the simulation configuration, setting which modules will be tested automatically.  
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
Once docker is installed, simulation can be done automatically by running
```
sudo ./scripts/run-local-test.sh
```
**Note:** It may take a while when you run the script first time.
If the simulation runs successfully, you should See
```
test-runner-1  | test_runner.py::test_runner[Templates/simple_adder] PASSED               [ 25%]
test-runner-1  | test_runner.py::test_runner[BasicModules/slice] PASSED                   [ 50%]
test-runner-1  | test_runner.py::test_runner[FlowControl/bus_create] PASSED               [ 75%]
test-runner-1  | test_runner.py::test_runner[FlowControl/bus_expand] PASSED               [100%]
...
--- CASPER DSP CI Run Completed Successfully ---
```
The **test results** should be under `tests/results`.  
A `vcd` file is generated for each tested module, and the test results can be checked by openning the vcd file on the online vcdviewer like [this](https://app.surfer-project.org).

### Remote simulation
The CI test for simulation will also be running automatically every time, when pushing the code to Github.  
The test results are also accessable through [Github Artifacts](https://docs.github.com/en/enterprise-cloud@latest/actions/tutorials/store-and-share-data).  
Here is an [example](https://github.com/liuweiseu/casper_dsp/actions/runs/22171786766) about the auto generated test resutls after the CI test runs successfully.

