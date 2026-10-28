# Simulink-exported test data

Which `test_data/` sets hold CSV data exported from MATLAB Simulink, and which keep the data of the Python reference models in `test_data/scripts/` (and `rtl/.../scripts/`).

## Source

- The Simulink data comes from the plugins-demo2 export flow: for each set of `tests/simulation.toml` it builds a Simulink model of the casper_library / Xilinx block (MATLAB R2021a, System Generator) with the parameters mapped by the module's HDL-Simulink mapping, simulates it with its own random stimulus and extracts every port to `sim_<port>.csv`. The plugins-demo2 regression ran the casper_dsp HDL against all of these sets (all non-excluded sets bit-exact).
- Copied on 2026-10-14 from `/data/casper/tools/plugins-demo2/test_data` (main sets), `test_data_async/batch1` and `test_data_async/batch2` (`ASYNC` / `DVALID_EN` sets). Only the `sim_*.csv` files of a set are replaced; `params.json` and memory files (`*.mem`) stay the generator's, except for the async sets added from Simulink, which are copied whole.
- `BasicModules/fifo` (added 2026-10-27) was exported in this repository's session, not by plugins-demo2: Simulink models of the Xilinx FIFO block driven by deterministic stimulus (Repeating Sequence Stair sources: fill past full, drain past empty, random traffic, `en` gaps and `rst` pulses), built and simulated with the matlab-tools scripts on the SNAP or RFSoC4x2 platform; every set is whole Simulink data (inputs and outputs). See its `test_data.md`.
- `FlowControl/munge` (added 2026-10-28) was exported the same way: random `din` words built from up to 16-bit Gateway Ins (Concat) and `dout` read through 16-bit Slices, on the SNAP platform; every set is whole Simulink data.
- Sets that a documented mlib_devel bug excludes (`docs/bugs.md`, the sets `filter_bug_sets` removes) keep the generated data: their Simulink output shows the bug, while the HDL and the reference models implement the intended behaviour.
- Each module's `test_data.md` says which of its sets are Simulink data (the bold line **CSV data exported from the corresponding MATLAB Simulink block.** and a "Simulink data:" note, or a "Sets exported from MATLAB Simulink" section for the async sets that only exist as Simulink data).
- Regenerating a module with its generator script (`[test_data] generate = true`, or running the script) overwrites its Simulink CSVs with the reference model's output. The "Sets exported from MATLAB Simulink" sections and their `simdata` directories are not written by the generators and are kept.

## Summary

366 of 424 sets (75 modules) are Simulink data.

## Per module

