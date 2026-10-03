# cmult

## Description

Port of casper_library's `cmult` (`casper_library_multipliers`, `cmult_init.m`). It multiplies two complex words and converts both parts to the output format:

- `CONJUGATED = 0`: `ab = a · b`
- `CONJUGATED = 1`: `ab = a · conj(b)`

The conjugated operand is **b**. The comment at `cmult_init.m:44` says "a", but the wiring conjugates b. The conjugate comes from the add/sub signs, not from negating `b_im`, so `b_im = −2^(N_BITS_B−1)` does not wrap.

```
a ─► pipeline(IN_LATENCY) ─► {a_re, a_im}      b ─► pipeline(IN_LATENCY) ─► {b_re, b_im}
rere = a_re·b_re   imim = a_im·b_im   imre = a_im·b_re   reim = a_re·b_im   (full precision, MULT_LATENCY)
[pipeline(PIPELINE_LATENCY): only with MULTIPLIER_IMPLEMENTATION = 2 and PIPELINE_CMULT_EN = 1]
re = rere ∓ imim   im = imre ± reim   (upper sign: CONJUGATED = 0; full precision, ADD_LATENCY)
ab = {convert(re), convert(im)}   (N_BITS_AB / BIN_PT_AB, QUANTIZATION / OVERFLOW, CONV_LATENCY)
```

Total latency is `IN_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY`, plus `PIPELINE_LATENCY` in the embedded-multiplier pipeline case.

The products (`N_BITS_A+N_BITS_B` bits) and sums (one bit more) are exact, so the output convert is the only rounding step. The module is built from `Bus/multiplier` ×4, `Bus/adder_subtractor` ×2, `Bus/convert` ×2 and `Delays/pipeline`.

**`cmult_4bit_hdl*` equivalence:** casper_library's `cmult_4bit_hdl*` (`system_145`) computes `real = ac + bd` and `imag = bc − ad` at full precision, with latency `mult + add`. It is bit- and cycle-equivalent to `cmult` with:

- `CONJUGATED = 1`
- `N_BITS_AB = N_BITS_A + N_BITS_B + 1`, `BIN_PT_AB = BIN_PT_A + BIN_PT_B`
- `IN_LATENCY = CONV_LATENCY = 0`

The only difference is that `cmult` packs the two parts into one word, where `cmult_4bit_hdl*` has separate real/imag ports. `cmult_4bit_hdl` is the same with `CONJUGATED = 0`.

## Parameters

Names follow the `cmult` mask. Defaults are the values stored in the casper_library mask, with one exception: the mask stores `n_bits_a = 0`, the empty-block value, which this module rejects (`$fatal`), so `N_BITS_A` uses the `cmult_init.m` default 18. `PIPELINE_LATENCY` keeps the mask-stored 0 (`cmult_init.m` uses 2).

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_BITS_A` / `BIN_PT_A` | 18 / 17 | Width / binary point of each part of `a` (signed) |
| `N_BITS_B` / `BIN_PT_B` | 18 / 17 | Width / binary point of each part of `b` (signed) |
| `N_BITS_AB` / `BIN_PT_AB` | 37 / 14 | Width / binary point of each part of `ab` (signed) |
| `QUANTIZATION` | 0 | 0 = Truncate, 1 = Round (unbiased: ±Inf), 2 = Round (unbiased: Even Values) |
| `OVERFLOW` | 0 | 0 = Wrap, 1 = Saturate |
| `MULT_LATENCY` | 3 | Multiplier latency |
| `ADD_LATENCY` | 1 | Add/sub latency |
| `CONV_LATENCY` | 1 | Output convert latency |
| `IN_LATENCY` | 0 | Input register latency (bus_replicate `csp_latency`) |
| `CONJUGATED` | 0 | 1 = multiply by the conjugate of `b` |
| `MULTIPLIER_IMPLEMENTATION` | 0 | 0 = behavioral HDL, 1 = standard core, 2 = embedded multiplier core. Resource only, except that 2 enables `PIPELINE_CMULT_EN` |
| `PIPELINE_CMULT_EN` | 0 | 1 = `PIPELINE_LATENCY` registers between multipliers and add/subs (embedded multipliers only) |
| `PIPELINE_LATENCY` | 0 | See `PIPELINE_CMULT_EN` |
| `FLOATING_POINT` | 0 | Must be 0 (floating point not implemented, `$fatal`) |
| `FLOAT_TYPE` / `EXP_WIDTH` / `FRAC_WIDTH` | "single" / 8 / 24 | Floating-point only; declared, not implemented |
| `ASYNC` | 0 | Must be 0 (`en` / `dvalid` ports not implemented, `$fatal`) |
| `PIPELINED_ENABLE` | 1 | `ASYNC` only; declared, not implemented |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a` | input | `2*N_BITS_A` | `{a_re, a_im}`, real part in the MSBs |
| `b` | input | `2*N_BITS_B` | `{b_re, b_im}`, real part in the MSBs |
| `ab` | output | `2*N_BITS_AB` | `{ab_re, ab_im}`, real part in the MSBs |
