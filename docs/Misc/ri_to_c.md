# ri_to_c

## Description

Packs a real part and an imaginary part into a single complex word by bit-concatenation. The real part occupies the high bits and the imaginary part occupies the low bits of the output: `c = {re, im}`. The operation is purely combinational with no clock or reset required.

This is the inverse of `c_to_ri`. It is commonly used to combine two real-valued data streams into the packed complex format expected by complex FFT cores.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS` | 8 | Bit width of each input (`re` and `im`) |

## Ports

| Port | Direction | Width    | Description |
|------|-----------|----------|-------------|
| `re` | input     | `NBITS`  | Real part |
| `im` | input     | `NBITS`  | Imaginary part |
| `c`  | output    | `2×NBITS` | Packed complex word: `re` in high bits, `im` in low bits |
