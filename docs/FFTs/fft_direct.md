# fft_direct

## Description

A fully parallel radix-2 FFT. Every cycle, each of the `N_STREAMS` streams
presents `2^FFT_SIZE` complex samples. `FFT_SIZE` stages of
[`butterfly_direct`](butterfly_direct.md) (`BIPLEX` off, `STEP_PERIOD` 0)
transform them, and the outputs come out in natural order. It corresponds
to casper_library's `fft_direct` (fixed point, sync mode,
`fft_direct_init.m`). [`fft_wideband_real`](fft_wideband_real.md) uses it
for its last `N_INPUTS` stages.

### Structure (as `fft_direct_init.m` wires it, F = `FFT_SIZE`)

| | |
|---|---|
| Stage 0 | One butterfly of `N_STREAMS·2^(F−1)` lanes. Input `in<s><n>` is lane `idx = n·N_STREAMS + s`: `a` gets `idx < N_STREAMS·2^(F−1)`, `b` the rest |
| Stage `s` | `2^s` butterflies of `L = N_STREAMS·2^(F−s−1)` lanes. Butterfly `2u+c` of stage `s+1` takes butterfly `u`'s `a+bw` (`c = 0`) or `a−bw` (`c = 1`): `a` = its first `L/2` lanes, `b` = the rest |
| Output | `out<s><n>` = stream `s` of position `p = bit_rev(n, F)` of the last stage (butterfly `p>>1`; `a+bw` if `p` is even, else `a−bw`) |
| shift | Stage `s` uses `shift[s]`; `DOWNSHIFT = HARDCODE_SHIFTS && SHIFT_SCHEDULE` bit `s` |
| sync | The stage-0 butterfly gets `sync`; butterfly `2u+c` gets the `sync_out` of butterfly `u`; `sync_out` = `sync_out` of the last stage's butterfly 0 |

All butterflies of one stage share the twiddle-table latency, so the stages
stay aligned. For this, a single-coefficient general twiddle has the
latency of `twiddle_coeff_0`; see [`butterfly_direct`](butterfly_direct.md).

### Coefficients

Butterfly `u` of stage `s` (`n = u·2^(F−s−1)`) gets a time sequence of
coefficients. With `STEP_PERIOD` 0 it moves to the next coefficient every
cycle, and `sync` restarts it:

| `MAP_TAIL` | `Coeffs` | FFT size of the twiddles |
|------------|----------|--------------------------|
| 0 | `[floor(n / 2^(F−(s+1)))] = [u]` | `FFT_SIZE` |
| 1 | `Coeffs[r] = floor((n + bit_reverse(r, LARGER−F)·2^(F−1)) / 2^(LARGER−(START_STAGE+s)))`, `r = 0 … 2^(LARGER−F)−1` | `LARGER_FFT_SIZE` |

`MAP_TAIL` makes the block the last `F` stages of a `LARGER_FFT_SIZE`-point
FFT whose earlier stages ran as a biplex FFT. The `2^(LARGER−F)` cycles of
one biplex frame each need their own twiddles. From the coefficients,
`butterfly_direct` picks `twiddle_coeff_0`, `twiddle_coeff_1` or
`twiddle_general`. A general twiddle reads
`COEFF_DIR` + `twiddle_direct_s<s>_<u>.mem`; generate these files with:

```bash
python3 rtl/FFTs/scripts/gen_fft_mem_files.py direct --fft-size F --coeff-bit-width W -o DIR/
python3 rtl/FFTs/scripts/gen_fft_mem_files.py direct --fft-size F --map-tail \
        --larger-fft-size L --start-stage S --coeff-bit-width W -o DIR/
```

### Widths

Stage `s` takes `W(s) = BITGROWTH ? min(MAX_BITS, INPUT_BIT_WIDTH+s) :
INPUT_BIT_WIDTH` bits. It grows one bit if `BITGROWTH` and
`W(s)+1 ≤ MAX_BITS`. The outputs have `N_BITS_OUT = W(F−1) + grow` bits,
with binary point `BIN_PT_IN`.

