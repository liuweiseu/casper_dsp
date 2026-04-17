# pulse_ext test data

Each subdirectory corresponds to one parameter set. Input file is `sim_in.csv` (the `in` trigger port); output file is `sim_out.csv`.

| Directory | PULSE_LEN | Cycles | Description |
|-----------|-----------|--------|-------------|
| `simdata0` | 3 | 30 | Single rising edge — pulse of 3 cycles |
| `simdata1` | 5 | 50 | Two separated rising edges — two 5-cycle pulses |
| `simdata2` | 4 | 40 | Second trigger during active pulse — re-arm extends pulse |
