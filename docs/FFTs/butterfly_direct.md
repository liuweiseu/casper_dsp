# butterfly_direct

## Description

A radix-2 FFT butterfly corresponding to casper_library's `butterfly_direct`
(fixed-point, synchronous path). For each of the `N_INPUTS` complex lanes it
computes `a + b·w` and `a − b·w`, where `w` is the twiddle factor. The
structure follows `butterfly_direct_init.m`:

```
a, b, sync ─► twiddle_* ─► ao, bwo ─► adder_subtractor ×4 (a+bw, a−bw; exact)
   ─► shift stage ─► convert_of ×4 ─► apbw, ambw
                                  └─► of (per lane, one cycle later)
```

### Twiddle Selection

The twiddle variant is chosen at elaboration (`generate`), with the same rule
as `butterfly_direct_init.m`. casper's `Coeffs` list is passed as `N_COEFFS`,
`COEFF_0 = Coeffs(1)` and `COEFF_1 = Coeffs(2)`:

| Condition | Twiddle |
|-----------|---------|
| `Coeffs = [0]`, `BIPLEX = 1` | [`twiddle_pass_through`](Twiddle/twiddle_pass_through.md) |
| `Coeffs = [0]`, `BIPLEX = 0` | [`twiddle_coeff_0`](Twiddle/twiddle_coeff_0.md) |
| `Coeffs = [1]` | [`twiddle_coeff_1`](Twiddle/twiddle_coeff_1.md) |
| `Coeffs = [0 1]` and `STEP_PERIOD = FFT_SIZE − 2` | [`twiddle_stage_2`](Twiddle/twiddle_stage_2.md) |
| otherwise | [`twiddle_general`](Twiddle/twiddle_general.md), table from `INIT_FILE` (`scripts/gen_twiddle_coeffs.py` for `Coeffs`) |

### Widths

