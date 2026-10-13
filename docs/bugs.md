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
| 4 | `fft_direct_init` sizes the output `bus_expand` with `*` instead of `+` | `fft_direct` with `bitgrowth` on (also inside `fft` and `fft_wideband_real`) | Confirmed in MATLAB R2021a |
| 5 | Stored copies of `bus_expand` still call the deleted `bus_expand_callback` | `cmult` (in `cmac`, `dual_pol_cmac`, `auto_tap`, `baseline_tap`, `xeng`) and other blocks with a stored `bus_expand` copy | Confirmed in MATLAB R2021a |
| 6 | `cosin_init` connects to `add_convert1`, which it does not draw for small tables | `twiddle_general` (via `coeff_gen` → `cosin`) with few coefficient phase steps | Confirmed in MATLAB R2021a |
| 7 | `delay_bram_init` rejects `DelayLen ≤ bram_latency + 1` and empties the block for `DelayLen = 0` | `delay_bram` with `DelayLen ≤ 3` (default `bram_latency` 2), and blocks that use it (e.g. `auto_tap`) | Confirmed in MATLAB R2021a |
| 8 | `bus_mult` passes 'Round  (unbiased: Even Values)' to a Xilinx `Mult`, which does not offer it | `bus_mult` real lanes with `quantization = 2` | Confirmed in MATLAB R2021a |
| 9 | The `complex_conj` library block is saved with `floating_point = 'on'` | `complex_conj` added without setting `floating_point` | Confirmed in MATLAB R2021a |
| 10 | `auto_tap` / `baseline_tap` library blocks hold stale internals that the init skips | `auto_tap` / `baseline_tap` whose mask values equal the stored library values | Confirmed in MATLAB R2021a (`auto_tap`; `baseline_tap` inferred) |
| 11 | `xeng_descramble_4ant`'s `x_cast` overrides parameters inside a library link | `xeng_descramble_4ant` (verified with sets 0, 1 and 2, at simulation time) | Confirmed in MATLAB R2021a |
| 12 | `auto_tap` / `baseline_tap` replace their delay with a portless stored `delay_slr` and lose its lines | `auto_tap`, `baseline_tap` and `xeng` with `use_bram_delay` off | Confirmed in MATLAB R2021a |
| 13 | `cmult_init` delays `dvalid` by the add latency where the convert latency belongs | `cmult` with `async` and `pipelined_enable` on, `conv_latency ≠ add_latency` | Confirmed in MATLAB R2021a |
| 14 | `delay_bram_init` never creates `dout` with `async` on and `bram_latency = 1` | `delay_bram` with `async` on and `bram_latency = 1` | Confirmed in MATLAB R2021a |

**Environment note:** `pfb_coeff_gen_calc.m:57, 72` computes the PFB
window through MATLAB's Python interface (`casper_library/python/window.py`).
MATLAB R2021a supports CPython up to 3.8; with Python 3.14 as `python` on
`PATH` it reports `Python commands require a supported version of CPython`
and `pfb_fir_real` fails. Putting `python3.8` first on `PATH` for the build
fixes it (verified: `pfb_fir_real_0` builds, 15 blocks). This is not an
mlib_devel bug.

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

**HDL trigger:** `FFTs/butterfly_direct`: `N_COEFFS == 1 && COEFF_0 == 1`;
`FFTs/fft_direct`: `FFT_SIZE >= 2 && (MAP_TAIL == 0 || (LARGER_FFT_SIZE == FFT_SIZE && START_STAGE == 1))`

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

**HDL trigger:** `FFTs/Twiddle/twiddle_coeff_1`: `N_INPUTS != 0`;
`FFTs/butterfly_direct`: `N_COEFFS == 1 && COEFF_0 == 1`;
`FFTs/fft_direct`: `FFT_SIZE >= 2 && (MAP_TAIL == 0 || (LARGER_FFT_SIZE == FFT_SIZE && START_STAGE == 1))`

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

**HDL trigger:** `FFTs/Twiddle/twiddle_coeff_1`: `N_INPUTS != 0`;
`FFTs/butterfly_direct`: `N_COEFFS == 1 && COEFF_0 == 1`;
`FFTs/fft_direct`: `FFT_SIZE >= 2 && (MAP_TAIL == 0 || (LARGER_FFT_SIZE == FFT_SIZE && START_STAGE == 1))`

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

**HDL trigger:** `FFTs/fft_direct`: `BITGROWTH != 0 && (INPUT_BIT_WIDTH * FFT_SIZE < MAX_BITS ? INPUT_BIT_WIDTH * FFT_SIZE : MAX_BITS) != (INPUT_BIT_WIDTH + FFT_SIZE < MAX_BITS ? INPUT_BIT_WIDTH + FFT_SIZE : MAX_BITS)`;
`FFTs/fft_wideband_real`: `BITGROWTH != 0 && ((INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS < MAX_BITS ? INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS : MAX_BITS) * N_INPUTS < MAX_BITS ? (INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS < MAX_BITS ? INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS : MAX_BITS) * N_INPUTS : MAX_BITS) != ((INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS < MAX_BITS ? INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS : MAX_BITS) + N_INPUTS < MAX_BITS ? (INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS < MAX_BITS ? INPUT_BIT_WIDTH + FFT_SIZE - N_INPUTS : MAX_BITS) + N_INPUTS : MAX_BITS)`

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

