# scale

## Description

Multiplication by a power of two, followed by requantization:

```
dout = convert(din · 2^SCALE_FACTOR)
```

As in the Xilinx *Scale* block, scaling only reinterprets the word: the bits are
unchanged and the binary point moves from `BIN_PT_IN` to
`BIN_PT_IN − SCALE_FACTOR`. The rescaled value then goes through a
[`convert`](convert.md) instance, which applies `QUANTIZATION` and `OVERFLOW` and
adds the `LATENCY` pipeline. One lane of casper_library's `bus_scale`. A typical
use is the FFT per-stage "shift" (`SCALE_FACTOR = −1`, with the output in the
same format as the input).

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_IN`    | 16      | Input word width |
| `BIN_PT_IN`    | 8       | Input binary point |
| `TYPE_IN`      | 1       | Input type: `0`=unsigned, `1`=signed |
| `SCALE_FACTOR` | −1      | Signed power-of-two exponent: `> 0` multiplies, `< 0` divides |
| `N_BITS_OUT`   | 16      | Output word width |
| `BIN_PT_OUT`   | 8       | Output binary point |
| `TYPE_OUT`     | 1       | Output type: `0`=unsigned, `1`=signed |
| `QUANTIZATION` | 0       | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`     | 0       | `0`=wrap, `1`=saturate, `2`=flag as error (treated as wrap) |
| `LATENCY`      | 1       | Pipeline stages on the output; `0` = combinational |

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock (unused when `LATENCY = 0`) |
| `din`  | input     | `N_BITS_IN`  | Input word |
| `dout` | output    | `N_BITS_OUT` | `convert(din · 2^SCALE_FACTOR)`, delayed by `LATENCY` cycles |

## Functional Description

The module is a single `convert` with `BIN_PT_IN` replaced by
`BIN_PT_IN − SCALE_FACTOR`. The intermediate binary point may be negative (for
example, `Fix_8_2` scaled by `2^5` has binary point −3). `convert` depends only on
the difference between the input and output binary points, so this is handled
exactly.
