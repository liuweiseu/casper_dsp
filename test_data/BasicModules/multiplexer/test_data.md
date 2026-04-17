# multiplexer test data

Each subdirectory corresponds to one parameter set. Input files are named
`sim_in0.csv`, `sim_in1.csv`, … (one per input port, 0-indexed).
`sim_sel.csv` contains the selection index per cycle.

| Test # | Directory | NBITS | NINPUTS | LATENCY | Cycles | Description |
|--------|-----------|-------|---------|---------|--------|-------------|
| 0 | `simdata0` | 8 | 2 | 1 | 16 | 2-input mux, single pipeline stage |
| 1 | `simdata1` | 8 | 4 | 1 | 16 | 4-input mux, single pipeline stage |
| 2 | `simdata2` | 8 | 2 | 0 | 16 | 2-input mux, combinational output |
| 3 | `simdata3` | 8 | 2 | 2 | 16 | 2-input mux, two pipeline stages |
