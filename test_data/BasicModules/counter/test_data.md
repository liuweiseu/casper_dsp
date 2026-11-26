# counter test data

Each subdirectory corresponds to one parameter set. `COUNTER_TYPE`: 0 = free-running, 1 = count-limit. `COUNT_DIR`: 0 = up, 1 = down, 2 = up/down from the `up` port.

**CSV data exported from the corresponding MATLAB Simulink block.**

Before 2026-10-14 this applied only to `simdata0`–`simdata4`. `simdata5`–`simdata13` are generated from a Python model of the Xilinx Counter (`data/sysgen/block_models/xlCounter.sgm`) by `test_data/scripts/gen_basic_test_data.py`, which writes `params.json` and the stimulus and expected-output CSVs:

- `simdata5`–`simdata9` test the synchronous reset and the enable, with `sim_rst.csv` and `sim_enable.csv` as stimulus. All of them keep `RST_VAL` = `INIT_VAL`: the Xilinx Counter resets to `start_count`, so a separate reset value has no Simulink counterpart.
- `simdata10`–`simdata13` test the up/down direction (`COUNT_DIR = 2`, `sim_up.csv`) and the load port (`ENABLE_LOAD = 1`, `sim_load.csv` and `sim_din.csv`). They also drive `rst` and `enable`.

In `simdata12` a load is attempted while `enable` is low (ignored) and during a reset (the reset wins). In `simdata13` a load arrives while the counter sits at `COUNT_TO_VAL` (the wrap to `INIT_VAL` wins). In `simdata10`–`simdata13`, `simulation.toml` leaves `RST_VAL` at its default, `INIT_VAL`. In sets 0–4 `ENABLE_SYNC_RST` and `ENABLE_ENABLE` are 0, so `RST_VAL` (default `INIT_VAL`) has no effect.

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: the `sim_*.csv` files of sets 0–13 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | NBITS | STEP | INIT_VAL | COUNT_TO_VAL | COUNTER_TYPE | COUNT_DIR | ENABLE_SYNC_RST | ENABLE_ENABLE | RST_VAL | ENABLE_LOAD | Cycles | Description |
|--------|-----------|-------|------|----------|--------------|--------------|-----------|-----------------|---------------|---------|-------------|--------|-------------|
| 0 | `simdata0` | 8 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 299 | Free-running, up, step=1 — basic increment with wrap-around |
| 1 | `simdata1` | 8 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 299 | Free-running, up, step=3 — non-unit step with wrap-around |
| 2 | `simdata2` | 8 | 1 | 255 | 0 | 0 | 1 | 0 | 0 | 255 | 0 | 299 | Free-running, down, step=1 — decrement with wrap-around |
| 3 | `simdata3` | 8 | 1 | 0 | 20 | 1 | 0 | 0 | 0 | 0 | 0 | 299 | Count-limit, up — count to 20 then wrap to INIT_VAL |
| 4 | `simdata4` | 8 | 1 | 20 | 0 | 1 | 1 | 0 | 0 | 20 | 0 | 299 | Count-limit, down — count down to 0 then wrap to INIT_VAL |
| 5 | `simdata5` | 6 | 1 | 9 | 17 | 1 | 0 | 1 | 1 | 9 | 0 | 300 | Count-limit up 9..17: Xilinx start_count on power-on, reset and wrap |
| 6 | `simdata6` | 4 | 1 | 11 | 0 | 0 | 0 | 1 | 1 | 11 | 0 | 300 | Free-running up, power-on and reset value 11 (nonzero) |
| 7 | `simdata7` | 4 | 1 | 12 | 0 | 0 | 1 | 1 | 0 | 12 | 0 | 300 | Free-running down, power-on and reset value 12, no enable |
| 8 | `simdata8` | 5 | 1 | 20 | 0 | 1 | 1 | 1 | 1 | 20 | 0 | 300 | Count-limit down, reset and wrap both go to 20 |
| 9 | `simdata9` | 8 | 3 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 300 | Free-running up step 3, default clear-to-zero reset with enable |
| 10 | `simdata10` | 4 | 1 | 6 | 0 | 0 | 2 | 1 | 1 | 6 | 0 | 300 | Free-running up/down from the `up` port, with reset and enable |
| 11 | `simdata11` | 5 | 2 | 3 | 13 | 1 | 2 | 1 | 1 | 3 | 0 | 300 | Count-limit up/down 3 to 13, step 2 — wraps in both directions |
| 12 | `simdata12` | 6 | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 1 | 300 | Free-running up with load; load gated by enable, reset beats load |
| 13 | `simdata13` | 5 | 1 | 10 | 0 | 1 | 1 | 1 | 0 | 10 | 1 | 300 | Count-limit down 10 to 0 with load, no enable; wrap beats load |
