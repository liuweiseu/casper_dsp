# armed_trigger test data

The module has no user-visible parameters, so there is a single test directory.

**CSV data exported from the corresponding MATLAB Simulink block.**

`simdata0/params.json` is empty (no parameters); the testbench selects the data set with `find_data_dir` in `testbench/data_paths.py`, which matches the DUT parameters against each `params.json`.

| Test # | Directory | Cycles | Description |
|--------|-----------|--------|-------------|
| 0 | `simdata0` | 16 | Full behavioural sweep: power-on armed state, one-shot fire, disarm, re-arm, rst priority over trig_in |
