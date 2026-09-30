# adder_subtractor

## Description

Fixed-point addition or subtraction with independent input formats and output
requantization. One lane of casper_library's `bus_addsub` (the Xilinx *AddSub*
block).

```
a ──► convert (align) ──┐
                        ├─► a ± b (full precision) ──► convert (QUANTIZATION, OVERFLOW, LATENCY) ──► dout
b ──► convert (align) ──┘
```

Both operands are aligned to a common signed full-precision format, so the
sum or difference is exact. A final `convert` then requantizes it to the output
format and adds the `LATENCY` pipeline.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_A`     | 8       | `a` word width |
| `BIN_PT_A`     | 4       | `a` binary point |
| `TYPE_A`       | 1       | `a` type: `0`=unsigned, `1`=signed |
| `N_BITS_B`     | 8       | `b` word width |
| `BIN_PT_B`     | 4       | `b` binary point |
| `TYPE_B`       | 1       | `b` type: `0`=unsigned, `1`=signed |
| `N_BITS_OUT`   | 9       | Output word width |
| `BIN_PT_OUT`   | 4       | Output binary point |
| `TYPE_OUT`     | 1       | Output type: `0`=unsigned, `1`=signed |
| `OPMODE`       | 0       | `0`=addition (`a + b`), `1`=subtraction (`a − b`) |
| `QUANTIZATION` | 0       | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`     | 0       | `0`=wrap, `1`=saturate, `2`=flag as error (treated as wrap) |
| `LATENCY`      | 1       | Pipeline stages on the output; `0` = combinational |

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock (unused when `LATENCY = 0`) |
| `a`    | input     | `N_BITS_A`   | First operand |
| `b`    | input     | `N_BITS_B`   | Second operand |
| `dout` | output    | `N_BITS_OUT` | `convert(a ± b)`, delayed by `LATENCY` cycles |

## Functional Description

The internal full-precision format is signed with:

- `BIN_PT_FULL = max(BIN_PT_A, BIN_PT_B)`
- `N_BITS_FULL = max(N_BITS_A − BIN_PT_A, N_BITS_B − BIN_PT_B) + 2 + BIN_PT_FULL`

The two extra integer bits hold the carry and the sign (needed for unsigned
operands and for subtraction), so the intermediate never overflows. Rounding
and overflow semantics are those of [`convert`](convert.md).

To get an exact full-precision result (as `complex_multiplier` does internally),
set the output format to `N_BITS_OUT = N_BITS_FULL`, `BIN_PT_OUT = BIN_PT_FULL`,
`TYPE_OUT = 1`.
