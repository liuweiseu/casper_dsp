# fft_wideband_real

## Description

A `2^FFT_SIZE`-point real FFT that takes `2^N_INPUTS` samples per stream per
cycle. It corresponds to casper_library's `fft_wideband_real` (fixed point,
sync mode, `fft_wideband_real_init.m`) and is the top of this port.

Each of the `N_STREAMS` streams presents `2^N_INPUTS` real samples
`in<s><n>` per cycle; sample `t·2^N_INPUTS + n` of a frame arrives on
`in<s><n>` in frame cycle `t`. The outputs are the lower half of the
spectrum, `2^(N_INPUTS−1)` complex bins per cycle. With `UNSCRAMBLE` they
are in natural order: bin `t·2^(N_INPUTS−1) + n` on `out<s><n>` in frame
cycle `t`.

The test data generator checks this end to end against numpy: every output
frame is the scaled FFT of an input frame, to within 3 output LSB.

### Structure (F = `FFT_SIZE`, NI = `N_INPUTS`, NS = `N_STREAMS`)

```
in<s><n> ─► pipeline INPUT_LATENCY ─► fft_biplex_real_4x pol<s·2^NI+n>_in
   fft_biplex_real_4x: N_BIPLEX_INPUTS = NS·2^(NI−2), FFT_SIZE = F−NI  (first F−NI stages)
pol<s·2^NI+n>_out ─► pipeline BIPLEX_DIRECT_LATENCY ─► fft_direct in<s><n>
   fft_direct: N_STREAMS = NS, FFT_SIZE = NI, MAP_TAIL on,
               LARGER_FFT_SIZE = F, START_STAGE = F−NI+1        (last NI stages)
fft_direct out<s><n>, n < 2^(NI−1)   (the upper half is terminated)
   UNSCRAMBLE: ─► pipeline BIPLEX_DIRECT_LATENCY ─► fft_unscrambler ─► out<s><n>
               (FFT_SIZE = F−1, LOG2_N_GROUPS = NI−1, N_STREAMS = NS)
   otherwise : ─► out<s><n>
shift ─► fft_biplex_real_4x (low F−NI bits); shift[F−1 : F−NI] ─► fft_direct
of = fft_direct of | fft_biplex_real_4x of     (Logical OR, latency 1)
```

The blocks are [`fft_biplex_real_4x`](fft_biplex_real_4x.md),
[`fft_direct`](fft_direct.md) and
[`fft_unscrambler`](fft_unscrambler.md).

- There is exactly one `fft_biplex_real_4x` and one `fft_direct`;
  `N_STREAMS` is handled inside them.
- casper passes the whole `shift` bus to `fft_biplex_real_4x`, whose
  biplex_core only uses its low `F−NI` bits; here only those bits are
  connected.
- With `HARDCODE_SHIFTS`, `SHIFT_SCHEDULE` (bit `k` = stage `k+1`) is
  split: the low `F−NI` bits go to the biplex part, the rest to
  `fft_direct`.
- Widths: `fft_direct` gets `BITGROWTH ? min(MAX_BITS, IW+F−NI) : IW` bits.
  The outputs have `N_BITS_OUT = BITGROWTH ? min(MAX_BITS, IW+F) : IW` bits,
  binary point `BIN_PT_IN`.

### Rules taken from casper

- `UNSCRAMBLE` is treated as off when `N_INPUTS = 1`, as casper does
  (silently; no error).
- `2^N_INPUTS·N_STREAMS` must be a multiple of 4 (`$fatal` otherwise).
- `FFT_SIZE − N_INPUTS ≥ 2` is required, because biplex_core needs at least
  2 stages; `FFT_SIZE − N_INPUTS ≥ 3` is needed for an FFT result (see
  bi_real_unscr_4x).
- With `UNSCRAMBLE`, fft_unscrambler's limits apply, and `sync` must recur
  every `ORDER·2^(F−NI)` cycles (or a multiple of that). `ORDER` is that of
  the unscrambler map. Without the unscrambler, one sync per
  `2^(F−NI)`-cycle frame is enough.

### Overflow

casper's final OR aligns its inputs at the LSB.

