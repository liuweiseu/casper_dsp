# edge_detect test data

Each subdirectory corresponds to one parameter set. `EDGE`: 0 = rising edge, 1 = falling edge, 2 = both edges. `POLARITY`: 0 = active high, 1 = active low.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: the `sim_*.csv` files of sets 0–5 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | EDGE | POLARITY | Cycles | Description |
|--------|-----------|-----------|------------|--------|-------------|
| 0 | `simdata0` | 0 (rising)  | 0 (active high) | 100 | Detect rising edge, output pulse active high |
| 1 | `simdata1` | 0 (rising)  | 1 (active low)  | 100 | Detect rising edge, output pulse active low |
| 2 | `simdata2` | 1 (falling) | 0 (active high) | 100 | Detect falling edge, output pulse active high |
| 3 | `simdata3` | 1 (falling) | 1 (active low)  | 100 | Detect falling edge, output pulse active low |
| 4 | `simdata4` | 2 (both)    | 0 (active high) | 100 | Detect any edge, output pulse active high |
| 5 | `simdata5` | 2 (both)    | 1 (active low)  | 100 | Detect any edge, output pulse active low |

The testbench also runs `power_on_test` before `module_test`, with no CSV data. Before the first clock edge it drives `din = 1` and checks the combinational `dout` against `din_prev = 0` (the Simulink initial value) for each parameter set.
