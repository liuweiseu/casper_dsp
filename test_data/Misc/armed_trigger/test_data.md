# armed_trigger test data

The module has no user-visible parameters, so there is a single test directory.

**CSV data exported from the corresponding MATLAB Simulink block.**

`simdata0/params.json` is empty (no parameters); the testbench selects the data set with `find_data_dir` in `testbench/data_paths.py`, which matches the DUT parameters against each `params.json`.

Simulink data: the `sim_*.csv` files were exported from a Simulink model of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own stimulus) and copied here on 2026-10-14. Regenerating the module with its script replaces them with the reference model's output.

| Test # | Directory | Cycles | Description |
|--------|-----------|--------|-------------|
| 0 | `simdata0` | 16 | Full behavioural sweep: power-on armed state, one-shot fire, disarm, re-arm, rst priority over trig_in |
