# c_to_ri test data

Each subdirectory corresponds to one parameter set. The input file `sim_c.csv` holds the packed complex word; `sim_re.csv` and `sim_im.csv` hold the expected real and imaginary outputs. `BIN_PT` does not affect bit-level behaviour and is not varied across test sets.

| Test # | Directory | N_BITS | BIN_PT | Cycles | Description |
|--------|-----------|-------|--------|--------|-------------|
| 0 | `simdata0` | 8  | 7  | 100 | Unpack a 16-bit complex word into two 8-bit parts |
| 1 | `simdata1` | 16 | 15 | 100 | Unpack a 32-bit complex word into two 16-bit parts |
