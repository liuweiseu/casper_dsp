# counter test data

Each subdirectory corresponds to one parameter set. `COUNTER_TYPE`: 0 = free-running, 1 = count-limit. `COUNT_DIR`: 0 = up, 1 = down.

**CSV data exported from the corresponding MATLAB Simulink block.**

| Test # | Directory | NBITS | STEP | INIT_VAL | COUNT_TO_VAL | COUNTER_TYPE | COUNT_DIR | Cycles | Description |
|--------|-----------|-------|------|----------|--------------|--------------|-----------|--------|-------------|
| 0 | `simdata0` | 8 | 1 | 0 | 0 | 0 | 0 | 299 | Free-running, up, step=1 — basic increment with wrap-around |
| 1 | `simdata1` | 8 | 3 | 0 | 0 | 0 | 0 | 299 | Free-running, up, step=3 — non-unit step with wrap-around |
| 2 | `simdata2` | 8 | 1 | 255 | 0 | 0 | 1 | 299 | Free-running, down, step=1 — decrement with wrap-around |
| 3 | `simdata3` | 8 | 1 | 0 | 20 | 1 | 0 | 299 | Count-limit, up — count to 20 then hold |
| 4 | `simdata4` | 8 | 1 | 20 | 0 | 1 | 1 | 299 | Count-limit, down — count down to 0 then hold |
