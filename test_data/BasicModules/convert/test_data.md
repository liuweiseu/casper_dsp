# convert test data

Input and expected-output vectors for the `convert` module. Inputs are
random signed values (two's-complement encoded as unsigned integers in the
CSVs) preceded by corner cases: full-scale extremes, zero, and explicit
rounding ties (`remainder == half LSB`) with even and odd truncation
results, which distinguish the three quantization modes. Expected outputs
are computed with a Python model of the shift/quantize/saturate steps and
the en-gated pipeline; the first `LATENCY` entries are the pipeline's
initial zeros. `simdata2` adds `sim_in_en.csv` for the en-gated (`ASYNC=1`)
configuration.

| Test # | Directory  | N_BITS_IN | BIN_PT_IN | TYPE_IN | N_BITS_OUT | BIN_PT_OUT | TYPE_OUT | QUANTIZATION | OVERFLOW | ASYNC | LATENCY | Cycles | Description |
|--------|------------|-----------|-----------|---------|------------|------------|----------|--------------|----------|-------|---------|--------|-------------|
| 0      | `simdata0` | 18        | 17        | 1       | 8          | 7          | 1        | 0            | 0        | 0     | 1       | 256    | SHIFT=10, Truncate + Wrap |
| 1      | `simdata1` | 18        | 17        | 1       | 8          | 7          | 1        | 1            | 1        | 0     | 1       | 256    | SHIFT=10, Round ±Inf + Saturate (the cmult convert form) |
| 2      | `simdata2` | 12        | 8         | 1       | 8          | 4          | 1        | 2            | 1        | 1     | 2       | 256    | SHIFT=4, Round even + Saturate, random `en` gating the pipeline |
| 3      | `simdata3` | 16        | 8         | 1       | 16         | 12         | 1        | 0            | 1        | 0     | 1       | 256    | SHIFT=−4 left shift + Saturate |
