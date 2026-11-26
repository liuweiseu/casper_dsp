# bit_reverse test data

Each subdirectory corresponds to one parameter set.

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

**CSV data exported from the corresponding MATLAB Simulink block.**

Simulink data: the `sim_*.csv` files of sets 0, 1 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | N_BITS | Cycles | Description |
|--------|-----------|-------|--------|-------------|
| 0 | `simdata0` | 8  | 256 | Reverse bit order of an 8-bit word |
| 1 | `simdata1` | 16 | 300 | Reverse bit order of a 16-bit word |
