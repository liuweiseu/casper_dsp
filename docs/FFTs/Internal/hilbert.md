# hilbert

## Description

Splits the FFT of two real signals that were packed as one complex signal.
It corresponds to casper_library's `hilbert` (fixed point, `misc` off,
`hilbert_init.m`). If `z = x + j·y` with real `x`, `y`, then with `a = Z[k]`
and `b = Z[N−k]`:

```
even = (a + conj(b)) / 2     = X[k]
odd  = (a − conj(b)) / (2j)  = Y[k]
```

Per lane, as `hilbert_init.m` wires it:

| Output | casper block | Value |
|--------|--------------|-------|
| `even_re` | `add_even_real` | `(a_re + b_re) / 2` |
| `even_im` | `sub_even_imag` | `(a_im − b_im) / 2` |
| `odd_re`  | `add_odd_real`  | `(a_im + b_im) / 2` |
| `odd_im`  | `sub_odd_imag`  | `(b_re − a_re) / 2` |

- The sums are full precision: `BIT_WIDTH+1` bits, binary point
  `BIN_PT_IN`, [`adder_subtractor`](../../Bus/adder_subtractor.md) with latency
  `ADD_LATENCY`.
- casper's `bus_scale(−1)` halves them by moving the binary point to
  `BIN_PT_IN+1`.
- A [`convert`](../../Bus/convert.md) brings them back to `BIT_WIDTH` bits /
  `BIN_PT_IN` with latency `CONV_LATENCY`. Its rounding (half to even) and
  overflow (wrap) are fixed in `hilbert_init.m`. The only overflow is
  `odd_im` for `b_re` maximum and `a_re` most negative, which rounds up to
  `+2^(BIT_WIDTH−1)` LSB and wraps.

Total latency: `ADD_LATENCY + CONV_LATENCY`. casper's `misc` port and
floating point are not implemented. [`bi_real_unscr_4x`](bi_real_unscr_4x.md)
uses two of them.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | Complex lanes |
| `BIT_WIDTH` | 18 | Width of the inputs and outputs (signed) |
| `BIN_PT_IN` | 17 | Binary point |
| `ADD_LATENCY` | 1 | Adder latency |
| `CONV_LATENCY` | 1 | Convert latency |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a_re`, `a_im` | input | `BIT_WIDTH` × `N_INPUTS` | `Z[k]` |
| `b_re`, `b_im` | input | `BIT_WIDTH` × `N_INPUTS` | `Z[N−k]` |
| `even_re`, `even_im` | output | `BIT_WIDTH` × `N_INPUTS` | `X[k]` (spectrum of the real part) |
| `odd_re`, `odd_im` | output | `BIT_WIDTH` × `N_INPUTS` | `Y[k]` (spectrum of the imaginary part) |
