# ri_to_c

## Description

Packs a real part and an imaginary part into a single complex word by bit-concatenation. The real part occupies the high bits and the imaginary part occupies the low bits of the output: `c = {re, im}`. The operation is purely combinational with no clock or reset required.

This is the inverse of the `c_to_ri` operation. It is commonly used to prepare two real-valued data streams for input to a complex FFT core.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `RE_WIDTH` | 8 | Bit width of the real input |
| `IM_WIDTH` | 8 | Bit width of the imaginary input |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `re` | input  | `RE_WIDTH` | Real part |
| `im` | input  | `IM_WIDTH` | Imaginary part |
| `c`  | output | `RE_WIDTH + IM_WIDTH` | Packed complex word: `re` in high bits, `im` in low bits |
