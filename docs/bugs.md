# mlib_devel library bugs

Bugs in the casper_library (mlib_devel) found while building Simulink
models of the casper_dsp blocks for comparison with the HDL. They are
library bugs, not HDL bugs. The HDL implements the intended casper
behaviour in every case below.

**Environment:** mlib_devel branch `scilab-dev-ai`, HEAD `c914cf04e`;
MATLAB R2021a Update 8; Vivado / Model Composer 2021.1.

| # | Bug | Affected blocks | Status |
|---|-----|-----------------|--------|
| 1 | `butterfly_direct_init` passes float parameters that `twiddle_coeff_1` does not have | `butterfly_direct` with `Coeffs = [1]`, `fft_direct` with `map_tail` off | Confirmed in MATLAB R2021a |
| 2 | `twiddle_coeff_1_init` sets `latency` on `bus_negate`, renamed `csp_latency` | `twiddle_coeff_1` (any use) | Confirmed in MATLAB R2021a |
| 3 | `twiddle_coeff_1_init` leaves `bus_negate` in floating-point mode | `twiddle_coeff_1` (any use) | From source only (masked by bug 2) |
| 4 | `fft_direct_init` sizes the output `bus_expand` with `*` instead of `+` | `fft_direct` with `bitgrowth` on | From source only |

Bugs 1–3 all concern `twiddle_coeff_1`, the twiddle for `w = −j`. They
stack: bug 1 stops `butterfly_direct` before `twiddle_coeff_1_init` runs,
bug 2 stops `twiddle_coeff_1_init` itself, and bug 3 would remain after
fixing bug 2. With this mlib_devel, `twiddle_coeff_1` cannot be built in
any configuration.

## 1. butterfly_direct passes float parameters to twiddle_coeff_1

**Affected code:** `casper_library/butterfly_direct_init.m:297-304`
(parameter list), used by the `reuse_block` call at
`butterfly_direct_init.m:342-343`.

**Symptom:**

```
Simulink:Commands:ParamUnknown: twiddle_coeff_1 block (mask) does not have a parameter named 'floating_point'
```

raised at `butterfly_direct_init.m:342`.

**Trigger:** the butterfly's `Coeffs` is exactly `[1]` (one coefficient,
index 1), so `butterfly_direct_init.m:208-209` selects `twiddle_coeff_1`.
Callers produce this only in these cases:
- `fft_direct` with `map_tail = 'off'` and `FFTSize ≥ 2`. Butterfly `u` of
  each stage then gets `Coeffs = [u]` (`fft_direct_init.m:348-351`).
- `fft_direct` with `map_tail = 'on'`, `LargerFFTSize = FFTSize` and
  `StartStage = 1`, whose one-element coefficient lists are the same as
  with `map_tail` off.

**Root cause:** when `twiddle_type` is `'twiddle_coeff_1'`, the parameter
list includes `floating_point`, `float_type`, `exp_width` and
`frac_width`. The `twiddle_coeff_1` mask (`casper_library_ffts_twiddle.slx`,
root block SID 8) has only `n_inputs`, `input_bit_width`, `bin_pt_in`,
`add_latency`, `mult_latency`, `bram_latency`, `conv_latency` and `async`;
no library version ever had the float parameters. `reuse_block`
(`reuse_block.m:51`) passes them to `add_block`, which fails, and
`dump_and_rethrow` rethrows the error.

**Origin:** `16592b8da` (Andrewvdb, 2018-07-04) added the four lines after
the closing `};` of the list, where they had no effect. `53ff4f39d`
(Andrewvdb, 2018-07-10) moved the `};`, which made them effective.
`d3d63bb03` (gcallanan, 2018-11-02) merged the floating-point FFT branch
into the mainline.

**Impact on casper designs:** none in practice. `fft_stage_n` (biplex,
used by `biplex_core`, `fft_biplex*`, `fft`, `fft_wideband_real`) gives
its butterflies `[0]`, `[0 1]` or longer lists, and `fft_direct` with
`map_tail = 'on'` (the mask default, and what `fft_init.m:275` and
`fft_wideband_real_init.m:400` pass) gives lists of
`2^(LargerFFTSize−FFTSize)` coefficients. Only a standalone `fft_direct`
with `map_tail` off reaches `twiddle_coeff_1`. The test model
`Tests/butterfly_direct_coeff_1_test.mdl` dates from 2010 and predates
the change.

