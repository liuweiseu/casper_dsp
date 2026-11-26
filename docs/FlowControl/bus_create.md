# bus_create

## Description

Packs an array of equal-width input words into a single concatenated output bus. Each input word `din[i]` is placed at bit position `i * NBITS` in the output, producing a bus of total width `NBITS * INPUT_NUM`. The mapping is combinational.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS` | 8 | Bit width of each individual input word |
| `INPUT_NUM` | 4 | Number of input words to pack |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `din` | input | `NBITS` × `INPUT_NUM` (array) | Array of `INPUT_NUM` input words, each `NBITS` wide |
| `bus_out` | output | `NBITS * INPUT_NUM` | Concatenated output bus |
