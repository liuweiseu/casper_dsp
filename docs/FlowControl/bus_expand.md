# bus_expand

## Description

Splits a wide concatenated input bus into an array of equal-width output words. This is the inverse operation of `bus_create`. Each output word `bus_out[i]` is extracted from bit position `i * WIDTH` of the input bus using the `slice` submodule. The mapping is combinational.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NOUT` | 4 | Number of output words to produce |
| `WIDTH` | 8 | Bit width of each output word |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `bus_in` | input | `NOUT * WIDTH` | Concatenated input bus |
| `bus_out` | output | `WIDTH` × `NOUT` (array) | Array of `NOUT` output words, each `WIDTH` wide |