- `fft_biplex_real_4x`'s `of` has `N_BIPLEX_INPUTS` bits, with lane 0 as the
  MSB of casper's bus.
- `fft_direct`'s `of` has `N_STREAMS` bits, with stream 0 as the MSB.

So `of` has `max(N_STREAMS, N_BIPLEX_INPUTS)` bits. Bit `b` is the OR of
biplex lane `N_BIPLEX_INPUTS−1−b` and fft_direct stream `N_STREAMS−1−b`;
a missing bit counts as 0.

### Memory files

All memory files live in `MEM_DIR`:

| File | Used by |
|------|---------|
| `twiddle_stage<s>.mem` | biplex_core |
| `map_even.mem`, `map_odd.mem`, `map_out.mem` | bi_real_unscr_4x |
| `twiddle_direct_s<s>_<u>.mem` | fft_direct |
| `map_unscrambler.mem` | fft_unscrambler |

Generate them with:

```bash
python3 rtl/FFTs/scripts/gen_fft_mem_files.py wideband_real --fft-size F --n-inputs NI \
        --coeff-bit-width W -o DIR/
```

### Ports

- Element `k` of `din` is `in<s><n>` with `k = s·2^NI + n`.
- Element `k` of `dout` is `out<s><n>` with `k = s·2^(NI−1) + n`.

### Not implemented

`ASYNC` and `FLOATING_POINT` must be 0. `FLOAT_TYPE`, `EXP_WIDTH`,
`FRAC_WIDTH`, `ADD_PIPE_LATENCY`, `MULT_PIPE_LATENCY`, `COEFF_SHARING`,
`COEFF_DECIMATION`, `COEFF_GENERATION`, `CAL_BITS`, `N_BITS_ROTATION`,
`MULT_SPEC` and `DSP48_ADDERS` are declared but ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_STREAMS` | 1 | Parallel streams |
| `FFT_SIZE` | 6 | log2 of the FFT length |
| `N_INPUTS` | 2 | log2 of the samples per stream per cycle |
| `INPUT_BIT_WIDTH` | 18 | Real input width (signed) |
| `BIN_PT_IN` | 17 | Binary point |
| `COEFF_BIT_WIDTH` | 18 | Twiddle width |
| `UNSCRAMBLE` | 1 | Natural-order outputs via fft_unscrambler (off when `N_INPUTS = 1`) |
| `ADD_LATENCY`, `MULT_LATENCY`, `BRAM_LATENCY`, `CONV_LATENCY` | 1, 2, 2, 0 | As casper |
| `INPUT_LATENCY` | 0 | Pipeline in front of the biplex part |
| `BIPLEX_DIRECT_LATENCY` | 0 | Pipelines between the blocks |
| `QUANTIZATION` | 1 | `0` = truncate, `1` = round ±inf, `2` = round even |
| `OVERFLOW` | 1 | `0` = wrap, `1` = saturate |
| `DELAYS_BIT_LIMIT`, `COEFFS_BIT_LIMIT` | 8, 8 | RAM thresholds |
| `MAX_FANOUT` | 4 | As the sub-blocks |
| `BITGROWTH`, `MAX_BITS` | 0, 19 | Bit growth instead of shifting, width limit |
| `HARDCODE_SHIFTS`, `SHIFT_SCHEDULE` | 0, 31 | Static shifts; bit `k` = stage `k+1` |
| `MEM_DIR` | `""` | Directory prefix of all memory files |
| `PLATFORM` | `"GENERIC"` | Memory primitives |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Frame sync |
| `shift` | input | `FFT_SIZE` | Dynamic downshift (bit `k` = stage `k+1`) |
| `din` | input | `INPUT_BIT_WIDTH` × `N_STREAMS·2^N_INPUTS` | Real inputs |
| `sync_out` | output | 1 | Sync, one cycle before the first output of a frame |
| `dout_re`, `dout_im` | output | `N_BITS_OUT` × `N_STREAMS·2^(N_INPUTS−1)` | Lower half of the spectrum |
| `of` | output | `max(N_STREAMS, N_BIPLEX_INPUTS)` | Overflow (see above) |
