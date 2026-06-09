# logical

## Description

A parameterizable bitwise logical reduction block with optional pipeline delay.
All `NINPUTS` input words of width `NBITS` are reduced combinationally using the
operation selected by `FUNC`. The result is then delayed by `LATENCY` flip-flop
pipeline stages before appearing at `dout`. When `LATENCY = 0` the output is
purely combinational. All pipeline stages are initialized to zero.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8       | Data bit width for all inputs and the output |
| `NINPUTS` | 2       | Number of input signals to reduce |
| `LATENCY` | 1       | Pipeline stages on output; `0` = combinational pass-through |
| `FUNC`    | 0       | Operation: `0`=AND, `1`=NAND, `2`=OR, `3`=NOR, `4`=XOR, `5`=XNOR |

## Ports

| Port   | Direction | Width               | Description |
|--------|-----------|---------------------|-------------|
| `clk`  | input     | 1                   | Clock signal (unused when `LATENCY = 0`) |
| `din`  | input     | `NBITS` × `NINPUTS` | Unpacked array of `NINPUTS` words, each `NBITS` wide |
| `dout` | output    | `NBITS`             | Reduced output, delayed by `LATENCY` clock cycles |

## Functional Description

The combinational stage reduces `din[0]` through `din[NINPUTS-1]` pairwise in
index order using the selected bitwise operation. NAND, NOR, and XNOR apply
bitwise inversion to the final accumulated value.

For `LATENCY > 0`, the result is registered through a `LATENCY`-stage shift
register (identical structure to the `delay` module). The first `LATENCY` output
samples are zero due to pipeline initialization.
