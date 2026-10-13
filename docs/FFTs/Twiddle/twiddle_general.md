# twiddle_general

## Description

The general-case twiddle stage of an FFT butterfly. It corresponds to
casper_library's `twiddle_general` (fixed-point, synchronous path). Each of the
`N_INPUTS` complex lanes has two legs:

- **a leg**: `ai → ao`, delay-matched only.
- **b leg**: `bi → bwo = bi · w[k]`. All lanes use the same coefficient in a
  given cycle.

`sync_in → sync_out` is delay-matched too.

```
sync_in ─► counter (cleared by sync) ─► addr = cnt >> STEP_PERIOD
                                         ▼
                 rom (INIT_FILE) ─► pipeline(CG_LATENCY-1) ─► w = {re, im}
bi ─► pipeline(CG_LATENCY) ─► complex_multiplier (exact) ─► convert ─► bwo
ai, sync_in ─► pipeline(LATENCY) ─► ao, sync_out
```

The structure and timing follow casper's: `coeff_gen` carries `ai`, `bi` and
`sync` on its misc path with the coefficient latency `CG_LATENCY`, then
`bus_mult` and `bus_convert` carry `ai` and `sync` with the product. With a
single coefficient (`N_COEFFS = 1`) there is no counter and no `rom`: the
coefficient is a constant (row 0 of `INIT_FILE`, two Constants in casper) and
`CG_LATENCY = 0`.

It is built from [`counter`](../../BasicModules/counter.md),
[`rom`](../../Delays/rom.md), [`pipeline`](../../Delays/pipeline.md),
[`complex_multiplier`](../../Multipliers/complex_multiplier.md) (4-multiply
form) and [`convert`](../../Bus/convert.md).

## Coefficient Table and Schedule

[`rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py`](../../../rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py)
generates the table from casper_library's `Coeffs` and `FFTSize`, using the
formula in `coeff_gen_init.m`:

```
w[k] = exp(-2πj · bit_rev(Coeffs[k], FFTSize-1) / 2^FFTSize)
```

- **Order**: row `k` holds `w[k]`, in the order of the `Coeffs` list. The bit
  reversal is already applied to the stored values, so the address counter
  steps through the table in order.
- **Format**: each part is a `COEFF_BIT_WIDTH`-bit signed word with binary point
  `COEFF_BIT_WIDTH − 1`, rounded half away from zero and saturated.
- **Words as Simulink**: the generator reproduces casper's `cosin` lookup for
  the module's `STEP_PERIOD`, `COEFFS_BIT_LIMIT`, `COEFF_SHARING` and
  `COEFF_DECIMATION` (which part of the cycle is stored, whether cos and sin
  share a table, and which values are derived by moving the address and
  negating). +1.0 is the largest positive word, and a −1.0 that `cosin`
  derives by negating it is −(1 − 2^−(`COEFF_BIT_WIDTH`−1)), not the most
  negative word, as in Simulink (e.g. cos = −1 at w = −1, sin = −1 at w = −j).
  This is a fixed-point convention, not a library bug. Exceptions: the
  quarter-cycle address-0 entry holds the intended value
  ([bug 15](../../bugs.md)); a `feedback_osc` list, and an in-order list with
  `FFT_SIZE − STEP_PERIOD − log2 N_COEFFS ≠ 1` (whose `cosin` angles are not
  the formula), get the exactly rounded formula values. A one-entry list is
  rounded to `COEFF_BIT_WIDTH − 2` fractional bits, as casper's Constants
  (`coeff_gen_init.m:156-157`).
- **Packing**: each row is `{re, im}`, with the real part in the upper half.

```
python3 rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --fft-size 5 --coeffs 0 1 2 3 \
    --step-period 2 --coeff-bit-width 18 -o twiddle.mem   # see --help for the other casper options
```

**Schedule.** `sync_in` clears the counter, as it does in casper_library's
`coeff_gen`. The sample on the cycle after a sync pulse (the first sample of a
CASPER frame) is multiplied by `w[0]`. Each row is then used for
`2^STEP_PERIOD` consecutive cycles, wrapping after `N_COEFFS` rows.
`N_COEFFS` does not have to be a power of two. Without sync pulses, the counter
free-runs from 0.

## Parameters

