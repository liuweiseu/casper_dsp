# power test data

Each subdirectory corresponds to one parameter set. `sim_c.csv` holds the complex input (raw `{re, im}` word, re in the MSBs, each part Fix_<BIT_WIDTH>_<BIT_WIDTH-1>) and `sim_dout.csv` the expected `dout` (Simulink port `power`; raw UFix_<2·BIT_WIDTH+1>_<2·BIT_WIDTH>), one value per cycle. The stimulus starts with corner values (both parts at -1, the largest positive values, all ones) followed by random words; set 2 covers every 8-bit input.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: exported on 2026-10-28 in this repository's session from Simulink models of `casper_library_misc/power` (MATLAB R2021a, System Generator 2021.1, SNAP platform), driven by Repeating Sequence Stair sources; both CSVs are the logged Simulink signals.

| Test # | Directory | BIT_WIDTH | ADD_LATENCY | MULT_LATENCY | Cycles | Description |
|--------|-----------|-----------|-------------|--------------|--------|-------------|
| 0 | `simdata0` | 18 | 2 | 3 | 400 | tut_spec configuration: BitWidth 18, add_latency 2, mult_latency 3 |
| 1 | `simdata1` | 8 | 1 | 2 | 300 | 8-bit, add_latency 1, mult_latency 2 |
| 2 | `simdata2` | 4 | 0 | 0 | 300 | 4-bit, combinational (both latencies 0): every input value |
| 3 | `simdata3` | 12 | 3 | 1 | 300 | 12-bit, add_latency 3, mult_latency 1 |
