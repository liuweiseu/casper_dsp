# multiplier

Fixed-point pipelined multiplier, `p = a × b`. Matches the Xilinx System
Generator `Mult` block (`xbsIndex_r4/Mult`) as used throughout mlib_devel
(e.g. the four real multipliers inside `cmult`).

Two output modes:

- **Full precision** (`PRECISION=0`): the exact product. Output width is
  `N_BITS_A + N_BITS_B` with binary point `BIN_PT_A + BIN_PT_B`. No
  quantization or overflow logic.
- **User defined** (`PRECISION=1`): the product is converted to
  `N_BITS_OUT` bits at `BIN_PT_OUT`, applying the selected quantization
  (Truncate or Round unbiased ±Inf, i.e. ties away from zero) followed by
  the selected overflow handling (Wrap or Saturate). The Sysgen
  "Flag as error" overflow mode is not implemented.

The result passes through `LATENCY` pipeline stages (0 = combinational
output). With `ASYNC=1` the optional `en` port acts as a clock enable on
every pipeline stage — when `en` is low the pipeline holds its state. With
`ASYNC=0` the `en` port is ignored.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_A`     | 18      | Bit width of input `a` |
| `BIN_PT_A`     | 17      | Binary point of input `a` |
| `N_BITS_B`     | 18      | Bit width of input `b` |
| `BIN_PT_B`     | 17      | Binary point of input `b` |
| `TYPE_A`       | 1       | Arithmetic type of `a`: 0 = Unsigned, 1 = Signed (2's comp) |
| `TYPE_B`       | 1       | Arithmetic type of `b`: 0 = Unsigned, 1 = Signed (2's comp) |
| `PRECISION`    | 0       | 0 = Full, 1 = User defined |
| `N_BITS_OUT`   | 36      | Output bit width (`PRECISION=1` only) |
| `BIN_PT_OUT`   | 34      | Output binary point (`PRECISION=1` only) |
| `TYPE_OUT`     | 1       | Output arithmetic type (`PRECISION=1` only): 0 = Unsigned, 1 = Signed |
| `QUANTIZATION` | 0       | 0 = Truncate, 1 = Round (unbiased: ±Inf) (`PRECISION=1` only) |
| `OVERFLOW`     | 0       | 0 = Wrap, 1 = Saturate (`PRECISION=1` only) |
| `ASYNC`        | 0       | 1 = `en` port gates the pipeline; 0 = free-running |
| `LATENCY`      | 2       | Number of output pipeline stages; 0 = combinational |

## Ports

| Port  | Direction | Width | Description |
|-------|-----------|-------|-------------|
| `clk` | input     | 1     | Clock |
| `rst` | input     | 1     | Synchronous reset (clears the pipeline) |
| `en`  | input     | 1     | Pipeline clock enable (active when `ASYNC=1`, otherwise ignored) |
| `a`   | input     | `N_BITS_A` | Multiplicand |
| `b`   | input     | `N_BITS_B` | Multiplier |
| `p`   | output    | `N_BITS_A+N_BITS_B` (Full) or `N_BITS_OUT` (User defined) | Product |
