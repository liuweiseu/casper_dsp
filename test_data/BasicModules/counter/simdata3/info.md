# simdata3 — Test Parameters

| Parameter     | Value          |
|---------------|----------------|
| COUNTER_TYPE  | count_limit    |
| COUNT_DIR     | up             |
| NBITS         | 8              |
| STEP          | 1              |
| INIT_VAL      | 0              |
| COUNT_TO_VAL  | 20             |

## Description

Limited up counter. The counter increments by 1 every clock cycle starting from 0,
and holds at COUNT_TO_VAL (20) once reached.

`sim_out.csv` contains 300 expected `dout` values: 0, 1, 2, …, 20, 20, …, 20.
