# inverter test data

Each subdirectory corresponds to one parameter set. `LATENCY=0` produces combinational output; `LATENCY>=1` adds pipeline stages.

| Test # | Directory | NBITS | LATENCY | Cycles | Description |
|--------|-----------|-------|---------|--------|-------------|
| 0 | `simdata0` | 4 | 0 | 8 | Combinational output — `dout = ~din` with no clock delay |
| 1 | `simdata1` | 4 | 1 | 8 | Single pipeline stage — output lags input by 1 clock cycle |
| 2 | `simdata2` | 4 | 2 | 8 | Two pipeline stages — output lags input by 2 clock cycles |