| Parameter         | Default     | Description |
|-------------------|-------------|-------------|
| `N_INPUTS`        | 1           | Number of complex lanes |
| `FFT_SIZE`        | 2           | casper `FFTSize` of the table (documentation; the table is fixed by `INIT_FILE`) |
| `N_COEFFS`        | 2           | Number of table rows (`length(Coeffs)`) |
| `STEP_PERIOD`     | 0           | Each row is held for `2^STEP_PERIOD` cycles |
| `INPUT_BIT_WIDTH` | 18          | Width of `ai`, `bi` and `ao` (signed) |
| `BIN_PT_IN`       | 17          | Binary point of `ai`, `bi`, `ao` and `bwo` |
| `COEFF_BIT_WIDTH` | 18          | Width of each coefficient part (binary point `COEFF_BIT_WIDTH − 1`) |
| `MULT_LATENCY`    | 2           | `complex_multiplier` multiplier stages |
| `ADD_LATENCY`     | 1           | `complex_multiplier` adder stages |
| `CONV_LATENCY`    | 1           | Output `convert` stages |
| `BRAM_LATENCY`    | 1           | `cosin` BRAM latency, part of `CG_LATENCY` (≥ 0; unused with one coefficient) |
| `QUANTIZATION`    | 1           | `bwo` rounding: `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`        | 0           | `bwo` overflow: `0`=wrap, `1`=saturate |
| `INIT_FILE`       | `""`        | Coefficient table (`.mem`) from `gen_twiddle_coeffs.py` |
| `PLATFORM`        | `"GENERIC"` | Passed to `rom` (`"GENERIC"`, `"XILINX"`, `"ALTERA"`) |
| `ASYNC`           | 0           | casper `async`: `1` = `en` enables the coefficient address counter (sync still clears it) and `dvalid` = `en` delayed `LATENCY`; the data is not gated. |

**Declared but not implemented** (kept for parameter traceability):
- `FLOATING_POINT` must be 0. Other values stop elaboration.
- These are ignored: `FLOAT_TYPE`, `EXP_WIDTH`, `FRAC_WIDTH`, `COEFF_SHARING`,
  `COEFF_DECIMATION`, `COEFF_GENERATION`, `CAL_BITS`, `N_BITS_ROTATION`,
  `MAX_FANOUT`, `USE_HDL`, `USE_EMBEDDED`, `COEFFS_BIT_LIMIT`. casper_library's
  table-size optimizations are not reproduced; the table is flat.

## Ports

All lane ports are unpacked arrays of `N_INPUTS` words, like `din` in
[`logical`](../../BasicModules/logical.md).

| Port       | Direction | Width                     | Description |
|------------|-----------|---------------------------|-------------|
| `clk`      | input     | 1                         | Clock |
| `ai_re`, `ai_im`   | input  | `INPUT_BIT_WIDTH` × `N_INPUTS` | a leg input |
| `bi_re`, `bi_im`   | input  | `INPUT_BIT_WIDTH` × `N_INPUTS` | b leg input |
| `sync_in`  | input     | 1                         | Frame sync; clears the coefficient schedule |
| `en`       | input     | 1                         | Async enable (used when `ASYNC = 1`; default 1) |
| `ao_re`, `ao_im`   | output | `INPUT_BIT_WIDTH` × `N_INPUTS` | `ai` delayed by `LATENCY` |
| `bwo_re`, `bwo_im` | output | `INPUT_BIT_WIDTH+1` × `N_INPUTS` | `bi · w`, delayed by `LATENCY` |
| `sync_out` | output    | 1                         | `sync_in` delayed by `LATENCY` |
| `dvalid`   | output    | 1                         | `en` delayed by `LATENCY` when `ASYNC = 1`, else 0 |

`bwo` has one more integer bit than `bi`, as in casper_library, because the
components of `b · w` can exceed those of `b`. This is why `butterfly_direct`
sizes its b-leg adders one bit wider for `twiddle_general` than for the other
twiddle variants.

## Latency

`LATENCY = CG_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY` on every
output, as in Simulink:

| `N_COEFFS` | `CG_LATENCY` | `LATENCY` |
|------------|--------------|-----------|
| > 1 (table) | `BRAM_LATENCY + ADD_LATENCY + CONV_LATENCY + 2` | `BRAM_LATENCY + MULT_LATENCY + 2·ADD_LATENCY + 2·CONV_LATENCY + 2` |
| 1 (constant) | 0 | `MULT_LATENCY + ADD_LATENCY + CONV_LATENCY` |

`CG_LATENCY` with a table is the `cosin` lookup latency: `bram_latency`, then
`mux + add + conv` for the address manipulation and `mux + neg` for the
inversion, with `coeff_gen`'s `mux_latency = 1` and `neg_latency = 0`
(`coeff_gen_init.m:452`; `cosin_init.m:240, 917, 1018`). The latency
therefore differs from the `1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY`
of [`twiddle_coeff_0`](twiddle_coeff_0.md) and
[`twiddle_coeff_1`](twiddle_coeff_1.md), as in casper.
