# bus_expand test data

Each subdirectory corresponds to one parameter set. The input file is `sim_bus_in.csv`; the `bus_out` array port has one expected-output file per element (`sim_bus_out<j>.csv` = `bus_out[j]`).

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

| Test # | Directory | OUTPUT_NUM | OUTPUT_WIDTH | Cycles | Description |
|--------|-----------|------|-------|--------|-------------|
| 0 | `simdata0` | 4 | 8 | 257 | Split a 32-bit input bus into 4 × 8-bit output ports |