> **Deliberate deviation from the source.** For `bitgrowth` on,
> `fft_direct_init.m` sizes the output `bus_expand`s with
> `n_bits = min(max_bits, input_bit_width*FFTSize)`. This is in the
> `for n=0:2^FFTSize-1` debus loop near the top of the file, a `*` typo for
> `+`. Copied literally, it would slice the outputs wrongly for almost every
> width. This module uses the real output width instead.

### Overflow

Per stage, the butterflies' `of` bits are concatenated (position `u·L + l`).
The stages are then ORed bitwise (casper `of_or`, Logical, latency 2). The
result is split into `2^(F−1)` parts of `N_STREAMS` bits, which are ORed
again (`combine`, latency 2). Position `j` of a part always belongs to
stream `j`, so `of[s]` is stream `s`'s overflow. It comes 4 cycles after
the butterflies' `of`. For `F = 1`, `of` is the single butterfly's `of`.

### Ports

Element `k` of `din` / `dout` is casper's `in<s><n>` / `out<s><n>` with
`k = s·2^F + n`.

### Not implemented

`ASYNC` must be 0. `COEFFS_BIT_LIMIT`, `COEFF_SHARING`, `COEFF_DECIMATION`,
`COEFF_GENERATION`, `CAL_BITS`, `N_BITS_ROTATION`, `MULT_SPEC`,
`DSP48_ADDERS`, `ADD_PIPE_LATENCY` and `MULT_PIPE_LATENCY` are declared but
ignored: the twiddles always come from tables, as in the rest of this
library.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_STREAMS` | 1 | Parallel streams |
| `FFT_SIZE` | 2 | log2 of the FFT length (stages) |
| `INPUT_BIT_WIDTH` | 18 | Input width (signed) |
| `BIN_PT_IN` | 17 | Binary point |
| `COEFF_BIT_WIDTH` | 18 | Twiddle width |
| `MAP_TAIL` | 1 | Tail of a larger FFT (see above) |
| `LARGER_FFT_SIZE` | 12 | Size of the larger FFT (`MAP_TAIL`) |
| `START_STAGE` | 10 | First stage of the larger FFT handled here, 1-based (`MAP_TAIL`) |
| `ADD_LATENCY`, `MULT_LATENCY`, `BRAM_LATENCY`, `CONV_LATENCY` | 1, 2, 2, 1 | As casper |
| `QUANTIZATION` | 1 | `0` = truncate, `1` = round ±inf, `2` = round even |
| `OVERFLOW` | 1 | `0` = wrap, `1` = saturate |
| `MAX_FANOUT` | 4 | butterfly_direct shift fan-out |
| `BITGROWTH` | 0 | Grow one bit per stage (up to `MAX_BITS`) instead of shifting |
| `MAX_BITS` | 19 | Width limit for bit growth |
| `HARDCODE_SHIFTS` | 1 | Use `SHIFT_SCHEDULE` instead of `shift` |
| `SHIFT_SCHEDULE` | 3 | Bit `s` = downshift in stage `s` |
| `COEFF_DIR` | `""` | Directory prefix of the twiddle tables |
| `PLATFORM` | `"GENERIC"` | Memory primitives |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Sync; restarts the coefficient sequences |
| `shift` | input | `FFT_SIZE` | Dynamic downshift per stage (bit `s` = stage `s`) |
| `din_re`, `din_im` | input | `INPUT_BIT_WIDTH` × `N_STREAMS·2^FFT_SIZE` | Inputs, element `s·2^F + n` |
| `sync_out` | output | 1 | Sync aligned with the outputs |
| `dout_re`, `dout_im` | output | `N_BITS_OUT` × `N_STREAMS·2^FFT_SIZE` | FFT outputs in natural order |
| `of` | output | `N_STREAMS` | Overflow per stream |
