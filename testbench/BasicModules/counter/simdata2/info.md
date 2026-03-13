# simdata2 — Test Parameters

| Parameter     | Value          |
|---------------|----------------|
| COUNTER_TYPE  | free_running   |
| COUNT_DIR     | down           |
| NBITS         | 8              |
| STEP          | 1              |
| INIT_VAL      | 255            |
| COUNT_TO_VAL  | 0              |

## Description

Free-running down counter with unit step. The counter decrements by 1 every clock
cycle starting from 255, wrapping around from 0 back to 255 (8-bit underflow).

`sim_out.csv` contains 300 expected `dout` values: 255, 254, 253, …, 0, 255, 254, …, 212.
