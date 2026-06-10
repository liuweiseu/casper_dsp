# multiplier test data

Input and expected-output vectors for the `multiplier` module. Inputs are
random signed values (two's-complement encoded as unsigned integers in the
CSVs) preceded by corner cases (max×max, min×min, min×max, zeros, ±1).
Expected outputs are computed with a Python model of the multiply,
quantization, saturation and en-gated pipeline; the first `LATENCY` entries
are the pipeline's initial zeros. `simdata2` additionally provides
`sim_in_en.csv` for the en-gated (`ASYNC=1`) configuration.

| Test # | Directory  | N_BITS_A | BIN_PT_A | N_BITS_B | BIN_PT_B | TYPE_A | TYPE_B | PRECISION | N_BITS_OUT | BIN_PT_OUT | TYPE_OUT | QUANTIZATION | OVERFLOW | ASYNC | LATENCY | Cycles | Description |
|--------|------------|----------|----------|----------|----------|--------|--------|-----------|------------|------------|----------|--------------|----------|-------|---------|--------|-------------|
| 0      | `simdata0` | 18       | 17       | 18       | 17       | 1      | 1      | 0         | —          | —          | —        | —            | —        | 0     | 2       | 256    | Full precision, signed 18×18 → 36 (the form used inside cmult) |
| 1      | `simdata1` | 8        | 7        | 8        | 7        | 1      | 1      | 1         | 8          | 7          | 1        | 1            | 1        | 0     | 2       | 256    | User defined 8×8 → 8 (SHIFT=7), Round ±Inf + Saturate (min×min saturates) |
| 2      | `simdata2` | 8        | 7        | 8        | 7        | 1      | 1      | 0         | —          | —          | —        | —            | —        | 1     | 2       | 256    | Full precision, random `en` gating the pipeline |
