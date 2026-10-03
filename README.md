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
| 10 | Bus | [`adder_subtractor`](docs/Bus/adder_subtractor.md) | Fixed-point add/subtract with independent input formats and output requantization |
| 11 | Bus | [`convert`](docs/Bus/convert.md) | Fixed-point format converter (quantization: truncate/round; overflow: wrap/saturate) |
| 12 | Bus | [`multiplier`](docs/Bus/multiplier.md) | Fixed-point real multiply with output requantization |
| 13 | Bus | [`negate`](docs/Bus/negate.md) | Two's-complement negate with output requantization |
| 14 | Bus | [`scale`](docs/Bus/scale.md) | Multiply by a power of two with output requantization |
| 15 | Correlator | [`cmac`](docs/Correlator/cmac.md) | Complex multiply-accumulate a·conj(b) over acc_len samples with an acc_in relay |
| 16 | Correlator | [`dual_pol_cmac`](docs/Correlator/dual_pol_cmac.md) | Four cmacs for the XX, YY, XY, YX products of two dual-polarisation inputs |
| 17 | Correlator/Internal | [`cmac_acc`](docs/Correlator/Internal/cmac_acc.md) | cmac's accumulate-and-relay cell (Accumulator with reinit-on-reset, 2-cycle muxes) |
| 18 | Delays | [`delay_bram`](docs/Delays/delay_bram.md) | RAM-based long delay line (vendor RAM via single_port_ram) |
| 19 | Delays | [`delay_srl`](docs/Delays/delay_srl.md) | Shift-register delay with optional synchronous reset and enable |
| 20 | Delays | [`dual_port_ram`](docs/Delays/dual_port_ram.md) | True dual-port RAM, common clock; GENERIC / XILINX (XPM) / ALTERA (stub) |
| 21 | Delays | [`pipeline`](docs/Delays/pipeline.md) | Register pipeline with configurable latency |
| 22 | Delays | [`rom`](docs/Delays/rom.md) | Synchronous ROM loaded from an init file; GENERIC / XILINX (XPM) / ALTERA (stub) |
| 23 | Delays | [`single_port_ram`](docs/Delays/single_port_ram.md) | Single-port RAM; GENERIC / XILINX (XPM) / ALTERA (stub) |
| 24 | Delays | [`sync_delay`](docs/Delays/sync_delay.md) | Sync-pulse delay with a loadable down counter |
| 25 | Delays | [`window_delay`](docs/Delays/window_delay.md) | Window (level) delay through two edge sync_delays |
| 26 | FFTs | [`biplex_core`](docs/FFTs/biplex_core.md) | Streaming biplex FFT core: chain of FFT_SIZE fft_stage_n |
| 27 | FFTs | [`butterfly_direct`](docs/FFTs/butterfly_direct.md) | Radix-2 butterfly (a ± b·w) with twiddle-variant selection, shift and overflow flag |
| 28 | FFTs | [`fft_biplex_real_4x`](docs/FFTs/fft_biplex_real_4x.md) | Biplex FFT of 4·N real signals: biplex_core + bi_real_unscr_4x |
| 29 | FFTs | [`fft_direct`](docs/FFTs/fft_direct.md) | Fully parallel radix-2 FFT stages (optionally the tail of a larger FFT) |
| 30 | FFTs | [`fft_stage_n`](docs/FFTs/fft_stage_n.md) | One biplex FFT stage: commutator delays/muxes + butterfly_direct |
| 31 | FFTs | [`fft_unscrambler`](docs/FFTs/fft_unscrambler.md) | square_transposer + reorder that restores natural order after fft_direct |
| 32 | FFTs | [`fft_wideband_real`](docs/FFTs/fft_wideband_real.md) | Wideband real FFT: fft_biplex_real_4x + fft_direct + fft_unscrambler |
| 33 | FFTs/Internal | [`bi_real_unscr_4x`](docs/FFTs/Internal/bi_real_unscr_4x.md) | Unscramble a biplex FFT of four real signals into their full spectra |
| 34 | FFTs/Internal | [`complex_conj`](docs/FFTs/Internal/complex_conj.md) | Complex conjugate: delayed real part, negated imaginary part |
| 35 | FFTs/Internal | [`hilbert`](docs/FFTs/Internal/hilbert.md) | Split the FFT of two real signals packed as one complex signal |
| 36 | FFTs/Internal | [`mirror_spectrum`](docs/FFTs/Internal/mirror_spectrum.md) | Complete the upper half of four real-signal spectra by conjugate mirroring |
| 37 | FFTs/Twiddle | [`twiddle_coeff_0`](docs/FFTs/Twiddle/twiddle_coeff_0.md) | Twiddle for coefficient 0 (w = 1) with delay matching |
| 38 | FFTs/Twiddle | [`twiddle_coeff_1`](docs/FFTs/Twiddle/twiddle_coeff_1.md) | Twiddle for coefficient 1 (w = −j): swap re/im and negate |
| 39 | FFTs/Twiddle | [`twiddle_general`](docs/FFTs/Twiddle/twiddle_general.md) | General twiddle: bi × coefficient table (ROM, sync-reset schedule) |
| 40 | FFTs/Twiddle | [`twiddle_pass_through`](docs/FFTs/Twiddle/twiddle_pass_through.md) | Twiddle pass-through (w = 1, zero latency) |
| 41 | FFTs/Twiddle | [`twiddle_stage_2`](docs/FFTs/Twiddle/twiddle_stage_2.md) | Twiddle alternating w = 1 / −j for the second FFT stage |
| 42 | FlowControl | [`bus_create`](docs/FlowControl/bus_create.md) | Pack multiple equal-width words into a single concatenated bus |
| 43 | FlowControl | [`bus_expand`](docs/FlowControl/bus_expand.md) | Split a wide bus into an array of equal-width words |
| 44 | Misc | [`adder_tree`](docs/Misc/adder_tree.md) | Pipelined pairwise adder tree (full or user-defined precision) |
| 45 | Misc | [`armed_trigger`](docs/Misc/armed_trigger.md) | One-shot trigger with explicit arm step |
| 46 | Misc | [`bit_reverse`](docs/Misc/bit_reverse.md) | Combinational bit-order reversal |
| 47 | Misc | [`convert_of`](docs/Misc/convert_of.md) | Fixed-point convert with casper overflow flag |
| 48 | Misc | [`edge_detect`](docs/Misc/edge_detect.md) | Rising/falling/both-edge detector with configurable output polarity |
| 49 | Misc | [`negedge_delay`](docs/Misc/negedge_delay.md) | Falling-edge stretcher (level held PULSE_LEN cycles after it drops) |
| 50 | Misc | [`pulse_ext`](docs/Misc/pulse_ext.md) | Rising-edge triggered pulse extender |
| 51 | Misc | [`sample_and_hold`](docs/Misc/sample_and_hold.md) | Register resampled one cycle after sync or every PERIOD cycles |
| 52 | Multipliers | [`cmult`](docs/Multipliers/cmult.md) | casper_library cmult: packed complex multiply, optional conjugate of b, output convert |
| 53 | Multipliers | [`complex_multiplier`](docs/Multipliers/complex_multiplier.md) | Fixed-point complex multiply, selectable 4-multiply or 3-multiply form |
| 54 | PFBs | [`first_tap_real`](docs/PFBs/first_tap_real.md) | First PFB FIR tap: product with the lowest coefficient slice, data / sync delayed one frame |
| 55 | PFBs | [`last_tap_real`](docs/PFBs/last_tap_real.md) | Last PFB FIR tap: product and sync for the adder tree |
| 56 | PFBs | [`pfb_coeff_gen`](docs/PFBs/pfb_coeff_gen.md) | PFB FIR coefficients: one windowed-sinc ROM per tap, sync-reset address counter |
| 57 | PFBs | [`pfb_fir_real`](docs/PFBs/pfb_fir_real.md) | Real-input polyphase filter bank FIR: coefficient ROMs, tap chains, adder trees |
| 58 | PFBs | [`tap_real`](docs/PFBs/tap_real.md) | Middle PFB FIR tap: product, coefficient bus forwarded, data / sync delayed |
| 59 | Reorder | [`barrel_switcher`](docs/Reorder/barrel_switcher.md) | Pipelined lane rotation by a select input |
| 60 | Reorder | [`reorder`](docs/Reorder/reorder.md) | Fixed-map frame permutation (corner turn), all map orders |
| 61 | Reorder | [`square_transposer`](docs/Reorder/square_transposer.md) | N × N block transpose with lane delays and a barrel switcher |

