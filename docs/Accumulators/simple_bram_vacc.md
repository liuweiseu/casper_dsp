# simple_bram_vacc

## Description

A vector accumulator over `VEC_LEN`-sample vectors, as the casper_library
block `casper_library_accumulators/simple_bram_vacc`.
`simple_bram_vacc_init.m` only sets the types. The structure is:

```
valid  = pulse_ext(new_acc, pulse_len = VEC_LEN)
sum    = din + (valid ? 0 : dout)      AddSub, <ARITH_TYPE> N_BITS_BIN_PT, Truncate / Wrap, latency 2
dout   = delay_bram(sum, DelayLen = VEC_LEN − 2, bram_latency 2)
```

- **The loop:** the adder and the `delay_bram` form a `VEC_LEN`-cycle loop.
  Each sample is added to the running sum of its vector position.
- **Restart:** while `valid = 1`, the loop restarts from 0, and `dout` shows
  the finished sums. `valid` is high for the `VEC_LEN` cycles after a rising
  edge of `new_acc`, and also for the first `VEC_LEN` cycles after power-on
  (the `pulse_ext` power-on pulse).
- **Input type:** `din` has its own fixed-point type (`N_BITS_IN`,
  `BIN_PT_IN`, `TYPE_IN`; inherited in Simulink). The adder aligns it with
  `BIN_PT`, then truncates and wraps to the accumulator type.
- **Building blocks:** the module is built from `pulse_ext`, `multiplexer`,
  `adder_subtractor` and `delay_bram`.
- **Parameter checks:** it stops with `$fatal` when `VEC_LEN < 6`,
  `N_BITS < 1` or `BIN_PT > N_BITS`. In these cases the Simulink init only
  shows an error dialog; `VEC_LEN < 6` then fails in `delay_bram`
  (docs/bugs.md bug 7).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `VEC_LEN` | 16 | Vector length (mask `vec_len`), ≥ 6 |
| `ARITH_TYPE` | 0 | Accumulator type: `0` Unsigned, `1` Signed (mask `arith_type`) |
| `N_BITS` | 32 | Accumulator width (mask `n_bits`) |
| `BIN_PT` | 0 | Accumulator binary point (mask `bin_pt`) |
| `N_BITS_IN`, `BIN_PT_IN`, `TYPE_IN` | 8, 0, 0 | Type of `din` (HDL only; inherited in Simulink) |
| `PLATFORM` | `"GENERIC"` | Memory vendor of the `delay_bram` |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `new_acc` | input | 1 | Start a new accumulation (rising edge) |
| `din` | input | `N_BITS_IN` | Sample |
| `dout` | output | `N_BITS` | Accumulated vector, one position per cycle |
| `valid` | output | 1 | High while `dout` shows finished sums (`VEC_LEN` cycles) |
