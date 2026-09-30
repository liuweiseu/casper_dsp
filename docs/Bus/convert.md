# convert

## Description

A fixed-point format converter: requantization, bit growth and overflow
handling, with no arithmetic. `din` is read as a fixed-point number in the input
format and re-expressed in the output format. Dropped LSBs are handled by
`QUANTIZATION` and dropped MSBs by `OVERFLOW`. The result is delayed by `LATENCY`
pipeline stages. It corresponds to the Xilinx System Generator *Convert* block
used by casper_library's `bus_convert`.

`convert` is the requantization core of every fixed-point module in `rtl/Bus/`
and `rtl/Multipliers/`. The other modules compute an exact full-precision result, then pass it through a `convert`
instance.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_IN`    | 16      | Input word width |
| `BIN_PT_IN`    | 8       | Input binary point (number of fractional bits; may be negative) |
| `TYPE_IN`      | 1       | Input type: `0`=unsigned, `1`=signed (two's complement) |
| `N_BITS_OUT`   | 8       | Output word width |
| `BIN_PT_OUT`   | 4       | Output binary point |
| `TYPE_OUT`     | 1       | Output type: `0`=unsigned, `1`=signed |
| `QUANTIZATION` | 0       | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`     | 0       | `0`=wrap, `1`=saturate, `2`=flag as error (treated as wrap) |
| `LATENCY`      | 0       | Pipeline stages on the output; `0` = combinational |

The encodings match the casper_library mask prompts: *quantization strategy
(Truncate=0, Round (unbiased: +/- Inf)=1, Round (unbiased: Even Values)=2)* and
*overflow strategy (Wrap=0, Saturate=1, Flag as error=2)*. All fixed-point
modules in `rtl/Bus/` and `rtl/Multipliers/` use these encodings.

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock (unused when `LATENCY = 0`) |
| `din`  | input     | `N_BITS_IN`  | Input word |
| `dout` | output    | `N_BITS_OUT` | Converted word, delayed by `LATENCY` cycles |

## Functional Description

A word `x` with binary point `B` has the value `int(x) · 2^-B`. Here `int(x)` is
the unsigned or two's-complement integer, depending on `TYPE`. With
`s = BIN_PT_IN − BIN_PT_OUT`:

1. **Alignment**: if `s < 0`, `-s` zero LSBs are appended (exact). Only the
   difference of the binary points matters, so negative or out-of-range binary
   points are allowed.
2. **Quantization** (`s > 0`), in output LSB units:
   - truncate: `floor(x / 2^s)`
   - round half away from zero: `sign(x) · floor(|x| / 2^s + 1/2)`
   - round half to even: nearest integer, ties to the even value
3. **Overflow**: with wrap, the low `N_BITS_OUT` bits are kept. With saturate,
   the value is clamped to `[−2^(N−1), 2^(N−1)−1]` (signed) or `[0, 2^N−1]`
   (unsigned).
4. **Pipeline**: `LATENCY` chained `BasicModules/register` stages (no reset or
   enable), which power up to 0.
