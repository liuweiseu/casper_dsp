# convert_of

## Description

A fixed-point convert with an overflow flag, corresponding to casper_library's
`convert_of`. `dout` is exactly the output of [`convert`](../Bus/convert.md)
(signed in, signed out). `of` flags an input whose integer part does not fit
the output format. The flag follows the rule in `convert_of_init.m`:

```
wb_lost = (BIT_WIDTH_I − BINARY_POINT_I) − (BIT_WIDTH_O − BINARY_POINT_O)     integer bits dropped
of      = top (wb_lost + 1) bits of din are not all equal
```

`of` is set when `din` is not a sign extension of a value that fits.

- **Only `din` is checked.** If rounding carries a value out of range (for
  example, the largest value rounding up), `of` is not set. This matches
  casper_library.
- **`wb_lost ≤ 0`** means overflow is impossible, so `of = 0`.
- **Latency:** `dout` and `of` both have `CSP_LATENCY` pipeline stages, which
  power up to 0.

[`butterfly_direct`](../FFTs/butterfly_direct.md) uses one per output
component for its overflow flag.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `BIT_WIDTH_I`    | 16      | Input width (signed) |
| `BINARY_POINT_I`    | 8       | Input binary point |
| `BIT_WIDTH_O`   | 8       | Output width (signed) |
| `BINARY_POINT_O`   | 4       | Output binary point |
| `QUANTIZATION` | 0       | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`     | 0       | `0`=wrap, `1`=saturate |
| `CSP_LATENCY`      | 0       | Pipeline stages on `dout` and `of`; `0` = combinational |

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock (unused when `CSP_LATENCY = 0`) |
| `din`  | input     | `BIT_WIDTH_I`  | Input word |
| `dout` | output    | `BIT_WIDTH_O` | Converted word |
| `of`   | output    | 1            | Overflow flag, aligned with `dout` |
