# bus_create test data

Each subdirectory corresponds to one parameter set. The `din` array port has one input file per element (`sim_din<j>.csv` = `din[j]`); `sim_bus_out.csv` holds the expected output.

**CSV data exported from the corresponding MATLAB Simulink block.**

| Test # | Directory | NBITS | INPUT_NUM | Cycles | Description |
|--------|-----------|-------|---------|--------|-------------|
| 0 | `simdata0` | 8  | 2 | 513 | Concatenate 2 × 8-bit inputs into a 16-bit output bus |
| 1 | `simdata1` | 10 | 4 | 513 | Concatenate 4 × 10-bit inputs into a 40-bit output bus |
