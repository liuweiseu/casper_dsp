# simple_bram_vacc test data

Each subdirectory corresponds to one parameter set. Inputs `sim_new_acc.csv` and `sim_din.csv` (raw words of the din type `N_BITS_IN` / `BIN_PT_IN` / `TYPE_IN`), expected outputs `sim_dout.csv` (raw words of the accumulator type) and `sim_valid.csv`, one value per cycle. `din` is random; `new_acc` pulses (1 to 3 cycles high) every 2 to 4 vectors, sometimes in the middle of a vector. The first `VEC_LEN` cycles show the power-on pulse of the block's `pulse_ext`.

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

Simulink data: exported on 2026-10-28 in this repository's session from Simulink models of `casper_library_accumulators/simple_bram_vacc` (MATLAB R2021a, System Generator 2021.1, SNAP platform), driven by Repeating Sequence Stair sources (a Reinterpret gives `din` its type); all CSVs are the logged Simulink signals.

| Test # | Directory | VEC_LEN | ARITH_TYPE | N_BITS | BIN_PT | N_BITS_IN | BIN_PT_IN | TYPE_IN | Cycles | Description |
|--------|-----------|---------|------------|--------|--------|-----------|-----------|---------|--------|-------------|
| 0 | `simdata0` | 512 | 0 | 64 | 34 | 37 | 36 | 0 | 4000 | tut_spec configuration: vec_len 512, UFix_64_34 accumulator, din UFix_37_36 (power output) |
| 1 | `simdata1` | 8 | 1 | 16 | 4 | 10 | 2 | 1 | 600 | vec_len 8, Fix_16_4 accumulator, signed din Fix_10_2 |
| 2 | `simdata2` | 6 | 0 | 8 | 0 | 8 | 0 | 0 | 500 | minimum vec_len 6, UFix_8_0: sums wrap |
| 3 | `simdata3` | 20 | 1 | 12 | 0 | 12 | 4 | 1 | 800 | vec_len 20, Fix_12_0 accumulator, din Fix_12_4 (fraction truncated) |
