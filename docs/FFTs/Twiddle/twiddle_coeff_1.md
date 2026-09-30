# twiddle_coeff_1

## Description

A twiddle stage for `Coeffs = [1]`, which corresponds to casper_library's
`twiddle_coeff_1`. It implements the block's datapath exactly as
`twiddle_coeff_1_init.m` builds it:

1. A `munge` splits `bi` into all real parts and all imaginary parts.
2. The real lane is negated (`bus_negate`, saturating). The imaginary lane is
   only delayed.
3. `bus_create(imag, −real)` and a second `munge` re-interleave the lanes. The
   delayed imaginary lane takes the real position, and the negated real lane
   takes the imaginary position.

Per lane, the result is:

```
bwo_re = bi_im        bwo_im = −bi_re        (= −j · bi)
```

This is the product with w = exp(−2πj · bit_rev(1, FFTSize−1) / 2^FFTSize) =
exp(−jπ/2) = −j, the coefficient `butterfly_direct` selects this variant for.
The negation uses [`negate`](../../Bus/negate.md) with `OVERFLOW = 1`, so
−(−2^(N−1)) saturates to 2^(N−1)−1. `bwo` keeps the input width and binary
point.

Every leg (`ai → ao`, both `bi` lanes, `sync`) has the same latency:

```
LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
```

This matches [`twiddle_coeff_0`](twiddle_coeff_0.md), and matches
[`twiddle_general`](twiddle_general.md) when its `BRAM_LATENCY` is 1.
`BRAM_LATENCY` is accepted but not used, as in casper_library.

## Parameters

| Parameter         | Default | Description |
|-------------------|---------|-------------|
| `N_INPUTS`        | 1       | Number of complex lanes |
| `INPUT_BIT_WIDTH` | 18      | Lane word width (signed) |
| `BIN_PT_IN`       | 17      | Binary point of the lanes |
| `MULT_LATENCY`    | 2       | Enters `LATENCY` |
| `ADD_LATENCY`     | 1       | Enters `LATENCY` |
| `BRAM_LATENCY`    | 1       | Accepted for traceability; unused |
| `CONV_LATENCY`    | 1       | Enters `LATENCY` |
| `ASYNC`           | 0       | Declared for traceability; must be 0 |

## Ports

The ports are the same as [`twiddle_pass_through`](twiddle_pass_through.md).
All outputs are delayed by `LATENCY`.
