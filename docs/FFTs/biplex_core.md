# biplex_core

## Description

A streaming biplex FFT core: a chain of `FFT_SIZE`
[`fft_stage_n`](fft_stage_n.md) stages. It corresponds to casper_library's
`biplex_core` (fixed-point, synchronous). As `biplex_core_init.m` wires it:
- Stage 1 takes `pol1`/`pol2`, `of_in = 0` and `sync`.
- Each later stage takes the previous stage's `out1`/`out2`/`of`/`sync_out`.
- All stages share the `shift` bus.

The core computes the `2^FFT_SIZE`-point FFT of each of the two complex
streams. The test data generator checks this against numpy. Outputs appear in
casper's biplex order, starting the cycle after `sync_out`:

- **Stream order:** the first half-frame (`2^(FFT_SIZE−1)` cycles) carries
  pol1, and the second half-frame carries pol2.
- **Bin order:** in frame cycle `k`, `out1` holds bin
  `bit_rev(k mod 2^(FFT_SIZE−1), FFT_SIZE−1)` and `out2` holds that bin
  `+ 2^(FFT_SIZE−1)`.
- **Scaling:** each stage that downshifts divides by 2.

This order is undone later by the `fft_biplex_real` / `fft_wideband_real`
unscramblers.

## Per-Stage Parameters (as `biplex_core_init.m`)

| Stage `s` parameter | Value |
|---------------------|-------|
| `DELAYS_BRAM` | `(FFT_SIZE − s > DELAYS_BIT_LIMIT) && (2^(FFT_SIZE−s) > BRAM_LATENCY)` |
| `DOWNSHIFT` | `HARDCODE_SHIFTS && SHIFT_SCHEDULE[s−1]` |
| input width | `BITGROWTH ? min(MAX_BITS, INPUT_BIT_WIDTH + s − 1) : INPUT_BIT_WIDTH` |
| `BITGROWTH` | `BITGROWTH && (input width + 1 ≤ MAX_BITS)` |
| `INIT_FILE` | `COEFF_DIR` + `twiddle_stage<s>.mem` (used by stages ≥ 3) |

- casper compares `2^(FFT_SIZE−s)` against `num2str(bram_latency)`, the
  character code of the digit. The result is the same whenever
  `DELAYS_BIT_LIMIT ≥ 5`.
- Generate each stage's table with
  `rtl/FFTs/Twiddle/scripts/gen_twiddle_coeffs.py --fft-size FFT_SIZE --coeffs 0 … 2^(s−1)−1`.
- `BIN_PT_IN` is the same for every stage.

## Parameters

| Parameter          | Default     | Description |
|--------------------|-------------|-------------|
| `N_INPUTS`         | 1           | Complex lanes per stream |
| `FFT_SIZE`         | 3           | log2 of the FFT length (≥ 2) |
| `INPUT_BIT_WIDTH`  | 18          | Input width (signed) |
| `BIN_PT_IN`        | 17          | Binary point (all stages) |
| `COEFF_BIT_WIDTH`  | 18          | Twiddle coefficient width |
| `ADD_LATENCY`, `MULT_LATENCY`, `BRAM_LATENCY`, `CONV_LATENCY` | 1, 2, 2, 1 | As casper |
| `QUANTIZATION`     | 1           | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`         | 0           | `0`=wrap, `1`=saturate |
| `DELAYS_BIT_LIMIT` | 8           | Stages with `FFT_SIZE − s` above this use RAM delays |
| `MAX_FANOUT`       | 4           | Fan-out latency control (per stage) |
| `BITGROWTH`        | 0           | Grow one bit per stage instead of shifting, up to `MAX_BITS` |
| `MAX_BITS`         | 20          | Width limit for bit growth |
| `HARDCODE_SHIFTS`  | 0           | Use `SHIFT_SCHEDULE` instead of the `shift` input |
| `SHIFT_SCHEDULE`   | 3           | casper `shift_schedule` as a bit mask (bit `s−1` = stage `s`) |
| `COEFF_DIR`        | `""`        | Directory prefix of the `twiddle_stage<s>.mem` files (include the trailing `/`) |
| `PLATFORM`         | `"GENERIC"` | Passed to the RAMs / ROMs |

**Declared but not implemented:** `ASYNC` and `FLOATING_POINT` must be 0. These
are ignored: `FLOAT_TYPE`, `EXP_WIDTH`, `FRAC_WIDTH`, `ADD_PIPE_LATENCY`,
`MULT_PIPE_LATENCY`, `COEFFS_BIT_LIMIT`, `COEFF_SHARING`, `COEFF_DECIMATION`,
`MULT_SPEC`, `DSP48_ADDERS`. `N_BITS_OUT` is derived (the last stage's
output width).

## Ports

Lane ports are unpacked arrays of `N_INPUTS` words.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `pol1_re`, `pol1_im`, `pol2_re`, `pol2_im` | input | `INPUT_BIT_WIDTH` × `N_INPUTS` | The two input streams |
| `sync` | input | 1 | Frame sync (one pulse per `2^FFT_SIZE`-sample frame, the cycle before the frame) |
| `shift` | input | `FFT_SIZE` | Dynamic downshift per stage (bit `s−1` = stage `s`) |
| `out1_re`, `out1_im`, `out2_re`, `out2_im` | output | `N_BITS_OUT` × `N_INPUTS` | FFT outputs (order above) |
| `of` | output | `N_INPUTS` | Overflow flags ORed over the stages |
| `sync_out` | output | 1 | Sync, the cycle before the first output of a frame |
