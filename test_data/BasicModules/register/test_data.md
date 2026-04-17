# register test data

Each subdirectory corresponds to one parameter set. `USE_RST`: 1 = synchronous reset enabled, 0 = disabled. `USE_ENABLE`: 1 = enable pin active, 0 = disabled. `INIT_VAL`: value loaded into `q` when reset is asserted.

| Directory | BITWIDTH | USE_RST | USE_ENABLE | INIT_VAL | Cycles | Description |
|-----------|----------|---------|------------|----------|--------|-------------|
| `simdata0` | 4 | 1 | 1 | 0  | 11 | Reset + enable — reset clears to 0 |
| `simdata1` | 4 | 1 | 0 | 0  |  7 | Reset only — always latches `d` when not in reset, clears to 0 |
| `simdata2` | 4 | 0 | 1 | 0  |  7 | Enable only — no reset, holds output when `en=0` |
| `simdata3` | 4 | 0 | 0 | 0  |  7 | Direct register — always latches `d` every cycle |
| `simdata4` | 4 | 1 | 1 | 7  | 11 | Reset + enable — reset loads 7 (non-zero INIT_VAL) |
| `simdata5` | 4 | 1 | 0 | 10 |  7 | Reset only — reset loads 10 (non-zero INIT_VAL) |
