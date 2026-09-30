# multiplier

## Description

Fixed-point real multiplication with independent input formats and output
requantization. One real lane of casper_library's `bus_mult` (the Xilinx *Mult*
block).

```
a ──► sign/zero extend ──┐
                         ├─► a × b (full precision) ──► convert (QUANTIZATION, OVERFLOW, LATENCY) ──► dout
b ──► sign/zero extend ──┘
```

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_A`     | 8       | `a` word width |
| `BIN_PT_A`     | 7       | `a` binary point |
| `TYPE_A`       | 1       | `a` type: `0`=unsigned, `1`=signed |
| `N_BITS_B`     | 8       | `b` word width |
| `BIN_PT_B`     | 7       | `b` binary point |
| `TYPE_B`       | 1       | `b` type: `0`=unsigned, `1`=signed |
| `N_BITS_OUT`   | 16      | Output word width |
| `BIN_PT_OUT`   | 14      | Output binary point |
| `TYPE_OUT`     | 1       | Output type: `0`=unsigned, `1`=signed |
| `QUANTIZATION` | 0       | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`     | 0       | `0`=wrap, `1`=saturate, `2`=flag as error (treated as wrap) |
| `LATENCY`      | 1       | Pipeline stages on the output; `0` = combinational |

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock (unused when `LATENCY = 0`) |
| `a`    | input     | `N_BITS_A`   | First operand |
| `b`    | input     | `N_BITS_B`   | Second operand |
| `dout` | output    | `N_BITS_OUT` | `convert(a × b)`, delayed by `LATENCY` cycles |

## Functional Description

Each operand is widened by one bit to a signed integer (sign-extended if signed,
zero-extended if unsigned). The two are multiplied into a signed full-precision
product:

- `N_BITS_FULL = N_BITS_A + N_BITS_B + 2`
- `BIN_PT_FULL = BIN_PT_A + BIN_PT_B`

The product is exact. A [`convert`](convert.md) instance then requantizes it to
the output format and adds the `LATENCY` pipeline. The multiplication uses the
generic `*` operator, so synthesis maps it to DSP slices as it chooses. No
vendor primitives are instantiated.
