# pfb_fir_real

## Description

A polyphase filter bank FIR for real inputs. It corresponds to
casper_library's `pfb_fir_real` (`pfb_fir_real_init.m`). The block has
`POLS` polarisations (2 if `MAKE_BIPLEX`, else 1). Each polarisation `p`
has `2^N_INPUTS` inputs, and each input `n` gets its own chain:

```
pol<p>_in<n> ─► pfb_coeff_gen (NPUT = n−1)                  own coefficients, or for p = 2 with
                                                            COEFFS_SHARE: a delay of BRAM_LATENCY+1+FAN_LATENCY,
                                                            using pol 1's coefficients
  ─► first_tap_real ─► tap_real × (TOTAL_TAPS−2) ─► last_tap_real
  ─► adder_tree (TOTAL_TAPS inputs, ADD_LATENCY per stage,
                 every adder Fix_ADDER_N_BITS_OUT_ADDER_BIN_PT_OUT, Truncate, Wrap)
  ─► Scale (2^SCALE_FACTOR) ─► Convert (Fix_BIT_WIDTH_OUT_(BIT_WIDTH_OUT−1), Wrap, CONV_LATENCY)
  ─► pol<p>_out<n>
```

The blocks are [`pfb_coeff_gen`](pfb_coeff_gen.md),
[`first_tap_real`](first_tap_real.md), [`tap_real`](tap_real.md),
[`last_tap_real`](last_tap_real.md) and
[`adder_tree`](../Misc/adder_tree.md) (with `PRECISION = 1`).

- Every first tap takes its sync from pol 1 / input 1's pfb_coeff_gen.
- `sync_out` is pol 1 / input 1's adder_tree sync, delayed `CONV_LATENCY`.
- `N_POL_BLOCKS` (serially interleaved polarisations) only lengthens the
  per-tap delay to `2^(PFB_SIZE−N_INPUTS)·N_POL_BLOCKS`; it adds no chains.

### What it computes

The tap chain computes the windowed presum

```
y_c(f) = Σ_{j ≡ c (mod 2^PFB_SIZE)} h[j] · x[(f − TOTAL_TAPS + 1)·2^PFB_SIZE + j]
```

for channel `c = 2^N_INPUTS·k + n−1`, which appears on input `n` at frame
cycle `k`. The test data generator checks every output frame end to end:

- The output equals, bit for bit, this sum computed from its definition with
  the quantized coefficients, then scaled and converted. So the Wrap-mode bit
  growth never loses a bit.
- The output differs from the same PFB in floating point (unquantized
  coefficients) by at most the coefficient-rounding bound.

### Width accounting (as `pfb_fir_real_init.m`)

These quantities need the coefficient values, so they are parameters,
computed by `rtl/PFBs/scripts/gen_pfb_coeffs.py --bit-width-in`. The same
script also writes the ROM files into `COEFF_DIR`.

| Parameter | Value |
|-----------|-------|
| `BIT_GROWTH` | `nextpow2(max over the 2^PFB_SIZE sub-filters of Σ|h|)`, from the unquantized coefficients, with the gain at least 1 |
| `ADDER_BIN_PT_OUT` | `BIT_WIDTH_IN + COEFF_BIT_WIDTH − 2` |
| `ADDER_N_BITS_OUT` | `BIT_GROWTH + 1 + ADDER_BIN_PT_OUT` |
| `SCALE_FACTOR` | `−BIT_GROWTH` |
| output width `N_BITS_OUT` | `BIT_WIDTH_OUT`, or `ADDER_N_BITS_OUT` if `BIT_WIDTH_OUT = 0` (the mask's convention) |

```bash
python3 rtl/PFBs/scripts/gen_pfb_coeffs.py --pfb-size P --total-taps T --window hamming \
        --n-inputs N --coeff-bit-width W --bit-width-in B [--bit-width-out O] -o DIR/
```

- The output convert truncates when `N_BITS_OUT > ADDER_BIN_PT_OUT`;
  otherwise it uses `QUANTIZATION` (0 truncate, 1 round ±inf, 2 round even),
  as the init script does.
- There is no overflow parameter: everything wraps, and there is no `shift`
  input.

### Ports

Element `(p−1)·2^N_INPUTS + (n−1)` of `din` / `dout` is `pol<p>_in<n>` /
`pol<p>_out<n>`.

### Not implemented

`WINDOW_TYPE` and `FWIDTH` only shape the coefficient files.
`MULT_SPEC`, `ADDER_FOLDING` (passed to the adder tree as
`FIRST_STAGE_HDL`), `ADDER_IMP` and `COEFF_DIST_MEM` are implementation
choices; they are declared and ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PFB_SIZE` | 5 | log2 of the channels |
| `TOTAL_TAPS` | 2 | Taps (≥ 2) |
| `WINDOW_TYPE` | `"hamming"` | Window (see pfb_coeff_gen) |
| `N_INPUTS` | 1 | log2 of the parallel inputs per polarisation |
| `N_POL_BLOCKS` | 1 | Serially interleaved polarisations per input |
| `MAKE_BIPLEX` | 0 | Two polarisations |
| `BIT_WIDTH_IN` | 8 | Input width (Fix_BIT_WIDTH_IN_(BIT_WIDTH_IN−1)) |
| `BIT_WIDTH_OUT` | 0 | Output width; 0 = `ADDER_N_BITS_OUT` |
| `COEFF_BIT_WIDTH` | 18 | Coefficient width |
| `COEFF_DIST_MEM` | 0 | Ignored |
| `ADD_LATENCY`, `MULT_LATENCY`, `BRAM_LATENCY`, `FAN_LATENCY`, `CONV_LATENCY` | 1, 2, 2, 1, 1 | As casper |
| `QUANTIZATION` | 1 | Output rounding (see above) |
| `FWIDTH` | 1.0 | Sinc width factor |
| `MULT_SPEC`, `ADDER_FOLDING`, `ADDER_IMP` | 2, 1, 0 | Ignored |
| `COEFFS_SHARE` | 0 | Pol 2 shares pol 1's coefficients (`MAKE_BIPLEX` only) |
| `BIT_GROWTH`, `ADDER_N_BITS_OUT`, `ADDER_BIN_PT_OUT`, `SCALE_FACTOR` | — | From `gen_pfb_coeffs.py` (see above) |
| `COEFF_DIR` | `""` | Directory prefix of the ROM files |
| `PLATFORM` | `"GENERIC"` | Memory primitives |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Sync |
| `din` | input | `BIT_WIDTH_IN` × `POLS·2^N_INPUTS` | Real inputs |
| `sync_out` | output | 1 | Sync aligned with the outputs |
| `dout` | output | `N_BITS_OUT` × `POLS·2^N_INPUTS` | Filtered outputs |
