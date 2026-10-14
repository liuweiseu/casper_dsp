# register test data

Each subdirectory corresponds to one parameter set. `USE_RST`: 1 = synchronous reset enabled, 0 = disabled. `USE_ENABLE`: 1 = enable pin active, 0 = disabled. `INIT_VAL`: value loaded into `q` when reset is asserted.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: the `sim_*.csv` files of sets 0–5 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | BITWIDTH | USE_RST | USE_ENABLE | INIT_VAL | Cycles | Description |
|--------|-----------|----------|---------|------------|----------|--------|-------------|
| 0 | `simdata0` | 4 | 1 | 1 | 0  | 11 | Reset + enable — reset clears to 0 |
| 1 | `simdata1` | 4 | 1 | 0 | 0  |  7 | Reset only — always latches `d` when not in reset, clears to 0 |
| 2 | `simdata2` | 4 | 0 | 1 | 0  |  7 | Enable only — no reset, holds output when `en=0` |
| 3 | `simdata3` | 4 | 0 | 0 | 0  |  7 | Direct register — always latches `d` every cycle |
| 4 | `simdata4` | 4 | 1 | 1 | 7  | 11 | Reset + enable — reset loads 7 (non-zero INIT_VAL) |
| 5 | `simdata5` | 4 | 1 | 0 | 10 |  7 | Reset only — reset loads 10 (non-zero INIT_VAL) |