## 🚀 Add new modules

The repository uses four parallel directory trees, all mirroring `rtl/` structure:

| Directory | Purpose |
|-----------|---------|
| `rtl/` | RTL source files |
| `testbench/` | Cocotb testbench scripts |
| `test_data/` | CSV simulation input/output data |
| `docs/` | Per-module documentation |

Two kinds of Python scripts live next to the files they belong to:

| Location | Purpose |
|----------|---------|
| `rtl/<Category>/.../scripts/` | Generators a module **needs to be used**, e.g. [rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py](rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py) writes the coefficient table (`.mem`) that `twiddle_general` loads through `INIT_FILE` |
| `test_data/scripts/` | Test data generators: reference models that write `test_data/<Category>/<module>/` (inputs, expected outputs, `params.json`, `test_data.md`). Each accepts `--module <name>` / `--list` and prints the module's `simulation.toml` entry |

### Steps

1. **RTL** — add the Verilog/SystemVerilog file under `rtl/<Category>/`.  
   Example: [rtl/Templates/simple_adder.v](rtl/Templates/simple_adder.v)

2. **Test data** — create `test_data/<Category>/<module>/` and place CSV files there (e.g. `sim_in.csv`, `sim_out.csv`). For multiple parameter sets use subdirectories `simdata0/`, `simdata1/`, …
   The data can be imported (e.g. exported from MATLAB) or produced by a generator script in `test_data/scripts/` (see *Test data generation* below).

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

### Test data generation
The `[test_data]` table in `tests/simulation.toml` decides whether the tests run on `test_data/` as it is, or regenerate it first with the scripts in `test_data/scripts/`:
```[toml]
[test_data]
generate = false        # true: regenerate before testing

[[simulations]]
dir = "Bus"
top = "convert"
test_data_script = "gen_fixed_point_test_data.py"   # generator of this module's data
# generate_test_data = false                        # per-module override of [test_data] generate
```
- `generate = false` (default): every module uses its committed / imported test data.
- `generate = true`: before a module's tests, `tests/test_runner.py` runs `test_data/scripts/<test_data_script> --module <top>`, so only that module's data is rewritten. Entries without `test_data_script` (e.g. MATLAB-exported data) are never regenerated.
- `generate_test_data` on a `[[simulations]]` entry overrides the global switch for that module, e.g. to keep your own imported data while the rest is regenerated.
- Generation writes into the test container's copy of `test_data/`; the repository's `test_data/` is not modified. To update the repository, run the script directly, e.g. `python3 test_data/scripts/gen_fixed_point_test_data.py --module convert`.

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

