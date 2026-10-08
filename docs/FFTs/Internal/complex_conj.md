# complex_conj

## Description

Complex conjugate of `N_INPUTS` lanes. It corresponds to casper_library's
`complex_conj` (fixed point, `complex_conj_init.m`):

- The real part is delayed `CSP_LATENCY` cycles (`real_delay`, a
  [`pipeline`](../../Delays/pipeline.md)).
- The imaginary part is negated by a [`negate`](../../Bus/negate.md)
  (casper `bus_negate`): same width and binary point, Truncate, latency
  `CSP_LATENCY`. `OVERFLOW` selects what happens to the most negative value,
  whose negation does not fit: `0` = Wrap (the value stays as it is), `1` =
  Saturate (it becomes the most positive value).

casper's `overflow = 'Flag as error'` and floating point are not
implemented. [`mirror_spectrum`](mirror_spectrum.md) uses it with Wrap.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | Complex lanes |
| `N_BITS` | 18 | Width of the real and imaginary parts (signed) |
| `BIN_PT` | 17 | Binary point |
| `CSP_LATENCY` | 1 | casper `csp_latency`; `0` = combinational |
| `OVERFLOW` | 0 | `0` = Wrap, `1` = Saturate |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din_re`, `din_im` | input | `N_BITS` × `N_INPUTS` | Input lanes |
| `dout_re`, `dout_im` | output | `N_BITS` × `N_INPUTS` | Conjugated lanes, `CSP_LATENCY` cycles later |
