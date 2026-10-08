# fft_biplex_real_4x

## Description

A biplex FFT of `4·N_INPUTS` real signals. It corresponds to
casper_library's `fft_biplex_real_4x` (fixed point, sync mode,
`fft_biplex_real_4x_init.m`); casper's `n_inputs` is `N_INPUTS`
here. The real inputs are paired into complex signals and fed to one
[`biplex_core`](biplex_core.md).
[`bi_real_unscr_4x`](Internal/bi_real_unscr_4x.md) then separates the four
real spectra of each lane.

| Signal | Source |
|--------|--------|
| biplex_core `pol1` (casper `even_bussify`), lane `j` | `pol_in[4j] + j·pol_in[4j+1]` |
| biplex_core `pol2` (casper `odd_bussify`), lane `j` | `pol_in[4j+2] + j·pol_in[4j+3]` |
| bi_real_unscr_4x `sync` / `even` / `odd` | biplex_core `sync_out` / `out1` / `out2` |
| `pol_out[i]` | bi_real_unscr_4x `pol<(i mod 4)+1>_out`, lane `floor(i/4)`: the spectrum of `pol_in[i]` (complex, one bin per cycle) |
| `of` | biplex_core's `of`, which bypasses bi_real_unscr_4x |

In casper, `pol<i−1>_in` and `pol<i>_in` (odd `i`) form `ri_to_c` number
`floor(i/2)`. It goes to `even_bussify` if `mod((i+1)/2, 2) == 1`, else to
`odd_bussify`, at port `floor(i/4)+1`. `pol<i>_out` comes from
`pol<i mod 4>_debus`, port `floor(i/4)+1`.

### Derived parameters (as `fft_biplex_real_4x_init.m`)

F = `FFT_SIZE`, IW = `INPUT_BIT_WIDTH`:

| Quantity | Value |
|----------|-------|
| `bram_delays` | `2^(F−1)·2·IW·N_INPUTS ≥ 2^DELAYS_BIT_LIMIT` and `2^(F−1) ≥ BRAM_LATENCY+2` |
| `bram_map` | `2^(F−1)·(F−1) ≥ 2^COEFFS_BIT_LIMIT` and `2^(F−1) ≥ BRAM_LATENCY` |
| output width `N_BITS_OUT` | `BITGROWTH ? min(IW+F, MAX_BITS) : IW`, binary point `BIN_PT_IN` |

### Memory files

- biplex_core reads `COEFF_DIR` + `twiddle_stage<s>.mem`.
- bi_real_unscr_4x reads `MAP_DIR` + `map_even.mem` / `map_odd.mem` /
  `map_out.mem`.

Generate all of them with:

```bash
python3 rtl/FFTs/scripts/gen_fft_mem_files.py biplex_real_4x --fft-size F --coeff-bit-width W -o DIR/
```

### Sync, overflow and limits

- The inputs need a sync once per `2^FFT_SIZE`-cycle frame (or a multiple
  of that), as bi_real_unscr_4x's reorders require.
- `of[n]` is lane `n`'s overflow, following biplex_core's convention.
- `FFT_SIZE ≥ 3` is needed for the outputs to be FFTs (bi_real_unscr_4x's
  casper behaviour at `FFT_SIZE = 2`).
- `ASYNC` must be 0. `COEFF_SHARING`, `COEFF_DECIMATION`, `MULT_SPEC`,
  `DSP48_ADDERS`, `ADD_PIPE_LATENCY` and `MULT_PIPE_LATENCY` are declared
  but ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | casper `n_inputs`: complex biplex lanes (4 real signals each) |
| `FFT_SIZE` | 2 | log2 of the FFT length |
| `INPUT_BIT_WIDTH` | 18 | Real input width (signed) |
| `BIN_PT_IN` | 17 | Binary point |
| `COEFF_BIT_WIDTH` | 18 | Twiddle width |
| `ADD_LATENCY`, `MULT_LATENCY`, `BRAM_LATENCY`, `CONV_LATENCY` | 1, 2, 2, 1 | As casper |
| `QUANTIZATION` | 1 | `0` = truncate, `1` = round ±inf, `2` = round even |
| `OVERFLOW` | 1 | `0` = wrap, `1` = saturate |
| `DELAYS_BIT_LIMIT`, `COEFFS_BIT_LIMIT` | 8, 8 | RAM thresholds (see above) |
| `MAX_FANOUT` | 4 | As biplex_core |
| `BITGROWTH`, `MAX_BITS` | 0, 19 | Bit growth instead of shifting, width limit |
| `HARDCODE_SHIFTS`, `SHIFT_SCHEDULE` | 0, 3 | Static shifts; bit `s−1` = stage `s` |
| `COEFF_DIR`, `MAP_DIR` | `""` | Directory prefixes of the memory files |
| `PLATFORM` | `"GENERIC"` | Memory primitives |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Frame sync |
| `shift` | input | `FFT_SIZE` | Dynamic downshift (bit `s−1` = stage `s`) |
| `pol_in` | input | `INPUT_BIT_WIDTH` × `4·N_INPUTS` | Real inputs |
| `sync_out` | output | 1 | Sync, one cycle before bin 0 |
| `pol_out_re`, `pol_out_im` | output | `N_BITS_OUT` × `4·N_INPUTS` | Spectrum of each input, bins 0 … 2^F−1 |
| `of` | output | `N_INPUTS` | biplex_core overflow per lane |
