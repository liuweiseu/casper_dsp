# pulse_ext test data

Each subdirectory corresponds to one parameter set. Input file is `sim_in.csv` (the `in` trigger port); output file is `sim_out.csv`.

**CSV data exported from the corresponding MATLAB Simulink block.**

| Test # | Directory | PULSE_LEN | Cycles | Description |
|--------|-----------|-----------|--------|-------------|
| 0 | `simdata0` | 3 | 30 | Single rising edge — pulse of 3 cycles |
| 1 | `simdata1` | 5 | 50 | Two separated rising edges — two 5-cycle pulses |
| 2 | `simdata2` | 4 | 40 | Second trigger during active pulse — re-arm extends pulse |
