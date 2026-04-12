# bus_create test data

Each subdirectory corresponds to one parameter set. Input files are named `sim_in1.csv`, `sim_in2.csv`, … (one per input port).

| Directory | NBITS | NINPUTS | Description |
|-----------|-------|---------|-------------|
| `simdata0` | 8  | 2 | Concatenate 2 × 8-bit inputs into a 16-bit output bus |
| `simdata1` | 10 | 4 | Concatenate 4 × 10-bit inputs into a 40-bit output bus |
