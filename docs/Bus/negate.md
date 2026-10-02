# negate

## Description

Two's-complement negation with output requantization:

```
dout = convert(−din)
```

The negation is formed at full precision (`N_BITS_IN + 1` bits, signed), so
negating the most negative signed value, or any unsigned value, is exact. A
[`convert`](convert.md) instance then maps the result to the output format and
adds the `LATENCY` pipeline. One lane of casper_library's `bus_negate` (the
Xilinx *Negate* block). The complex-conjugate block in `mirror_spectrum` will
use it.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_IN`    | 8       | Input word width |
| `BIN_PT_IN`    | 4       | Input binary point |
| `TYPE_IN`      | 1       | Input type: `0`=unsigned, `1`=signed |
| `N_BITS_OUT`   | 8       | Output word width |
| `BIN_PT_OUT`   | 4       | Output binary point |
| `TYPE_OUT`     | 1       | Output type: `0`=unsigned, `1`=signed |
| `QUANTIZATION` | 0       | `0`=truncate, `1`=round half away from zero, `2`=round half to even (only relevant when `BIN_PT_OUT < BIN_PT_IN`) |
| `OVERFLOW`     | 0       | `0`=wrap, `1`=saturate, `2`=flag as error (treated as wrap) |
| `LATENCY`      | 1       | Pipeline stages on the output; `0` = combinational |

With `OVERFLOW = 0` and the output in the same format as the input, `−(−2^(N−1))`
wraps to `−2^(N−1)`, as in plain two's-complement hardware. With `OVERFLOW = 1`
it saturates to `2^(N−1) − 1`.

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock (unused when `LATENCY = 0`) |
| `din`  | input     | `N_BITS_IN`  | Input word |
| `dout` | output    | `N_BITS_OUT` | `convert(−din)`, delayed by `LATENCY` cycles |
