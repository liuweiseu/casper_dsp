# cmult

Pipelined complex multiplier, `ab = a × b` (4-real-multiply form). Matches
`casper_library_multipliers/cmult` from mlib_devel (behavioral-HDL
multiplier implementation, fixed point; the floating-point mode and
`multiplier_implementation` choices are not applicable to RTL behaviour).

The module is a structural composition of verified BasicModules — it
contains no arithmetic of its own:

```
a ─[delay]─ c_to_ri ─┬─ multiplier rere ─┬─ addersubtracter (re) ─ convert ─┐
b ─[delay]─ c_to_ri ─┼─ multiplier imim ─┘                                  ├─ ri_to_c ─ ab
                     ├─ multiplier imre ─┬─ addersubtracter (im) ─ convert ─┘
                     └─ multiplier reim ─┘
```

Complex values are packed `{re, im}` with `re` in the MSBs (per
`ri_to_c`/`c_to_ri`). All four real products are computed at full precision
(`N_BITS_A+N_BITS_B` bits), the add/sub layer grows one bit, and the convert
layer quantizes to `(N_BITS_AB, BIN_PT_AB)` with the selected
`QUANTIZATION`/`OVERFLOW` behaviour.

**Conjugated mode.** With `CONJUGATED=1` the add/sub modes swap
(re = rere + imim, im = imre − reim), which computes **`a × conj(b)`** —
this matches the mlib_devel implementation exactly. Note the mlib_devel
docstring claims the `a` input is conjugated, but its wiring conjugates `b`;
we replicate the implementation, not the comment.

**Enable / dvalid.** With `ASYNC=1` and `PIPELINED_ENABLE=1`, `en` is
re-registered alongside the data (through IN/MULT/ADD/CONV latency stages)
and emerges as `dvalid`. With `PIPELINED_ENABLE=0`, the same `en` directly
gates every pipeline stage, the input register layer is bypassed
(`IN_LATENCY` is ignored, per `cmult_init.m`) and `dvalid` stays 0. With
`ASYNC=0` the pipeline is free-running and `dvalid` stays 0.

**Deviation from mlib_devel:** when `PIPELINE_CMULT_EN=1` the en chain here
includes `PIPELINE_LATENCY`, keeping `dvalid` aligned with the data;
mlib_devel omits it (the option is only used in synchronous embedded-
multiplier designs there).

Total latency = `IN_LATENCY` (when active) + `MULT_LATENCY` +
`PIPELINE_LATENCY` (when `PIPELINE_CMULT_EN=1`) + `ADD_LATENCY` +
`CONV_LATENCY`.

## Parameters

| Parameter           | Default | Description |
|---------------------|---------|-------------|
| `N_BITS_A`          | 18      | Bit width of each component of `a` |
| `BIN_PT_A`          | 17      | Binary point of each component of `a` |
| `N_BITS_B`          | 18      | Bit width of each component of `b` |
| `BIN_PT_B`          | 17      | Binary point of each component of `b` |
| `N_BITS_AB`         | 37      | Bit width of each component of `ab` |
| `BIN_PT_AB`         | 14      | Binary point of each component of `ab` |
| `QUANTIZATION`      | 0       | 0 = Truncate, 1 = Round (unbiased: ±Inf), 2 = Round (unbiased: even values) |
| `OVERFLOW`          | 0       | 0 = Wrap, 1 = Saturate |
| `IN_LATENCY`        | 0       | Input register stages |
| `MULT_LATENCY`      | 3       | Real-multiplier pipeline stages |
| `ADD_LATENCY`       | 1       | Add/sub pipeline stages |
| `CONV_LATENCY`      | 1       | Convert pipeline stages |
| `CONJUGATED`        | 0       | 1 = compute `a × conj(b)` (see note above) |
| `ASYNC`             | 0       | 1 = `en`/`dvalid` active |
| `PIPELINED_ENABLE`  | 1       | 1 = en re-registered per stage (dvalid available); 0 = direct en gating |
| `PIPELINE_CMULT_EN` | 0       | 1 = extra pipeline between multipliers and add/sub |
| `PIPELINE_LATENCY`  | 2       | Depth of that extra pipeline |

## Ports

| Port     | Direction | Width | Description |
|----------|-----------|-------|-------------|
| `clk`    | input     | 1     | Clock |
| `rst`    | input     | 1     | Synchronous reset (clears mult/add/convert pipelines) |
| `a`      | input     | `2*N_BITS_A` | Complex multiplicand `{re_a, im_a}` |
| `b`      | input     | `2*N_BITS_B` | Complex multiplier `{re_b, im_b}` |
| `en`     | input     | 1     | Enable (active when `ASYNC=1`, otherwise ignored) |
| `ab`     | output    | `2*N_BITS_AB` | Complex product `{re_ab, im_ab}` |
| `dvalid` | output    | 1     | Delayed `en` (only when `ASYNC=1` and `PIPELINED_ENABLE=1`, else 0) |
