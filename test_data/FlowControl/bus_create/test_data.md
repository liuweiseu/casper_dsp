# bus_create test data

Each subdirectory corresponds to one parameter set. The `din` array port has one input file per element (`sim_din<j>.csv` = `din[j]`); `sim_bus_out.csv` holds the expected output.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: the `sim_*.csv` files of sets 0, 1 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | NBITS | INPUT_NUM | Cycles | Description |
|--------|-----------|-------|---------|--------|-------------|
| 0 | `simdata0` | 8  | 2 | 513 | Concatenate 2 × 8-bit inputs into a 16-bit output bus |
| 1 | `simdata1` | 10 | 4 | 513 | Concatenate 4 × 10-bit inputs into a 40-bit output bus |
