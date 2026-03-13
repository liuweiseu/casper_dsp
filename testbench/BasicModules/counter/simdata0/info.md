# simdata0 — Test Parameters

| Parameter     | Value          |
|---------------|----------------|
| COUNTER_TYPE  | free_running   |
| COUNT_DIR     | up             |
| NBITS         | 8              |
| STEP          | 1              |
| INIT_VAL      | 0              |
| COUNT_TO_VAL  | 0              |

## Description

Free-running up counter with unit step. The counter increments by 1 every clock
cycle starting from 0, wrapping around from 255 back to 0 (8-bit overflow).

`sim_out.csv` contains 300 expected `dout` values: 0, 1, 2, …, 255, 0, 1, …, 43.
