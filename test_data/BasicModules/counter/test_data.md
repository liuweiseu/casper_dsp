# counter test data

Each subdirectory corresponds to one parameter set. `COUNTER_TYPE`: 0 = free-running, 1 = count-limit. `COUNT_DIR`: 0 = up, 1 = down.

**CSV data exported from the corresponding MATLAB Simulink block.**

This applies to `simdata0`–`simdata4`. `simdata5`–`simdata9` test the synchronous reset (`RST_VAL`) and enable. They are generated from a Python model of the Xilinx Counter by `test_data/scripts/gen_basic_test_data.py`, which writes `params.json`, the `sim_rst.csv` and `sim_enable.csv` stimulus, and the expected `sim_dout.csv`. In sets 0–4, `ENABLE_SYNC_RST`, `ENABLE_ENABLE` and `RST_VAL` are 0.

| Test # | Directory | NBITS | STEP | INIT_VAL | COUNT_TO_VAL | COUNTER_TYPE | COUNT_DIR | ENABLE_SYNC_RST | ENABLE_ENABLE | RST_VAL | Cycles | Description |
|--------|-----------|-------|------|----------|--------------|--------------|-----------|-----------------|---------------|---------|--------|-------------|
| 0 | `simdata0` | 8 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 299 | Free-running, up, step=1 — basic increment with wrap-around |
| 1 | `simdata1` | 8 | 3 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 299 | Free-running, up, step=3 — non-unit step with wrap-around |
| 2 | `simdata2` | 8 | 1 | 255 | 0 | 0 | 1 | 0 | 0 | 0 | 299 | Free-running, down, step=1 — decrement with wrap-around |
| 3 | `simdata3` | 8 | 1 | 0 | 20 | 1 | 0 | 0 | 0 | 0 | 299 | Count-limit, up — count to 20 then wrap to INIT_VAL |
| 4 | `simdata4` | 8 | 1 | 20 | 0 | 1 | 1 | 0 | 0 | 0 | 299 | Count-limit, down — count down to 0 then wrap to INIT_VAL |
| 5 | `simdata5` | 6 | 1 | 9 | 17 | 1 | 0 | 1 | 1 | 9 | 300 | Count-limit up 9..17: Xilinx start_count on power-on, reset and wrap |
| 6 | `simdata6` | 4 | 1 | 0 | 0 | 0 | 0 | 1 | 1 | 15 | 300 | Free-running up, reset to 15 (nonzero), power-on 0 |
| 7 | `simdata7` | 4 | 1 | 12 | 0 | 0 | 1 | 1 | 0 | 5 | 300 | Free-running down, reset to 5, no enable |
| 8 | `simdata8` | 5 | 1 | 20 | 0 | 1 | 1 | 1 | 1 | 3 | 300 | Count-limit down, reset value 3 differs from wrap value 20 |
| 9 | `simdata9` | 8 | 3 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 300 | Free-running up step 3, default clear-to-zero reset with enable |
