# multiplexer test data

Each subdirectory corresponds to one parameter set. The `din` array port has
one input file per element (`sim_din<j>.csv` = `din[j]`).
`sim_sel.csv` contains the selection index per cycle.

**CSV data exported from the corresponding MATLAB Simulink block.**

Before 2026-10-14 this applied only to `simdata0`–`simdata3` (`USE_ENABLE` = 0). `simdata4` tests the enable (`en` from `sim_en.csv`). It is generated from a Python model of the Xilinx System Generator block (`data/sysgen/block_models/xl*.sgm`) by `test_data/scripts/gen_basic_test_data.py`, which also writes a `params.json` for each set (the testbench matches the DUT parameters against it).

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: the `sim_*.csv` files of sets 0–4 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | NBITS | NINPUTS | LATENCY | USE_ENABLE | Cycles | Description |
|--------|-----------|-------|---------|---------|------------|--------|-------------|
| 0 | `simdata0` | 8 | 2 | 1 | 0 | 16 | 2-input mux, single pipeline stage |
| 1 | `simdata1` | 8 | 4 | 1 | 0 | 16 | 4-input mux, single pipeline stage |
| 2 | `simdata2` | 8 | 2 | 0 | 0 | 16 | 2-input mux, combinational output |
| 3 | `simdata3` | 8 | 2 | 2 | 0 | 16 | 2-input mux, two pipeline stages |
| 4 | `simdata4` | 8 | 4 | 2 | 1 | 200 | 4-input mux, two pipeline stages held while `en` is low |
