# inverter test data

Each subdirectory corresponds to one parameter set. `LATENCY=0` produces combinational output; `LATENCY>=1` adds pipeline stages.

`simdata3` tests the enable (`USE_ENABLE = 1`, `en` from `sim_en.csv`). It is generated from a Python model of the Xilinx System Generator block (`data/sysgen/block_models/xl*.sgm`) by `test_data/scripts/gen_basic_test_data.py`, which also writes a `params.json` for each set (the testbench matches the DUT parameters against it).

| Test # | Directory | NBITS | LATENCY | USE_ENABLE | Cycles | Description |
|--------|-----------|-------|---------|------------|--------|-------------|
| 0 | `simdata0` | 4 | 0 | 0 | 8 | Combinational output — `dout = ~din` with no clock delay |
| 1 | `simdata1` | 4 | 1 | 0 | 8 | Single pipeline stage — output lags input by 1 clock cycle |
| 2 | `simdata2` | 4 | 2 | 0 | 8 | Two pipeline stages — output lags input by 2 clock cycles |
| 3 | `simdata3` | 4 | 2 | 1 | 200 | Two pipeline stages held while `en` is low |
