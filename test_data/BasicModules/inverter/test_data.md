# inverter test data

Each subdirectory corresponds to one parameter set. `LATENCY=0` produces combinational output; `LATENCY>=1` adds pipeline stages.

| Directory | NBITS | LATENCY | Description |
|-----------|-------|---------|-------------|
| `simdata0` | 4 | 0 | Combinational output — `dout = ~din` with no clock delay |
| `simdata1` | 4 | 1 | Single pipeline stage — output lags input by 1 clock cycle |
| `simdata2` | 4 | 2 | Two pipeline stages — output lags input by 2 clock cycles |
