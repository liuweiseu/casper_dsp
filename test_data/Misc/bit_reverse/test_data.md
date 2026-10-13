# bit_reverse test data

Each subdirectory corresponds to one parameter set.

Every `simdataN/` holds a `params.json` with the DUT parameters of that set; the testbench selects the set whose `params.json` matches the DUT (`find_data_dir` in `testbench/data_paths.py`).

| Test # | Directory | N_BITS | Cycles | Description |
|--------|-----------|-------|--------|-------------|
| 0 | `simdata0` | 8  | 256 | Reverse bit order of an 8-bit word |
| 1 | `simdata1` | 16 | 300 | Reverse bit order of a 16-bit word |
