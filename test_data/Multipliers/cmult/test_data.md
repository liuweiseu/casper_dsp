# cmult test data

Input and expected-output vectors for the `cmult` module. Inputs are random
complex values (components packed `{re, im}`, two's-complement encoded)
preceded by corner cases: full-scale extremes on each axis (including
min×min, whose squared magnitude exercises the post-add bit growth), zeros
and ±1 LSB values. Expected outputs are computed with a cycle-accurate
structural Python model that mirrors the RTL composition (4 full-precision
multiplies → add/sub → convert, with per-stage en gating and the en delay
chain); the first `total latency` entries are the pipeline's initial zeros.
`simdata2` adds `sim_in_en.csv` and `sim_out_dvalid.csv` for the async
pipelined-enable configuration.

All sets use `N_BITS_A/B=8`, `BIN_PT_A/B=7`, `MULT_LATENCY=2`,
`ADD_LATENCY=1`, `CONV_LATENCY=1`.

| Test # | Directory  | N_BITS_AB | BIN_PT_AB | QUANTIZATION | OVERFLOW | IN_LATENCY | CONJUGATED | ASYNC | PIPELINED_ENABLE | Cycles | Description |
|--------|------------|-----------|-----------|--------------|----------|------------|------------|-------|------------------|--------|-------------|
| 0      | `simdata0` | 17        | 14        | 0            | 0        | 0          | 0          | 0     | 1                | 256    | Full-width pass-through (SHIFT=0), total latency 4 |
| 1      | `simdata1` | 8         | 7         | 1            | 1        | 0          | 0          | 0     | 1                | 256    | SHIFT=7, Round ±Inf + Saturate (min×min saturates) |
| 2      | `simdata2` | 17        | 14        | 0            | 0        | 1          | 0          | 1     | 1                | 256    | Async pipelined enable, random `en`, dvalid checked, total latency 5 |
| 3      | `simdata3` | 17        | 14        | 0            | 0        | 0          | 1          | 0     | 1                | 256    | Conjugated mode: computes a × conj(b) (mlib_devel implementation behaviour) |