**Confirmed in MATLAB R2021a:** `fft_wideband_real` set 3
(`FFT_SIZE = 6`, `N_INPUTS = 2`, `INPUT_BIT_WIDTH = 12`, `BITGROWTH = 1`,
`MAX_BITS = 22`). Its `fft_direct` gets `FFTSize = 2` and
`input_bit_width = min(22, 12 + 4) = 16`, so the final butterflies carry
`2·min(22, 18) = 36`-bit words while `adebus1_0` slices
`2·min(22, 32) = 44` bits: "Illegal parameterization: Width of slice" and
"Incorrect slice end point" in `fft_direct/adebus1_0/slice1` (simulation
fails at a Gateway Out first; see "Misleading simulation error" below).
The mis-slicing for `n_streams > 1`, and the narrower case
`FFTSize = 1` (`input_bit_width·1 < input_bit_width + 1`, the MSBs are
dropped without an error), are from source only.

**Suggested fix:** in `fft_direct_init.m:228`, use
`min(max_bits, input_bit_width+FFTSize)`.

## 5. Stored bus_expand copies call the deleted bus_expand_callback

**Affected code:** non-linked copies of `bus_expand` stored inside other
libraries, e.g. `cmac/cmult*/a_expand` in `casper_library_correlator.slx`
(`system_855_917.xml` and its siblings). The failing call is
`cmult_init.m:236` (`reuse_block` of `a_expand`), which reaches
`set_param` at `reuse_block.m:138`.

**Symptom:**

```
Simulink:Engine:CallbackEvalErr: Error evaluating 'MaskDialog' callback of bus_expand block (mask) 'cmac_2/cmac/cmult*/a_expand'. Callback string is 'bus_expand_callback();'
```

raised from `reuse_block.m:138`. The parent mask initialization then
fails ("Failed to evaluate mask initialization commands").

**Trigger:** `reuse_block` finds the stored copy and only calls
`set_param` on it. When a dialog parameter changes value, the copy's
`MaskDialog` callback runs and calls the deleted function. It therefore
fails exactly when the requested values differ from the stored ones. For
`cmult` inside `cmac` the stored copy has `outputWidth [4 4 4 4]` and
`outputBinaryPt [3 3 3 3]`, so any data width other than 4 (binary point
other than 3) fails.

**HDL trigger:** none (library save issue: the Simulink builds use the no-op `bus_expand_callback` workaround, so no HDL parameter set is affected).