**Confirmed in MATLAB R2021a:** the specs `butterfly_direct_2`
(`N_COEFFS = 1`, `COEFF_0 = 1`) and `fft_direct_0/1/2/4` (`MAP_TAIL = 0`,
`FFT_SIZE` 2–4) failed with the error above. `fft_direct_3`
(`MAP_TAIL = 0`, `FFT_SIZE = 1`) and `fft_direct_5` (`MAP_TAIL = 1`) built.

**Suggested fix:** in `butterfly_direct_init.m:297-304`, remove
`floating_point`, `float_type`, `exp_width` and `frac_width` from the
`twiddle_coeff_1` branch. Adding the four parameters to the
`twiddle_coeff_1` mask would also work, but only together with float
support in `twiddle_coeff_1_init.m` (see bug 3).

## 2. twiddle_coeff_1 sets latency on bus_negate

**Affected code:** `casper_library/twiddle_coeff_1_init.m:74-79`
(the `'latency', latency_s` argument is on line 78).

**Symptom:**

```
Simulink:Libraries:CannotChangeLinkedBlkParam: Unable to change parameter 'Latency' of block '.../twiddle_coeff_1/negate_real' because it is a linked block.
```

raised at `twiddle_coeff_1_init.m:74` (from `reuse_block.m:51`).

**Trigger:** any `twiddle_coeff_1` with `n_inputs ≠ 0`, whatever the other
parameter values. It is the first error of a standalone `twiddle_coeff_1`;
through `butterfly_direct`, bug 1 fails first.

**Root cause:** `negate_real` is a link to `casper_library_bus/bus_negate`.
The library stores `twiddle_coeff_1` empty (its default `n_inputs = 0`
makes the init call `clean_blocks`), so the init creates `negate_real`
with `add_block`; this is not a stale link in the `.slx` file. The init
passes `'latency'`, but `bus_negate` has no such mask parameter: commit
`f343a3933` (gcallanan, 2018-10-26, R2016b → R2018b update) renamed it
to `csp_latency` (`bus_negate_init.m:12, 38`). The name then appears to
resolve to a built-in `Latency` block parameter, which cannot be changed
on a linked block (inferred from the error text).

**Origin:** `f343a3933` updated the other `bus_negate` callers
(`complex_conj_init.m:114-120`, `twiddle_stage_2_init.m:137-156`) but not
`twiddle_coeff_1_init.m`, which was last changed in `e6ac7563d` (2013).

**Impact on casper designs:** the same as bug 1. `twiddle_coeff_1` is only
reached through `butterfly_direct` with `Coeffs = [1]`.

**Confirmed in MATLAB R2021a:** all three standalone `twiddle_coeff_1`
specs failed with the error above.

**Suggested fix:** in `twiddle_coeff_1_init.m:78`, replace
`'latency', latency_s` with `'csp_latency', latency_s`.

## 3. twiddle_coeff_1 leaves bus_negate in floating-point mode

**Affected code:** `casper_library/twiddle_coeff_1_init.m:74-79`.

**Symptom:** none observed, because bug 2 stops the init at the same
call. Once bug 2 is fixed, `negate_real` would be built as a
floating-point negate inside a fixed-point twiddle.

**Trigger:** any `twiddle_coeff_1`.

**Root cause:** the call does not pass `floating_point`, and the
`bus_negate` library default is `floating_point = 'on'`
(`casper_library_bus.slx`; `casper_library_bus_initialize.m:154`). The
other `bus_negate` callers pass it explicitly (`twiddle_stage_2_init.m:137-157`,
`complex_conj_init.m:114-116`).

**Impact on casper designs:** the same as bug 1.

**Status:** from source only.

**Suggested fix:** pass `'floating_point', 'off'` to `negate_real` (or
the float settings, if float support is added to `twiddle_coeff_1`).

## 4. fft_direct output bus_expand width: `*` instead of `+`

**Affected code:** `casper_library/fft_direct_init.m:228`, used by the
output `bus_expand` blocks at `fft_direct_init.m:236-238`.

