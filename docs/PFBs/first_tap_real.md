# first_tap_real

## Description

The first tap of a real PFB FIR. It corresponds to casper_library's
`first_tap_real`: the internal diagram in `casper_library_pfbs.slx` is the
same as [`tap_real`](tap_real.md)'s, and `first_tap_real_init.m` only sets
the multiplier implementation. The module is a `tap_real` instance with the
parameters pfb_fir_real propagates:

| tap_real parameter | Value |
|--------------------|-------|
| `DELAY` | `2^(PFB_SIZE−N_INPUTS) · N_POL_BLOCKS` |
| `COEFF_WIDTH`, `COEFF_FRAC_WIDTH` | `COEFF_BIT_WIDTH`, `COEFF_BIT_WIDTH−1` |
| `DATA_WIDTH` | `BIT_WIDTH_IN` |
| `N_COEFFS` | `TOTAL_TAPS` (the full bus of [`pfb_coeff_gen`](pfb_coeff_gen.md)) |

pfb_coeff_gen puts ROM 1 in the MSBs of the coefficient bus, so this tap
uses the lowest slice, ROM `TOTAL_TAPS`, which is the last segment of the
window. Its sample is the newest one in the windowed presum; see tap_real.
In pfb_fir_real, its `din` and `coeff` come from pfb_coeff_gen's `dout` and
`coeff`, and its `sync` from pfb_coeff_gen's `sync_out`.

Of the mask parameters, the following are used: `PFBSize`, `n_inputs`,
`n_pol_blocks`, `CoeffBitWidth`, `TotalTaps`, `BitWidthIn`, `mult_latency`
and `bram_latency`. `use_hdl` and `use_embedded` are declared and ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PFB_SIZE` | 6 | log2 of the PFB channels |
| `N_INPUTS` | 1 | log2 of the parallel inputs |
| `N_POL_BLOCKS` | 1 | Serially interleaved polarisations |
| `COEFF_BIT_WIDTH` | 8 | Coefficient width |
| `TOTAL_TAPS` | 4 | Taps (≥ 2) |
| `BIT_WIDTH_IN` | 8 | Data width |
| `MULT_LATENCY` | 2 | Multiplier latency |
| `BRAM_LATENCY` | 2 | casper delay_bram latency |
| `PLATFORM` | `"GENERIC"` | Memory primitives |
| `USE_HDL`, `USE_EMBEDDED` | 1, 0 | Ignored |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | `BIT_WIDTH_IN` | Data |
| `sync` | input | 1 | Sync |
| `coeff` | input | `TOTAL_TAPS·COEFF_BIT_WIDTH` | pfb_coeff_gen's bus `{coeff[0], …, coeff[T−1]}` (ROM 1 = MSB) |
| `dout` | output | `BIT_WIDTH_IN` | `din` delayed `DELAY` |
| `sync_out` | output | 1 | `sync` through `sync_delay(DELAY)` |
| `coeff_out` | output | `(TOTAL_TAPS−1)·COEFF_BIT_WIDTH` | Rest of the bus (no delay) |
| `taps_out` | output | `BIT_WIDTH_IN+COEFF_BIT_WIDTH` | Product (binary point `BIT_WIDTH_IN+COEFF_BIT_WIDTH−2`) |
