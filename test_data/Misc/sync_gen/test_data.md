# sync_gen test data

Each subdirectory corresponds to one parameter set. Inputs are the three software-register values `sim_sync.csv`, `sim_sync_period_sel.csv` and `sim_sync_period_var.csv` (32-bit words; the block uses bit 0 of `sync` and `sync_period_sel`); the expected output is `sim_sync_out.csv`, one value per cycle. `sync` has pulses of 1 to 40 cycles with various values (bit 0 set or clear); `sync_period_sel` and `sync_period_var` change every 60 to 200 cycles, sometimes in the middle of a period. `REORDER_VEC` is the mask vector (a TOML list in `tests/simulation.toml`, packed into 32-bit elements by `tests/test_runner.py`).

**CSV data exported from the corresponding MATLAB Simulink block.**

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT.

Simulink data: exported on 2026-10-28 in this repository's session from Simulink models of `casper_library_misc/sync_gen` (MATLAB R2021a, System Generator 2021.1, SNAP platform). The block's three swregs take their simulation values from Constant blocks inside it (`sync` = 1, the others 0); in these models the link was broken and those three Constants were replaced by Repeating Sequence Stair sources playing the register values above, the rest of the block unchanged. `sim_sync_out.csv` is the logged Simulink output; the register CSVs are the source values.

| Test # | Directory | SIM_ACC_LEN | FFT_SIZE | FFT_SIMULT_INPUTS | PFB_FIR_TAPS | REORDER_VEC | SCALE | Cycles | Description |
|--------|-----------|-------------|----------|-------------------|--------------|-------------|-------|--------|-------------|
| 0 | `simdata0` | 1 | 4096 | 8 | 4 | `[2 2 9]` | 4096 | 600 | tut_spec configuration (period 150994944): sync edges and sync_period_var only |
| 1 | `simdata1` | 1 | 8 | 2 | 2 | `[2 3]` | 1 | 600 | period 48 (constant 46) |
| 2 | `simdata2` | 2 | 16 | 4 | 1 | `[3 4 6]` | 1 | 800 | period 96 (constant 94), lcm of three reorder lengths |
| 3 | `simdata3` | 1 | 4 | 4 | 1 | `[1]` | 3 | 400 | period 3 (constant 1): the shortest periods |