```matlab
if strcmp(bitgrowth, 'on'), n_bits = min(max_bits, input_bit_width*FFTSize);
```

**Symptom:** the `out<s><n>` ports are wider than the data they carry.
Example (the earlier casper_dsp test set `fft_direct_1`: `N_STREAMS = 2`,
`FFT_SIZE = 3`, `INPUT_BIT_WIDTH = 16`, `MAX_BITS = 21`, bit growth on):
the outputs are `2·min(21, 48) = 42` bits wide, against
`2·min(21, 16+3) = 38` bits of data.

**Trigger:** `bitgrowth = 'on'` and `input_bit_width + FFTSize < max_bits`
(and `FFTSize ≥ 2`, so that `input_bit_width·FFTSize` is larger). This can
also happen inside `fft` and `fft_wideband_real`, which pass `bitgrowth`
and `max_bits` to their `fft_direct` (`fft_init.m:293-294`,
`fft_wideband_real_init.m:419-420`).

**Root cause:** each stage grows by one bit, so the final width is
`min(max_bits, input_bit_width + FFTSize)`. The stage splits use that
rule (`fft_direct_init.m:470`), but line 228 multiplies. The final
`bus_expand` then slices `2·n_bits`-bit words from a bus of narrower
words. With `n_streams > 1` the streams are cut at the wrong positions.

**Origin:** line 228 dates from the first `fft_direct` versions
(`ed0ef22cd`, Andrew Martens, 2013-07-04; last changed in `3fba31ba5`,
2013-07-12).

**Impact on casper designs:** `fft_direct`, `fft` and `fft_wideband_real`
with bit growth on, when the width is not capped by `max_bits` (with the
mask default `max_bits = 19` and 18-bit data the width is capped and the
bug has no effect).

**Status:** from source only. The port widths come from the casper_dsp
port analysis; the mis-slicing for `n_streams > 1` has not been run in
MATLAB.

**Suggested fix:** in `fft_direct_init.m:228`, use
`min(max_bits, input_bit_width+FFTSize)`.

## How casper_dsp handles these bugs

- **Mapping:** the HDL-Simulink Mapping blocks record the bugs, so that
  exporters do not build the affected configurations
  (`tools/check_simulink_mapping.py`):
  - `rtl/FFTs/butterfly_direct.sv`: an `unsupported` entry
    `when = 'N_COEFFS == 1 && COEFF_0 == 1'`, plus a `deviations` entry.
  - `rtl/FFTs/fft_direct.sv`: an `unsupported` entry
    `when = 'FFT_SIZE >= 2 && (MAP_TAIL == 0 || (LARGER_FFT_SIZE == FFT_SIZE && START_STAGE == 1))'`.
    Bug 4 is a `deviations` entry: the HDL uses the real width
    `min(MAX_BITS, INPUT_BIT_WIDTH + FFT_SIZE)`.
- **Test configurations** (`tests/simulation.toml`): no parameter set
  hits bugs 1–3.
  - `butterfly_direct` set 2 (formerly `Coeffs = [1]`) is now a
    single-coefficient `twiddle_general` (`Coeffs = [3]`) with the same
    other parameters.
  - `fft_direct` sets 0, 1, 2 and 4 (formerly `MAP_TAIL = 0`) now use
    `MAP_TAIL = 1` with `LARGER_FFT_SIZE > FFT_SIZE`. Set 1 keeps bit
    growth, with `MAX_BITS = INPUT_BIT_WIDTH + FFT_SIZE` (19), so bug 4
    does not change its widths.
  - `twiddle_coeff_1` is no longer listed. Its testbench and
    `test_data/FFTs/Twiddle/twiddle_coeff_1/` are kept.
- **Coverage lost:** the HDL `twiddle_coeff_1` (and the
  `N_COEFFS = 1, COEFF_0 = 1` branch of `butterfly_direct`) and
  `fft_direct` with `MAP_TAIL = 0` and `FFT_SIZE ≥ 2` are no longer in the
  regression. The numpy check that a standalone `fft_direct` output is the
  FFT of its input applied only to `MAP_TAIL = 0` sets and is no longer
  run; `fft_wideband_real`'s end-to-end FFT check still covers
  `fft_direct` with `MAP_TAIL = 1`.
