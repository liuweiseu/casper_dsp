# simdata1 — Test Parameters

| Parameter     | Value          |
|---------------|----------------|
| COUNTER_TYPE  | free_running   |
| COUNT_DIR     | up             |
| NBITS         | 8              |
| STEP          | 3              |
| INIT_VAL      | 0              |
| COUNT_TO_VAL  | 0              |

## Description

Free-running up counter with step size 3. The counter increments by 3 every clock
cycle starting from 0, wrapping around on 8-bit overflow.

`sim_out.csv` contains 300 expected `dout` values: 0, 3, 6, 9, …, (3×i) mod 256.
