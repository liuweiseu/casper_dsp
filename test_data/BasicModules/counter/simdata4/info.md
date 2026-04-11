# simdata4 — Test Parameters

| Parameter     | Value          |
|---------------|----------------|
| COUNTER_TYPE  | count_limit    |
| COUNT_DIR     | down           |
| NBITS         | 8              |
| STEP          | 1              |
| INIT_VAL      | 20             |
| COUNT_TO_VAL  | 0              |

## Description

Limited down counter. The counter decrements by 1 every clock cycle starting from 20,
and holds at COUNT_TO_VAL (0) once reached.

`sim_out.csv` contains 300 expected `dout` values: 20, 19, 18, …, 0, 0, …, 0.
