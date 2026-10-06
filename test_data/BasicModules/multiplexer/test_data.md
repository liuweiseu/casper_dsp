# multiplexer test data

Each subdirectory corresponds to one parameter set. The `din` array port has
one input file per element (`sim_din<j>.csv` = `din[j]`).
`sim_sel.csv` contains the selection index per cycle.

**CSV data exported from the corresponding MATLAB Simulink block.**

This applies to `simdata0`–`simdata3` (`USE_ENABLE` = 0). `simdata4` tests the enable (`en` from `sim_en.csv`). It is generated from a Python model of the Xilinx System Generator block (`data/sysgen/block_models/xl*.sgm`) by `test_data/scripts/gen_basic_test_data.py`, which also writes a `params.json` for each set (the testbench matches the DUT parameters against it).

| Test # | Directory | NBITS | NINPUTS | LATENCY | USE_ENABLE | Cycles | Description |
|--------|-----------|-------|---------|---------|------------|--------|-------------|
| 0 | `simdata0` | 8 | 2 | 1 | 0 | 16 | 2-input mux, single pipeline stage |
| 1 | `simdata1` | 8 | 4 | 1 | 0 | 16 | 4-input mux, single pipeline stage |
| 2 | `simdata2` | 8 | 2 | 0 | 0 | 16 | 2-input mux, combinational output |
| 3 | `simdata3` | 8 | 2 | 2 | 0 | 16 | 2-input mux, two pipeline stages |
| 4 | `simdata4` | 8 | 4 | 2 | 1 | 200 | 4-input mux, two pipeline stages held while `en` is low |
