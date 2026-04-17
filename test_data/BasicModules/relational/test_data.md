# relational test data

Each subdirectory corresponds to one parameter set. `COMP`: 0=eq, 1=ne, 2=lt, 3=gt, 4=le, 5=ge. Input files are `sim_a.csv` and `sim_b.csv`; output file is `sim_out.csv`.

| Test # | Directory | NBITS | COMP | LATENCY | Cycles | Description |
|--------|-----------|-------|------|---------|--------|-------------|
| 0 | `simdata0` | 4 | 0 (eq) | 1 | 20 | Equal — registered output |
| 1 | `simdata1` | 4 | 1 (ne) | 1 | 20 | Not-equal — registered output |
| 2 | `simdata2` | 4 | 2 (lt) | 1 | 20 | Less-than — registered output |
| 3 | `simdata3` | 4 | 3 (gt) | 1 | 20 | Greater-than — registered output |
| 4 | `simdata4` | 4 | 4 (le) | 1 | 20 | Less-or-equal — registered output |
| 5 | `simdata5` | 4 | 5 (ge) | 1 | 20 | Greater-or-equal — registered output |
| 6 | `simdata6` | 4 | 2 (lt) | 0 | 20 | Less-than — combinational output (LATENCY=0) |
| 7 | `simdata7` | 8 | 0 (eq) | 2 | 25 | Equal, 8-bit — two pipeline stages |
