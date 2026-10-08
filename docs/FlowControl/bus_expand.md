# bus_expand

## Description

Splits a wide concatenated input bus into an array of equal-width output words. This is the inverse operation of `bus_create`. Each output word `bus_out[i]` is extracted from bit position `i * OUTPUT_WIDTH` of the input bus using the `slice` submodule. The mapping is combinational.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `OUTPUT_NUM` | 4 | Number of output words to produce |
| `OUTPUT_WIDTH` | 8 | Bit width of each output word |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `bus_in` | input | `OUTPUT_NUM * OUTPUT_WIDTH` | Concatenated input bus |
| `bus_out` | output | `OUTPUT_WIDTH` × `OUTPUT_NUM` (array) | Array of `OUTPUT_NUM` output words, each `OUTPUT_WIDTH` wide |
