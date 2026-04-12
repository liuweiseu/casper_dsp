# register test data

Each subdirectory corresponds to one parameter set. `USE_RST`: 1 = synchronous reset enabled, 0 = disabled. `USE_ENABLE`: 1 = enable pin active, 0 = disabled.

| Directory | BITWIDTH | USE_RST | USE_ENABLE | Description |
|-----------|----------|---------|------------|-------------|
| `simdata0` | 4 | 1 | 1 | Synchronous reset + enable (default behaviour) |
| `simdata1` | 4 | 1 | 0 | Synchronous reset only — always latches `d` when not in reset |
| `simdata2` | 4 | 0 | 1 | Enable only — no reset, holds output when `en=0` |
| `simdata3` | 4 | 0 | 0 | Direct register — always latches `d` every cycle |
