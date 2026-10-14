# pulse_ext test data

Each subdirectory corresponds to one parameter set. Input file is `sim_in.csv` (the `in` trigger port); output file is `sim_out.csv`.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: the `sim_*.csv` files of sets 0–2 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Test # | Directory | PULSE_LEN | Cycles | Description |
|--------|-----------|-----------|--------|-------------|
| 0 | `simdata0` | 3 | 30 | Single rising edge — pulse of 3 cycles |
| 1 | `simdata1` | 5 | 50 | Two separated rising edges — two 5-cycle pulses |
| 2 | `simdata2` | 4 | 40 | Second trigger during active pulse — re-arm extends pulse |
