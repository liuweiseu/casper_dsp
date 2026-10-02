# c_to_ri

## Description

Unpacks a single complex word into separate real and imaginary parts by bit-slicing. The real part is taken from the high bits and the imaginary part from the low bits: `re = c[2×NBITS-1:NBITS]`, `im = c[NBITS-1:0]`. The operation is purely combinational with no clock or reset required.

`BIN_PT` records the binary point position of the fixed-point representation for documentation and downstream toolflow use; it does not affect the hardware bit-level behaviour.

This is the inverse of `ri_to_c`. It is commonly used to extract individual real-valued outputs from a complex FFT core.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8  | Bit width of each output (`re` and `im`) |
| `BIN_PT`  | 7  | Binary point position (metadata only, does not affect bit layout) |

## Ports

| Port | Direction | Width    | Description |
|------|-----------|----------|-------------|
| `c`  | input     | `2×NBITS` | Packed complex word: `re` in high bits, `im` in low bits |
| `re` | output    | `NBITS`  | Real part |
| `im` | output    | `NBITS`  | Imaginary part |