| Category | Module | Sets | Simulink-exported sets | Generated sets (reason) |
|---|---|---|---|---|
| BasicModules | `BasicModules/constant` | 5 | — | 0–4: testbench derives the expected output from the parameters (no CSV files); simulated in Simulink but not extracted |
| BasicModules | `BasicModules/counter` | 14 | all | — |
| BasicModules | `BasicModules/delay` | 5 | all | — |
| BasicModules | `BasicModules/fifo` | 12 | all | — |
| BasicModules | `BasicModules/inverter` | 4 | all | — |
| BasicModules | `BasicModules/logical` | 9 | all | — |
| BasicModules | `BasicModules/multiplexer` | 5 | all | — |
| BasicModules | `BasicModules/register` | 6 | all | — |
| BasicModules | `BasicModules/relational` | 18 | all | — |
| BasicModules | `BasicModules/slice` | 1 | all | — |
| Bus | `Bus/adder_subtractor` | 9 | 0–3, 5–8 | 4: no Simulink equivalent (mapping `unsupported`) |
| Bus | `Bus/convert` | 9 | 0–3, 5–8 | 4: no Simulink equivalent (mapping `unsupported`) |
| Bus | `Bus/multiplier` | 6 | 0, 2–5 | 1: mlib_devel bug 8 |
| Bus | `Bus/negate` | 5 | all | — |
| Bus | `Bus/scale` | 6 | all | — |
| Correlator | `Correlator/auto_tap` | 4 | 0, 2 | 1: mlib_devel bug 12; 3: mlib_devel bug 7 |
| Correlator | `Correlator/baseline_tap` | 4 | 0, 1, 3 | 2: mlib_devel bug 12 |
| Correlator | `Correlator/cmac` | 5 | all | — |
| Correlator | `Correlator/cross_multiplier` | 4 | all | — |
| Correlator | `Correlator/dual_pol_cmac` | 3 | all | — |
| Correlator | `Correlator/xeng` | 7 | 0, 2–6 | 1: mlib_devel bug 12 |
| Correlator | `Correlator/xeng_descramble` | 6 | 0, 1, 3, 5 | 2: no Simulink equivalent (mapping `unsupported`); 4: Simulink output has a NaN (RAM read/write collision, System Generator undefined value) in this set |
| Correlator | `Correlator/xeng_descramble_4ant` | 3 | all | — |
| Correlator | `Correlator/xeng_tvg` | 4 | all | — |
| Correlator | `Correlator/Internal/cmac_acc` | 3 | — | 0–2: internal subsystem of cmac, not a library block (no Simulink export) |
| Correlator | `Correlator/Internal/read_ctrl` | 4 | — | 0–3: internal subsystem of xeng_descramble, not a library block (no Simulink export) |
| Correlator | `Correlator/Internal/write_ctrl` | 4 | — | 0–3: internal subsystem of xeng_descramble, not a library block (no Simulink export) |
| Correlator | `Correlator/Internal/x_cast` | 4 | — | 0–3: internal subsystem of xeng_descramble, not a library block (no Simulink export) |
| Delays | `Delays/delay_bram` | 9 | 1–4, 7, 8 | 0, 5, 6: mlib_devel bug 7 |
| Delays | `Delays/delay_srl` | 6 | all | — |
| Delays | `Delays/dual_port_ram` | 5 | all | — |
| Delays | `Delays/pipeline` | 5 | all | — |
| Delays | `Delays/rom` | 5 | all | — |
| Delays | `Delays/single_port_ram` | 6 | all | — |
| Delays | `Delays/sync_delay` | 5 | all | — |
| Delays | `Delays/window_delay` | 5 | all | — |
| FFTs | `FFTs/biplex_core` | 6 | 0, 2, 4, 5 | 1, 3: mlib_devel bug 18 |
| FFTs | `FFTs/butterfly_direct` | 11 | 0–5, 7–10 | 6: mlib_devel bug 15, 20 |
| FFTs | `FFTs/fft_biplex_real_4x` | 6 | all | — |
| FFTs | `FFTs/fft_direct` | 8 | 3, 6, 7 | 0–2, 4, 5: mlib_devel bug 15 |
| FFTs | `FFTs/fft_stage_n` | 9 | all | — |
| FFTs | `FFTs/fft_unscrambler` | 7 | all | — |
| FFTs | `FFTs/fft_wideband_real` | 7 | 3, 5, 6 | 0, 1, 4: mlib_devel bug 15; 2: mlib_devel bug 4 |
| FFTs | `FFTs/Internal/bi_real_unscr_4x` | 8 | all | — |
| FFTs | `FFTs/Internal/complex_conj` | 4 | all | — |
| FFTs | `FFTs/Internal/hilbert` | 5 | all | — |
| FFTs | `FFTs/Internal/mirror_spectrum` | 6 | all | — |
| FFTs | `FFTs/Twiddle/twiddle_coeff_0` | 4 | all | — |
| FFTs | `FFTs/Twiddle/twiddle_general` | 8 | 2, 4, 6, 7 | 0, 5: mlib_devel bug 15, 20; 1: mlib_devel bug 6, 20; 3: no Simulink equivalent (mapping `unsupported`) |
| FFTs | `FFTs/Twiddle/twiddle_pass_through` | 3 | all | — |
| FFTs | `FFTs/Twiddle/twiddle_stage_2` | 6 | 0, 1, 3–5 | 2: no Simulink equivalent (mapping `unsupported`) |
| FlowControl | `FlowControl/bus_create` | 2 | all | — |
| FlowControl | `FlowControl/bus_expand` | 1 | all | — |
| FlowControl | `FlowControl/munge` | 8 | all | — |
| Misc | `Misc/adder_tree` | 8 | all | — |
| Misc | `Misc/armed_trigger` | 1 | all | — |
| Misc | `Misc/bit_reverse` | 2 | all | — |
| Misc | `Misc/c_to_ri` | 2 | all | — |
| Misc | `Misc/convert_of` | 5 | all | — |
| Misc | `Misc/edge_detect` | 6 | all | — |
| Misc | `Misc/negedge_delay` | 4 | all | — |
| Misc | `Misc/pulse_ext` | 3 | all | — |
| Misc | `Misc/ri_to_c` | 2 | all | — |
| Misc | `Misc/sample_and_hold` | 4 | all | — |
| Multipliers | `Multipliers/cmult` | 12 | 0–9, 11 | 10: mlib_devel bug 13 |
| Multipliers | `Multipliers/complex_multiplier` | 8 | 0, 1, 7 | 2–6: QUANTIZATION 1 / 2 have no Simulink equivalent (Complex Multiplier 6.0 offers Truncate and Random Rounding only) |
| PFBs | `PFBs/first_tap_real` | 3 | all | — |
| PFBs | `PFBs/last_tap_real` | 3 | all | — |
| PFBs | `PFBs/pfb_coeff_gen` | 6 | all | — |
| PFBs | `PFBs/pfb_fir_real` | 5 | 0–3 | 4: mlib_devel bug 19 |
| PFBs | `PFBs/tap_real` | 4 | 0–2 | 3: mlib_devel bug 7 |
| Reorder | `Reorder/barrel_switcher` | 4 | all | — |
| Reorder | `Reorder/reorder` | 12 | all | — |
| Reorder | `Reorder/square_transposer` | 5 | all | — |
| Templates | `Templates/simple_adder` | 1 | — | all: template, no casper_library block |
