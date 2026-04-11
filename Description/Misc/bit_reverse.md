# bit_reverse

## Description

Reverses the bit order of the input word. The most significant bit of the input becomes the least significant bit of the output, and vice versa. The operation is purely combinational.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS` | 8 | Bit width of the input and output |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `din` | input | `NBITS` | Input data |
| `dout` | output | `NBITS` | Bit-reversed output data |
