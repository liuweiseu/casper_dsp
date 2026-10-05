# bus_expand test data

Each subdirectory corresponds to one parameter set. The input file is `sim_bus_in.csv`; `sim_bus_out.csv` has one column per element of the `bus_out` array port (column j = `bus_out[j]`).

**CSV data exported from the corresponding MATLAB Simulink block.**

| Test # | Directory | NOUT | WIDTH | Cycles | Description |
|--------|-----------|------|-------|--------|-------------|
| 0 | `simdata0` | 4 | 8 | 257 | Split a 32-bit input bus into 4 × 8-bit output ports |