- **Adder inputs:** `a` is `INPUT_BIT_WIDTH` bits at `BIN_PT_IN`. `bwo` is
  `INPUT_BIT_WIDTH + 1` bits for `twiddle_general` and `INPUT_BIT_WIDTH` bits
  for the other variants. These are the `addsub_b_bitwidth` rules of
  `butterfly_direct_init.m` (casper's `bw = input+3` / `input+2`).
- **Sum and difference:** exact, one bit wider than `bwo`.
- **Outputs:** `INPUT_BIT_WIDTH` bits at `BIN_PT_IN`, or `INPUT_BIT_WIDTH + 1`
  bits with `BITGROWTH = 1` (parameter `N_BITS_OUT`).

### Shifting

| Mode | Behavior |
|------|----------|
| `BITGROWTH = 1` | No shift. The output grows by one bit. |
| `HARDCODE_SHIFTS = 1` | Static. `DOWNSHIFT = 1` halves the result by moving the binary point, not the bits. |
| default (both 0) | Dynamic. `shift = 1` halves the result. |

In dynamic mode:
- The unscaled sum and the halved sum (`bus_norm0` and `bus_scale` + `bus_norm1`
  in casper) are formed exactly.
- A 1-cycle [`multiplexer`](../BasicModules/multiplexer.md) picks one of them.
- `shift` passes through `FAN_LATENCY = max(1, ⌈log2(4·N_INPUTS / MAX_FANOUT)⌉)`
  registers first (casper's `bus_replicate`). The mux therefore uses `shift`
  from `FAN_LATENCY` cycles before the sum reaches it.

[`convert_of`](../Misc/convert_of.md) then rounds to `BIN_PT_IN`
(`QUANTIZATION`) and handles output overflow (`OVERFLOW`).

### Overflow Flag

`of[n] = 1` when any of lane `n`'s four output components (re/im of `a + bw`
and `a − bw`) overflowed in `convert_of`. The flag comes one cycle after the
data, because casper's `munge` + `bus_relational (a != 0)` has latency 1.

### Latency

The data and `sync_out` have latency `TWIDDLE_LATENCY + ADD_LATENCY +
MUX_LATENCY + CONV_LATENCY`. `MUX_LATENCY` is 1 for dynamic shifting and 0
otherwise. `TWIDDLE_LATENCY` depends on the variant:

| Twiddle | `TWIDDLE_LATENCY` |
|---------|-------------------|
| `twiddle_pass_through` | 0 |
| `twiddle_coeff_0`, `twiddle_coeff_1` | `1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY` |
| `twiddle_stage_2`, `twiddle_general` | `BRAM_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY` |

`of` has one more cycle of latency than the data.

## Parameters

| Parameter         | Default     | Description |
|-------------------|-------------|-------------|
| `N_INPUTS`        | 1           | Number of complex lanes |
| `BIPLEX`          | 1           | casper `biplex` (selects pass-through vs `coeff_0` for `Coeffs = [0]`) |
| `FFT_SIZE`        | 6           | casper `FFTSize` |
| `N_COEFFS`        | 32          | `length(Coeffs)` |
| `COEFF_0`         | 0           | `Coeffs(1)` |
| `COEFF_1`         | 16          | `Coeffs(2)` (ignored if `N_COEFFS = 1`) |
| `STEP_PERIOD`     | 1           | casper `StepPeriod` |
| `INIT_FILE`       | `""`        | `twiddle_general` table (only used by that variant) |
| `COEFF_BIT_WIDTH` | 18          | Coefficient width (`twiddle_general`) |
| `INPUT_BIT_WIDTH` | 18          | Lane width (signed) |
| `BIN_PT_IN`       | 17          | Lane binary point (inputs and outputs) |
| `BITGROWTH`       | 0           | `1`: grow one output bit instead of shifting |
| `DOWNSHIFT`       | 0           | Static downshift (with `HARDCODE_SHIFTS = 1`) |
| `HARDCODE_SHIFTS` | 0           | `1`: static shift (`DOWNSHIFT`); `shift` input unused |
| `ADD_LATENCY`     | 1           | Butterfly adders and twiddle adders |
| `MULT_LATENCY`    | 2           | Twiddle multipliers |
| `BRAM_LATENCY`    | 1           | Twiddle coefficient / stage_2 pre-delay |
| `CONV_LATENCY`    | 1           | Output convert and twiddle convert |
| `QUANTIZATION`    | 0           | Output (and `twiddle_general`) rounding: `0`/`1`/`2` as `convert` |
| `OVERFLOW`        | 0           | Output (and `twiddle_general`) overflow: `0`=wrap, `1`=saturate |
| `MAX_FANOUT`      | 4           | Only sets `FAN_LATENCY` |
| `PLATFORM`        | `"GENERIC"` | Passed to `twiddle_general`'s `rom` |

**Declared but not implemented:** `ASYNC` and `FLOATING_POINT` must be 0. These
are ignored: `FLOAT_TYPE`, `EXP_WIDTH`, `FRAC_WIDTH`, `ADD_PIPE_LATENCY`,
`MULT_PIPE_LATENCY`, `COEFFS_BIT_LIMIT`, `COEFF_SHARING`, `COEFF_DECIMATION`,
`COEFF_GENERATION`, `CAL_BITS`, `N_BITS_ROTATION`, `USE_HDL`, `USE_EMBEDDED`,
`DSP48_ADDERS`. `N_BITS_OUT` is derived and should not be overridden.

## Ports

Lane ports are unpacked arrays of `N_INPUTS` words.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a_re`, `a_im`, `b_re`, `b_im` | input | `INPUT_BIT_WIDTH` × `N_INPUTS` | Butterfly inputs |
| `sync_in` | input | 1 | Frame sync (restarts the twiddle schedule) |
| `shift` | input | 1 | Dynamic downshift select |
| `apbw_re`, `apbw_im` | output | `N_BITS_OUT` × `N_INPUTS` | `a + b·w` |
| `ambw_re`, `ambw_im` | output | `N_BITS_OUT` × `N_INPUTS` | `a − b·w` |
| `of` | output | `N_INPUTS` | Per-lane overflow flag (bit `n` = lane `n`), one cycle after the data |
| `sync_out` | output | 1 | `sync_in` delayed by the data latency |