**Root cause:** `f994adffb` (amartens, 2022-08-31, "removed
bus_expand_callback") deleted `casper_library/bus_expand_callback.m` and
commented the callback out in `casper_library_flow_control.slx`
(`%bus_expand_callback();`, 3 places). Copies of `bus_expand` stored in
other libraries still carry the old, uncommented callback:

| Library | Uncommented `bus_expand_callback();` |
|---------|--------------------------------------|
| `casper_library_correlator.slx` | 30 |
| `casper_library_pfbs.slx` | 6 |
| `casper_library_scopes.slx` | 6 |
| `casper_library_misc.slx` | 3 |

(Counted from the `<Callback>` entries in the `.slx` XML.)

**Origin:** `f994adffb`. It removed the function but re-saved only
`casper_library_flow_control.slx`.

**Impact on casper designs:** any design that changes the widths of these
stored copies hits the error with this mlib_devel, also when the blocks
are used interactively. The removed function
(`f994adffb^:casper_library/bus_expand_callback.m`) only updated the mask
UI (`MaskEnables` / `MaskPrompts`, `LinkStatus` inactive) and, in
'divisions of arbitrary size' mode, synced `outputNum`. `cmult` uses
'divisions of equal size', so the callback has no effect on the built
model.

**Confirmed in MATLAB R2021a:**
- Failed: `cmac` sets 2 (8 bit) and 3 (6/8 bit); `dual_pol_cmac` set 2
  (8 bit); `auto_tap` set 3 (8 bit), `baseline_tap` set 3 (8 bit) and
  `xeng` set 3 (3 bit). All of these contain `dual_pol_cmac` → `cmac` →
  `cmult`.
- Built: the 4-bit sets (`cmac` 0/1/4, `dual_pol_cmac` 0/1 and the 4-bit
  sets of the other modules).
- The `pfb_fir_real` failures are **not** this bug: `pfb_fir_real_0` still
  fails with the workaround below on the path ("Failed to evaluate mask
  initialization commands", no `CallbackEvalErr`). Their cause is still
  unknown.

**Suggested fix:** re-save the four libraries with the callbacks commented
out, as `f994adffb` did for `casper_library_flow_control.slx`, or replace
the stored copies with links to `casper_library_flow_control/bus_expand`.
Not applied here: mlib_devel is left unchanged.

**Workaround (verified in MATLAB R2021a):** a no-op
`function bus_expand_callback() end` in a directory outside mlib_devel,
put on the path for the build with the `MATLABPATH` environment variable
(`MATLABPATH=<dir> create_simulink.sh ...`). With it, `cmac` set 2
(8 bit, previously `CallbackEvalErr`) builds: 17 blocks, 14 lines, no
`CallbackEvalErr` in the log. The no-op does not change the built model,
because the removed function only touched the mask UI and the
'divisions of arbitrary size' mode, which `cmult` does not use.

With the workaround applied to all failing correlator sets:
- Now build: `cmac` sets 2 and 3 (17 blocks), `dual_pol_cmac` set 2 (17),
  `baseline_tap` set 3 (31) and `xeng` set 3 (19).
- Still fails: `auto_tap` set 3 (`N_ANTS = 2`, `N_SIMULTAN = 2`,
  `N_BITS = 8`, `ACC_LEN = 4`, ADD / MULT / BRAM latency 1 / 1 / 1,
  `MULT_TYPE = 0`, `USE_BRAM_DELAY = 1`). The `CallbackEvalErr` is gone, but
  the build now stops with a bare "Failed to evaluate mask initialization
  commands" and no further detail in the log. This is a different cause:
  the `delay_bram` minimum delay check (bug 7), reached through
  `auto_tap_init.m`.

## 6. cosin connects to an add_convert1 it does not draw

**Affected code:** `casper_library/cosin_init.m:184-190` (small-table
fallback), `cosin_init.m:224-226`, and `draw_basic_partial_cycle` at
`cosin_init.m:656-663`.

**Symptom:**

```
Invalid Simulink object name: add_convert1/2
```

raised in `.../twiddle_general/coeff_gen/cosin`, after the warning
`forcing all value storage for small number of points`
(`cosin_init.m:187`).

**Trigger:** `coeff_gen` (inside `twiddle_general`) uses a `cosin` lookup
table for in-order coefficients, or when coefficient generation is off or
forced off (`coeff_gen_init.m:260-263, 308-330`). It passes
`table_bits = log2(length(Coeffs))` and `fraction = multiple_bits`, and
`cosin` computes `full_cycle_bits = table_bits + fraction`. The bug fires
when `full_cycle_bits < 3`. For in-order coefficients `0 … N−1` this is
`FFTSize − StepPeriod < 3`. Example: `twiddle_general` with
`Coeffs = [0 1 2 3]`, `FFTSize = 4`, `StepPeriod = 2`.

**HDL trigger:** `FFTs/Twiddle/twiddle_general`: `N_COEFFS > 1 && FFT_SIZE - STEP_PERIOD < 3`;
`FFTs/butterfly_direct`: `N_COEFFS > 1 && FFT_SIZE - STEP_PERIOD < 3 && !(N_COEFFS == 2 && COEFF_0 == 0 && COEFF_1 == 1 && STEP_PERIOD == FFT_SIZE - 2)`;
`FFTs/fft_direct`: `MAP_TAIL != 0 && LARGER_FFT_SIZE == FFT_SIZE + 1 && FFT_SIZE >= 2`

**Root cause:** for `full_cycle_bits < 3`, `cosin_init.m:184-190` switches
to full storage, and `draw_basic_partial_cycle` returns early
(`cosin_init.m:660-663`, "parameters not sensible so returning") without
drawing `add_convert0` / `add_convert1`. `cosin_init.m:226`
(`add_line(blk,'misci/1','add_convert1/2')`) and the following lines still
connect to `add_convert1`, so `add_line` fails.

**Impact on casper designs:** `fft_stage_n` (biplex) never reaches it: its
stage `s` twiddle has `full_cycle_bits = s ≥ 3`. `fft_direct` with
`map_tail` on reaches it only with 2-entry lists (`LargerFFTSize = FFTSize + 1`),
which `fft_wideband_real` never uses (`FFTSize − n_inputs ≥ 2`). It mainly
affects a standalone `twiddle_general` (or `butterfly_direct`) with a short
coefficient period.

**Confirmed in MATLAB R2021a:** the `twiddle_general` set 1 model
(`N_INPUTS = 2`, `FFT_SIZE = 4`, `STEP_PERIOD = 2`) failed with the error
above. That model kept the library default `Coeffs = [0 1]` (the Coeffs
mask parameter is not exported yet), not the set's `[0 1 2 3]`; both give
`full_cycle_bits = FFTSize − StepPeriod = 2`. The root cause is from
source.

**Suggested fix:** in `cosin_init.m`, skip the `add_convert1` connections
(`:226-231` and the later `add_convert1` lines) when `full_cycle_bits < 3`,
or have `draw_basic_partial_cycle` draw a pass-through `add_convert1` in
that case.

## 7. delay_bram cannot be built for short delays

**Affected code:** `casper_library/delay_bram_init.m:30-34` (`DelayLen = 0`)
and `delay_bram_init.m:40-43` (minimum delay check).

**Symptom:**
- `DelayLen` 1 or 2:
  ```
  Error in '<model>/delay_bram': Failed to evaluate mask initialization commands
  ```
  raised by `delay_bram_init: delay value must be greater than BRAM Latency + 1`.
- `DelayLen` 0: the block is left empty, so connecting it fails
  (`delay_bram/1: block 'delay_bram' has 0 input port(s), not 1`, reported
  by the model builder).

**Trigger:**
- `DelayLen ≤ bram_latency + 1`, i.e. `DelayLen ≤ 3` with the library
  default `bram_latency = 2`. `DelayLen = 1` fails for any `bram_latency`.
- `DelayLen = 0`.

**HDL trigger:** `Delays/delay_bram`: `DELAY_LEN <= BRAM_LATENCY + 1`;
`Correlator/auto_tap`: `USE_BRAM_DELAY != 0 && ACC_LEN * ((N_ANTS + 1) / 2) - N_ANTS / 2 <= (BRAM_LATENCY > 2 ? BRAM_LATENCY : 2) + 1`;
`Correlator/xeng`: `USE_BRAM_DELAY != 0 && ACC_LEN * ((N_ANTS + 1) / 2) - N_ANTS / 2 <= (BRAM_LATENCY > 2 ? BRAM_LATENCY : 2) + 1`;
`Correlator/baseline_tap`: `USE_BRAM_DELAY != 0 && ACC_LEN <= (BRAM_LATENCY > 2 ? BRAM_LATENCY : 2) + 1`;
`PFBs/tap_real`: `DELAY <= BRAM_LATENCY + 1`;
`PFBs/first_tap_real`: `2 ** (PFB_SIZE - N_INPUTS) * N_POL_BLOCKS <= BRAM_LATENCY + 1`;
`PFBs/pfb_fir_real`: `2 ** (PFB_SIZE - N_INPUTS) * N_POL_BLOCKS <= BRAM_LATENCY + 1`;
`FFTs/Internal/bi_real_unscr_4x`: `BRAM_DELAYS != 0 && 2 ** (FFT_SIZE - 1) <= BRAM_LATENCY + 1`

**Root cause:**
- `delay_bram` is a counter-addressed RAM. With `DelayLen = bram_latency + 1`
  the counter would drive the RAM with a maximum value of 0 (comment at
  `delay_bram_init.m:37-39`), so the init rejects short delays instead of
  falling back to a register delay.
- For `DelayLen = 0`, the "default state, do nothing" branch
  (`delay_bram_init.m:29-34`) calls `clean_blocks` and returns. It removes
  the ports as well, so the block cannot serve as a zero delay.

**Origin:** long-standing design checks in `delay_bram_init.m`, not a
recent regression.

**Impact on casper designs:** any block that sizes a `delay_bram` from its
own parameters fails for short delays. `auto_tap` reaches the same check
through `auto_tap_init.m:61-68` (see its `unsupported` entry). Designs
that use `delay_bram` only for long delays are unaffected.

**Confirmed in MATLAB R2021a:** `delay_bram` sets 0 (`DELAY_LEN = 2`) and
5 (`DELAY_LEN = 1`) failed with the minimum-delay error, and set 6
(`DELAY_LEN = 0`) left the block without ports. The other sets (5, 16, 100
and 1000) built.

**Suggested fix:** for `DelayLen = 0`, connect `din` to `dout` instead of
clearing the block; for `DelayLen ≤ bram_latency + 1`, fall back to a
register delay (as `delay_srl`) instead of erroring.

## 8. bus_mult rounds to even inside a Xilinx Mult

**Affected code:** `casper_library/bus_mult_init.m:634-641` (quantization
mapping) and `bus_mult_init.m:683-686` (the real-lane `xbsIndex_r4/Mult`).

**Symptom:**

```
Invalid setting in Xilinx Multiplier Block 'mult1' for parameter 'quantization'
```

(the `bus_mult` mask initialization then fails).

**Trigger:** `bus_mult` with real lanes (`cmplx_a` / `cmplx_b` off) and
`quantization = 2` (round half to even).

**HDL trigger:** `Bus/multiplier`: `QUANTIZATION == 2`

**Root cause:** `bus_mult_init.m:640` maps quantization 2 to
`'Round  (unbiased: Even Values)'` and passes it to `xbsIndex_r4/Mult` with
`precision = 'User Defined'`. In Vivado 2021.1 (`xbsIndex_r4.slx`) the
quantization popup of `Mult` (and of `AddSub` and `CMult`) offers only
`'Truncate'` and `'Round  (unbiased: +/- Inf)'`; `Convert` offers all three.

**Origin:** `970d1b3cf` (andrewvanderbyl, 2019-10-01, "Updated bus_mult to
allow Rounding: Unbiased Even Values") added the option to the mapping
without a block that supports it.

**Impact on casper designs:** only `bus_mult` real lanes with
quantization 2. Complex lanes use `cmult`, which multiplies at full
precision and rounds in an `xbsIndex_r4/Convert` (`cmult_init.m:605-613`),
so `twiddle_general` (complex `bus_mult`) and `cmult` work with round to
even. `pfb_fir_taps` passes quantization 0.

**Confirmed in MATLAB R2021a:** `multiplier` set 1 (Fix_18_17 × Fix_18_17
→ Fix_18_17, `QUANTIZATION = 2`, `OVERFLOW = 1`, `MULT_LATENCY = 3`) failed
with the error above.

**Suggested fix:** for quantization 2, build the real lane as `cmult`
does: a full-precision `Mult` followed by an `xbsIndex_r4/Convert`, whose
popup has `'Round  (unbiased: Even Values)'` (verified in the 2021.1
`xbsIndex_r4.slx`). Alternatively, remove option 2 from `bus_mult`'s
quantization.

## Misleading simulation error (bugs 4, 9, 10 and 12)

Bugs 4, 9, 10 and 12 build without an error, but simulating the model
(`run_simulation`) fails at a Gateway Out with an unrelated message:

```
The S-function 'sysgen' in '<model>/gw_out_<port>' has specified the option SS_OPTION_PORT_SAMPLE_TIMES_ASSIGNED and specified inherited for sample time number 0. ...
```

The real error shows only after the `gw_out_*` blocks are commented out
and the model is compiled. System Generator then reports the real error
in `sysgen_error.log`: "Incorrect slice end point / Slice endpoints must
lie between the LSB and MSB" (bugs 4, 9 and 10, during "Rate and Type
Error Checking") or "Undriven input port" (bug 12) inside the block.

## 9. complex_conj library block is saved with floating_point = 'on'

**Affected code:** `casper_library_misc.slx/complex_conj`
(`system_root.xml`, SID 415), with `complex_conj_init.m` (the
`if floating_point == 1` branch).

**Symptom:** the simulation fails at `gw_out_z_conj` with the sample time
error above. The real error is an incorrect slice end point in
`complex_conj/munge_in/split/slice1`.

**Trigger:** a freshly added `complex_conj` whose `floating_point` is not
set.

**HDL trigger:** none (library save issue: the mapping sets `floating_point = 'off'` explicitly, so no export reaches it).

**Root cause:** the saved mask value is `floating_point = 'on'`, while
the defaults listed in `complex_conj_init.m` are `'off'`. The block
therefore builds in single-precision float: `complex_conj_init.m` sets
`n_bits = exp_width + frac_width = 32` and `bin_pt = 0`.
`munge_in/split/slice1` then slices out of range against a fixed-point
input (`complex_conj_0`: a 36-bit bus, 2 × 18).

**Impact on casper designs:** any design that drops in `complex_conj` and
relies on the mask defaults. Of the 18 mapped casper_dsp blocks with a
`floating_point` mask parameter, only `complex_conj` and `bus_negate`
are saved with `'on'` (for `bus_negate` see bug 3).

**Confirmed in MATLAB R2021a:** all 4 `complex_conj` sets failed. With
`floating_point = 'off'` all 4 build and simulate (129 samples each).

**Suggested fix:** re-save the library block with `floating_point = 'off'`,
matching the defaults in `complex_conj_init.m`.

## 10. auto_tap / baseline_tap hold stale internals that the init skips

**Affected code:** `casper_library_correlator.slx/auto_tap` and
`baseline_tap`; `auto_tap_init.m:24` (the early return) and
`auto_tap_init.m:45-59` (the skipped `dual_pol_cmac` setup).

**Symptom:** the simulation fails with the sample time error above
(`gw_out_a_del_out` for `baseline_tap`). The real error is an incorrect
slice end point in `dual_pol_cmac/Slice11`.

**Trigger:** the mask values of the added block equal the values stored
in the library. `auto_tap` set 0 and `baseline_tap` set 0 failed.

**HDL trigger:** none (stale library state: the mapping writes `acc_len` as `'<ACC_LEN>*1'`, so the init always runs).

**Root cause (verified for `auto_tap` in MATLAB):**
- The saved mask values of the library `auto_tap` are `n_ants` 4,
  `n_simultan` 2, `n_bits` 4, `acc_len` 64, `add_latency` 1,
  `mult_latency` 2, `bram_latency` 2, `mult_type` 0,
  `use_bram_delay` 1. These are exactly `auto_tap` set 0.
- Its `UserData.state` hash (69913246) matches these values.
- The stored internal `dual_pol_cmac` is stale: `acc_len` 128,
  `mult_latency` 1, `multiplier_implementation` 'embedded multiplier core'.
- When the block is added with these values,
  `auto_tap_init.m:24` (`if same_state(blk, varargin{:}), return, end`)
  returns early. `dual_pol_cmac` is never re-parameterised;
  `auto_tap_init.m:45-59` would set `acc_len` 64, `mult_latency` 2 and
  'behavioral HDL'.
- `dual_pol_cmac` then expects a 128-bit `acc_in` (4 × 16 × 2), while the
  port carries 120 bits (4 × 15 × 2), so `dual_pol_cmac/Slice11` goes out
  of range.

`baseline_tap` shows the same symptom and the same fix works. Its library
values were not dumped, so the cause there is inferred.

**Experiment:**
- Added with `acc_len` `'64'`: the internals stay stale.
- Added with `acc_len` `'2^6'`, or with 65 and then changed to 64: the
  init runs, and `dual_pol_cmac` gets `acc_len` 64 and `mult_latency` 2.

**Impact on casper designs:** only blocks whose mask values equal the
stored library values. Any other configuration runs the init.

**Confirmed in MATLAB R2021a:** `auto_tap` set 0. `baseline_tap` set 0
fails the same way.

**Workaround (verified in MATLAB R2021a):** give `acc_len` as an equivalent
expression: `'2^6'` or `'64*1'` for `auto_tap_0`, `'2^5'` or `'32*1'` for
`baseline_tap_0`. `same_state` compares the strings, so the init runs.
Both sets then build and simulate (1085 and 573 samples). casper_dsp
writes `acc_len` as `'<ACC_LEN>*1'` (see the handling section below).

**Suggested fix:** re-save the library blocks after running their init, or
make `same_state` also check that the stored contents match.

## 11. xeng_descramble_4ant: x_cast overrides parameters inside a library link

**Affected code:** `casper_library_correlator.slx/xeng_descramble_4ant`
and its `x_cast` mask initialization.

**Symptom:** `xeng_descramble_4ant_0` builds, but the simulation fails:

```
Error in '<model>/xeng_descramble_4ant/x_cast': Failed to evaluate mask initialization commands.
Caused by: Attempting to override parameters of '<model>/xeng_descramble_4ant/x_cast' which is inside a library link
```

**Trigger:** simulating any `xeng_descramble_4ant` whose block is still a
resolved library link.

**HDL trigger:** none (library link issue: the mapping places the block with `break_link`).

**Root cause:** the `x_cast` mask initialization sets parameters of blocks
inside itself while the enclosing `xeng_descramble_4ant` is still a
resolved library link. The init code was not analysed further.

**Impact on casper designs:** `xeng_descramble_4ant`. The plain
`xeng_descramble` (`xeng_descramble_0`) simulates fine.

**Confirmed in MATLAB R2021a:** `xeng_descramble_4ant` sets 0, 1 and 2.

**Workaround (verified in MATLAB R2021a with sets 0, 1 and 2):** set
`LinkStatus` to `'inactive'` on the top `xeng_descramble_4ant` block when
it is added. All three sets then build and simulate (set 0: 5596 samples).
casper_dsp records this as `break_link` (see the handling section below).

**Suggested fix:** the `x_cast` / `xeng_descramble_4ant` mask code should
break the link (`set_param(gcb, 'LinkStatus', 'inactive')`) before it
modifies the contents, as the `dual_pol_cmac` mask code does.

## 12. auto_tap / baseline_tap lose the delay lines with use_bram_delay off

**Affected code:** `casper_library/auto_tap_init.m:69-72` and
`casper_library/baseline_tap_init.m:86-89` (the `use_bram_delay` off
branch).

**Symptom:** the simulation fails at a Gateway Out (see above). The real
error is "Undriven input port" at `<model>/auto_tap/delay/dly`
(`auto_tap`), at `baseline_tap/delay/dly` and `baseline_tap/Delay3`
(`baseline_tap`), and at `xeng/auto_tap/delay/dly`,
`xeng/baseline_tap1/Delay3` and `Delay8` (`xeng`).

**Trigger:** `use_bram_delay = 0`, whatever the other parameters. `xeng`
passes its `use_bram_delay` to its `auto_tap` and `baseline_tap` blocks
(`xeng_init.m:84-104`).

**HDL trigger:** `Correlator/auto_tap`: `USE_BRAM_DELAY == 0`;
`Correlator/baseline_tap`: `USE_BRAM_DELAY == 0`;
`Correlator/xeng`: `USE_BRAM_DELAY == 0`

**Root cause:** the init swaps the block named `delay` with
`replace_block(blk, 'Name', 'delay', 'casper_library_delays/delay_slr',
'noprompt')`. The library copy of `delay_slr` is stored with
`DelayLen = 0`, an empty shell without ports, so `replace_block` drops all
lines to and from the delay. The following `set_param(..., 'DelayLen', ...)`
brings the ports back, but nothing reconnects them. The `use_bram_delay`
on branch replaces it with `delay_bram`, which keeps its ports, so it is
unaffected.

**Impact on casper designs:** every `auto_tap`, `baseline_tap` and `xeng`
built with `use_bram_delay` off (SRL delays instead of BRAM).

**Confirmed in MATLAB R2021a:**
- `auto_tap` set 1 (`N_ANTS = 4`, `N_SIMULTAN = 2`, `N_BITS = 4`,
  `ACC_LEN = 8`, `USE_BRAM_DELAY = 0`);
- `baseline_tap` set 2 (`N_ANTS = 6`, `ANT_SEP = 3`, `ACC_LEN = 4`,
  `USE_BRAM_DELAY = 0`);
- `xeng` set 1 (`N_ANTS = 4`, `DEMUX_FACTOR = 2`, `ACC_LEN = 16`,
  `USE_BRAM_DELAY = 0`).

**Suggested fix:** re-save `casper_library_delays` with a `delay_slr` that
has ports (`DelayLen ≥ 1`), or, in the init scripts, set `DelayLen` and
reconnect the delay's lines after `replace_block` (or use `reuse_block`
with explicit `add_line` calls).

## 13. cmult: dvalid uses the add latency instead of the convert latency

**Affected code:** `casper_library/cmult_init.m:522-547` and `:615-627`
(the `async`, `pipelined_enable` on branch).

**Symptom:** with `async` on, `dvalid` does not line up with `ab`: it comes
`conv_latency − add_latency` cycles off.

**Trigger:** `async = 'on'`, `pipelined_enable = 'on'` (the mask default)
and `conv_latency ≠ add_latency`.

**HDL trigger:** `Multipliers/cmult`: `ASYNC != 0 && PIPELINED_ENABLE != 0 && CONV_LATENCY != ADD_LATENCY`

**Root cause:** the init creates the last `dvalid` Delay `den` with
`'latency', num2str(latency)` while `latency` still holds `add_latency`
(set at `:522-523` for `en_replicate2`); it only assigns
`latency = conv_latency` after the block is created (`:623-627`). So
`dvalid` = `en` delayed `in_latency + mult_latency + 2·add_latency`,
while the data takes `in_latency + mult_latency + add_latency +
conv_latency`.

**Impact on casper designs:** no casper_library block triggers it
(checked in all `*_init.m` and the stored `.slx` blocks). `bus_mult` does
not pass `async` (default off), `feedback_osc` sets `async` off, and the 5
`cmult` instances in `casper_library_correlator` `cmac` have `async` off
(add latency 1, conv latency 0). Only user designs that place `cmult`
directly with `async` on and `conv_latency ≠ add_latency` are affected.

**Confirmed in MATLAB R2021a:** async batch 1, `cmult` set 0
(`in_latency 1`, `mult_latency 2`, `add_latency 1`, `conv_latency 2`):
`dvalid` = `en` delayed 5, not 6.

**Suggested fix:** set `latency = conv_latency` before creating `den`.

**HDL:** implements the intended behaviour (`dvalid` aligned with `ab`);
sets that trigger the bug are excluded from the Simulink comparison.

## 14. delay_bram: no output port with async on and bram_latency = 1

**Affected code:** `casper_library/delay_bram_init.m:104-158` (the
`async` branch).

**Symptom:** the block has no output port, so the model cannot be built:
`delay_bram/1: block 'delay_bram' has 0 output port(s), not 1`.

**Trigger:** `async = 'on'` with `bram_latency = 1`.

**HDL trigger:** `Delays/delay_bram`: `ASYNC != 0 && BRAM_LATENCY == 1`

**Root cause:** in the async branch the RAM has latency 1, followed by
`bram_latency − 1` gated Delays. The loop that creates those Delays also
creates and wires the `dout` port (`:131-157`); for `bram_latency = 1` it
runs zero times, so `dout` is never created.

**Impact on casper designs:** `delay_bram` with `async` on and
`bram_latency = 1`.

**Confirmed in MATLAB R2021a:** async batch 1, `delay_bram` set 2
(`DelayLen 16`, `bram_latency 1`).

**Suggested fix:** create `dout` outside the loop and wire it to the RAM
output when `bram_latency = 1`.

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
- **Bug 4:** `unsupported` entries on `rtl/FFTs/fft_direct.sv`
  (`BITGROWTH != 0` and `min(MAX_BITS, INPUT_BIT_WIDTH·FFT_SIZE)` ≠
  `min(MAX_BITS, INPUT_BIT_WIDTH + FFT_SIZE)`) and on
  `rtl/FFTs/fft_wideband_real.sv` (the same rule for the inner
  `fft_direct`: `FFTSize = N_INPUTS`, input width
  `min(MAX_BITS, INPUT_BIT_WIDTH + FFT_SIZE − N_INPUTS)`). They skip
  `fft_wideband_real` set 3; no `fft_direct` set is affected.
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
- **Bug 5:** no change to casper_dsp; it is not an HDL issue. The
  Simulink builds use the no-op `bus_expand_callback.m` workaround above
  (`/data/casper/tools/plugins-demo2/matlab_compat/bus_expand_callback.m`,
  outside mlib_devel, on `MATLABPATH`). All correlator sets that bug 5
  broke now build, except `auto_tap` set 3, which hits bug 7 (the
  `delay_bram` minimum delay) and is covered by the `auto_tap`
  `unsupported` entry.
- **Bug 6:** `unsupported` entries on `rtl/FFTs/Twiddle/twiddle_general.sv`
  (`N_COEFFS > 1 && FFT_SIZE - STEP_PERIOD < 3`, assuming in-order
  coefficients; the HDL holds the list only in `INIT_FILE`) and on
  `rtl/FFTs/fft_direct.sv`
  (`MAP_TAIL != 0 && LARGER_FFT_SIZE == FFT_SIZE + 1 && FFT_SIZE >= 2`).
- **Bug 7:** two `unsupported` entries on `rtl/Delays/delay_bram.sv`:
  `DELAY_LEN == 0` and `DELAY_LEN >= 1 && DELAY_LEN <= 3` (the latter
  assumes the default `bram_latency = 2`, which the HDL does not set). They
  skip `delay_bram` sets 0, 5 and 6; the HDL tests still run. The
  `auto_tap` / `xeng` entries below are the same check, reached through
  `auto_tap_init.m`.
- **Bug 8:** an `unsupported` entry on `rtl/Bus/multiplier.sv`
  (`QUANTIZATION == 2`). It skips `multiplier` set 1; the HDL test still
  runs.
- **Bug 9:** the mapping sets `floating_point = 'off'` explicitly:
  `[mask_set.floating_point] value = 'off'` in `complex_conj` (required),
  `negate`, `adder_subtractor`, `multiplier`, `bi_real_unscr_4x`,
  `hilbert`, `mirror_spectrum`, `fft_unscrambler`, `fft_biplex_real_4x`
  and `fft_direct`. The other 8 blocks map it through their
  `FLOATING_POINT` parameter (HDL default 0 = `'off'`). A later re-save of
  a library block therefore cannot switch an export to float.
- **Bug 10:** `rtl/Correlator/auto_tap.sv` and `baseline_tap.sv` map
  `ACC_LEN` with `template = '{ACC_LEN}*1'`, so the exported `acc_len` is
  an expression such as `'64*1'` and the init always runs. Verified with
  `auto_tap_0` (`'64*1'`) and `baseline_tap_0` (`'32*1'`). `xeng` needs no
  entry: `xeng_init.m:84-99` passes the inner taps `num2str(acc_len)`, so a
  template on the `xeng` mask would not reach them, and all `xeng` sets
  build.
- **Bug 11:** `rtl/Correlator/xeng_descramble_4ant.sv` has a top-level
  `break_link` entry; exporters then place the block with `LinkStatus`
  `'inactive'`. Verified with `xeng_descramble_4ant` sets 0, 1 and 2.
- **Bug 13:** not reproduced: `rtl/Multipliers/cmult.sv` delays `dvalid` by
  `IN_LATENCY + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY`, aligned with
  `ab`. `cmult` set 10 (`ADD_LATENCY 1`, `CONV_LATENCY 2`) exercises the
  fix and is excluded from the Simulink comparison by its **HDL trigger**.
- **Bug 14:** an `unsupported` entry `ASYNC != 0 && BRAM_LATENCY == 1` on
  `rtl/Delays/delay_bram.sv`.
- **Bug 12:** `unsupported` entries `USE_BRAM_DELAY == 0` on
  `rtl/Correlator/auto_tap.sv`, `baseline_tap.sv` and `xeng.sv`. They skip
  `auto_tap` set 1, `baseline_tap` set 2 and `xeng` set 1.
- **Simulink parameter limits:** other configurations that the init scripts
  reject are also `unsupported` entries (each with the init-script
  reference in its `reason`):
  - `twiddle_stage_2` with `MULT + ADD + CONV` latency 0 (a delay of −1),
    and the modules that reach it: `butterfly_direct`, `fft_stage_n`,
    `biplex_core`, `fft_biplex_real_4x` and `fft_wideband_real`;
  - `auto_tap` and `xeng` when the `delay_bram` delay is not larger than
    `max(BRAM_LATENCY, 2) + 1`, and `tap_real` when `DELAY ≤ BRAM_LATENCY + 1`
    (its stored `delay_bram` gets `DelayLen = delay`; bug 7);
  - `twiddle_general` when `N_COEFFS > 1` is not a power of two
    (`coeff_gen_init.m:281-285`);
  - `scale` when `SCALE_FACTOR` is outside
    `BIN_PT_IN − N_BITS_IN … BIN_PT_IN` (the Xilinx `Scale` output binary
    point must lie within the input word: "Illegal parameterization: Scale
    factor s");
  - `xeng_descramble` with `NUM_ANTS == 4`, where `write_ctrl/Counter2`
    would count from `pivot_pnt` = 9 to `num_elements − 1` = 9 (Xilinx
    `Counter`: "Initial value cannot equal count to value");
  - `adder_subtractor` with `QUANTIZATION == 2`;
  - `fft_wideband_real` and `fft_direct` when `coeff_gen` draws a
    `feedback_osc` with too few phase steps.

  They skip `twiddle_stage_2` set 2, `auto_tap` set 3, `tap_real` set 3,
  `twiddle_general` sets 1 and 3, `scale` sets 3 and 4, `xeng_descramble`
  set 2, `adder_subtractor` set 4 and `fft_wideband_real` set 2; the HDL
  tests of these sets still run.
- **Coverage lost:** the HDL `twiddle_coeff_1` (and the
  `N_COEFFS = 1, COEFF_0 = 1` branch of `butterfly_direct`) and
  `fft_direct` with `MAP_TAIL = 0` and `FFT_SIZE ≥ 2` are no longer in the
  regression. The numpy check that a standalone `fft_direct` output is the
  FFT of its input applied only to `MAP_TAIL = 0` sets and is no longer
  run; `fft_wideband_real`'s end-to-end FFT check still covers
  `fft_direct` with `MAP_TAIL = 1`.
