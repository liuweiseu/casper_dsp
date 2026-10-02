# twiddle_stage_2

## Description

A twiddle stage for `Coeffs = [0 1]` with `StepPeriod = FFTSize − 2`: w
alternates between 1 and −j. It corresponds to casper_library's
`twiddle_stage_2`, which `butterfly_direct` selects for exactly that case. The
behavior below was derived from `twiddle_stage_2_init.m`:

- `sync_in` is delayed by `bram_latency`. It then clears an
  `FFTSize − 1`-bit free-running counter. The counter's MSB (`Slice`) is the
  select signal `sel`.
- `mux0` produces the real part of `bwo` and chooses between the delayed real
  and imaginary lanes. `mux1` produces the imaginary part and chooses between
  the delayed imaginary lane and the negated real lane (`bus_negate`,
  saturating).
- The delays in front of the two muxes line up every path.

The result is:

| `sel` | `bwo` | w |
|-------|-------|---|
| 0 | `( bi_re,  bi_im)` | 1 |
| 1 | `( bi_im, −bi_re)` | −j |

The counter restarts at 0 on the first sample after a sync pulse. The first
`2^(FFTSize−2)` samples of each frame therefore use w = 1, and the next
`2^(FFTSize−2)` use w = −j.

This module produces the same result with repo primitives:
1. `bi` and `sync` are delayed by `BRAM_LATENCY` ([`pipeline`](../../Delays/pipeline.md)).
2. The delayed sync clears a [`counter`](../../BasicModules/counter.md).
3. The real lane is negated ([`negate`](../../Bus/negate.md), `OVERFLOW = 1`).
4. Each output part is selected by a [`multiplexer`](../../BasicModules/multiplexer.md)
   with `LATENCY = MULT_LATENCY + CONV_LATENCY + ADD_LATENCY`.

Every leg (`ai → ao`, `bi → bwo`, `sync`) has latency
`BRAM_LATENCY + MULT_LATENCY + CONV_LATENCY + ADD_LATENCY`. This formula uses
`BRAM_LATENCY`, unlike `twiddle_coeff_0`/`twiddle_coeff_1`, which use a fixed
1. `bwo` keeps the input width and binary point.

## Parameters

| Parameter         | Default | Description |
|-------------------|---------|-------------|
| `N_INPUTS`        | 1       | Number of complex lanes |
| `FFT_SIZE`        | 5       | casper `FFTSize` (≥ 2); w switches every `2^(FFT_SIZE−2)` samples |
| `INPUT_BIT_WIDTH` | 18      | Lane word width (signed) |
| `BIN_PT_IN`       | 17      | Binary point of the lanes |
| `ADD_LATENCY`     | 1       | Enters `LATENCY` |
| `MULT_LATENCY`    | 2       | Enters `LATENCY` |
| `BRAM_LATENCY`    | 2       | Enters `LATENCY` (sync / data pre-delay) |
| `CONV_LATENCY`    | 2       | Enters `LATENCY` |

**Declared but not implemented:** `ASYNC` and `FLOATING_POINT` must be 0.
`FLOAT_TYPE`, `EXP_WIDTH` and `FRAC_WIDTH` are ignored. The defaults follow
casper_library's mask.

## Ports

The ports are the same as [`twiddle_pass_through`](twiddle_pass_through.md).
All outputs are delayed by `LATENCY`.
