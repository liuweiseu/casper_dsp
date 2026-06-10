# addersubtracter test data

Input and expected-output vectors for the `addersubtracter` module. Inputs
are random signed values (two's-complement encoded as unsigned integers in
the CSVs) preceded by corner cases (max±min, min±max, zeros, ±1). Expected
outputs are computed with a bit-level Python model of the aligned add/sub,
carry chain and en-gated pipeline; the first `LATENCY` entries are the
pipeline's initial zeros. `simdata1` adds `sim_in_cin.csv` /
`sim_out_cout.csv` for the carry ports; `simdata2` adds `sim_in_sub.csv` /
`sim_in_en.csv` for runtime operation select and pipeline gating.

| Test # | Directory  | N_BITS_A | BIN_PT_A | TYPE_A | N_BITS_B | BIN_PT_B | TYPE_B | MODE | USE_CARRY_IN | USE_CARRY_OUT | ASYNC | LATENCY | Cycles | Description |
|--------|------------|----------|----------|--------|----------|----------|--------|------|--------------|---------------|-------|---------|--------|-------------|
| 0      | `simdata0` | 18       | 17       | 1      | 18       | 17       | 1      | 1    | 0            | 0             | 0     | 1       | 256    | Fixed subtraction, signed 18/17 → 19/17 (the `addsub_re` form inside cmult) |
| 1      | `simdata1` | 8        | 7        | 1      | 8        | 7        | 1      | 0    | 1            | 1             | 0     | 2       | 256    | Fixed addition with random carry-in; carry-out checked |
| 2      | `simdata2` | 8        | 7        | 1      | 8        | 7        | 1      | 2    | 0            | 0             | 1     | 2       | 256    | Runtime add/sub select with random `en` gating the pipeline |
