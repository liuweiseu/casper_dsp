# relational test data

Each subdirectory corresponds to one parameter set. `COMP`: 0=eq, 1=ne, 2=lt, 3=gt, 4=le, 5=ge. Input files are `sim_a.csv` and `sim_b.csv`; output file is `sim_out.csv`.

**CSV data exported from the corresponding MATLAB Simulink block.**

This applies to `simdata0`–`simdata7` (unsigned, `SIGNED` = 0). `simdata8`–`simdata16` test the `SIGNED` parameter. They are generated from a Python model by `test_data/scripts/gen_basic_test_data.py`, which also writes a `params.json` for each set. The 4- and 5-bit sets cover every input pair in shuffled order.

| Test # | Directory | NBITS | COMP | LATENCY | SIGNED | Cycles | Description |
|--------|-----------|-------|------|---------|--------|--------|-------------|
| 0 | `simdata0` | 4 | 0 (eq) | 1 | 0 | 20 | Equal — registered output |
| 1 | `simdata1` | 4 | 1 (ne) | 1 | 0 | 20 | Not-equal — registered output |
| 2 | `simdata2` | 4 | 2 (lt) | 1 | 0 | 20 | Less-than — registered output |
| 3 | `simdata3` | 4 | 3 (gt) | 1 | 0 | 20 | Greater-than — registered output |
| 4 | `simdata4` | 4 | 4 (le) | 1 | 0 | 20 | Less-or-equal — registered output |
| 5 | `simdata5` | 4 | 5 (ge) | 1 | 0 | 20 | Greater-or-equal — registered output |
| 6 | `simdata6` | 4 | 2 (lt) | 0 | 0 | 20 | Less-than — combinational output (LATENCY=0) |
| 7 | `simdata7` | 8 | 0 (eq) | 2 | 0 | 20 | Equal, 8-bit — two pipeline stages |
| 8 | `simdata8` | 4 | 0 (eq) | 1 | 1 | 256 | Signed equal — all input pairs |
| 9 | `simdata9` | 4 | 1 (ne) | 1 | 1 | 256 | Signed not-equal — all input pairs |
| 10 | `simdata10` | 4 | 2 (lt) | 1 | 1 | 256 | Signed less-than — all input pairs |
| 11 | `simdata11` | 4 | 3 (gt) | 1 | 1 | 256 | Signed greater-than — all input pairs |
| 12 | `simdata12` | 4 | 4 (le) | 1 | 1 | 256 | Signed less-or-equal — all input pairs |
| 13 | `simdata13` | 4 | 5 (ge) | 1 | 1 | 256 | Signed greater-or-equal — all input pairs |
| 14 | `simdata14` | 4 | 2 (lt) | 0 | 1 | 256 | Signed less-than, combinational — all input pairs |
| 15 | `simdata15` | 7 | 5 (ge) | 2 | 1 | 300 | Signed greater-or-equal, 7-bit random inputs, two pipeline stages |
| 16 | `simdata16` | 5 | 2 (lt) | 1 | 0 | 1024 | Explicit unsigned less-than — all input pairs |
