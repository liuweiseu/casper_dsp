# slice

## Description

A combinational bit-field extractor. Selects a contiguous range of bits from the input bus, starting at `START_BIT` with a width of `WIDTH` bits, and presents them at the output. Equivalent to the Verilog expression `dout = din[START_BIT + WIDTH - 1 : START_BIT]`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS` | 8 | Total bit width of the input bus |
| `START_BIT` | 0 | Index of the least significant bit to extract |
| `WIDTH` | 1 | Number of bits to extract |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `din` | input | `NBITS` | Input data bus |
| `dout` | output | `WIDTH` | Extracted bit field |
