# convert

Fixed-point format converter. Matches the Xilinx System Generator `Convert`
(Type Converter) block (`xbsIndex_r4/Convert`) with fixed-point output, as
used throughout mlib_devel (e.g. `convert_re` / `convert_im` inside `cmult`).

The module performs no arithmetic: it re-represents `din` from
`(N_BITS_IN, BIN_PT_IN)` as `(N_BITS_OUT, BIN_PT_OUT)` in three steps:

1. **Binary-point shift** by `BIN_PT_IN - BIN_PT_OUT` (right shift drops
   LSBs; left shift pads zeros, no precision loss).
2. **Quantization** of the dropped LSBs: Truncate (floor), Round
   (unbiased: ±Inf — ties away from zero), or Round (unbiased: even
   values — ties to even result).
3. **Overflow** handling of the excess MSBs: Wrap (keep low bits) or
   Saturate (clamp to the representable range). The Sysgen "Flag as error"
   mode is not implemented.

Quantization happens before the overflow check, in a work domain widened by
one bit, so a rounding carry (e.g. 0.999… rounding up to 1.0) saturates
correctly. The result passes through `LATENCY` pipeline stages
(0 = combinational). With `ASYNC=1` the `en` port acts as a clock enable on
every pipeline stage. The Sysgen Boolean output type corresponds to
`N_BITS_OUT=1, BIN_PT_OUT=0, TYPE_OUT=0`; floating-point is not implemented.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_IN`    | 37      | Bit width of `din` |
| `BIN_PT_IN`    | 35      | Binary point of `din` |
| `TYPE_IN`      | 1       | Arithmetic type of `din`: 0 = Unsigned, 1 = Signed (2's comp) |
| `N_BITS_OUT`   | 18      | Bit width of `dout` |
| `BIN_PT_OUT`   | 17      | Binary point of `dout` |
| `TYPE_OUT`     | 1       | Arithmetic type of `dout`: 0 = Unsigned, 1 = Signed (2's comp) |
| `QUANTIZATION` | 0       | 0 = Truncate, 1 = Round (unbiased: ±Inf), 2 = Round (unbiased: even values) |
| `OVERFLOW`     | 0       | 0 = Wrap, 1 = Saturate |
| `ASYNC`        | 0       | 1 = `en` port gates the pipeline; 0 = free-running |
| `LATENCY`      | 1       | Number of output pipeline stages; 0 = combinational |

## Ports

| Port   | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk`  | input     | 1     | Clock |
| `rst`  | input     | 1     | Synchronous reset (clears the pipeline) |
| `en`   | input     | 1     | Pipeline clock enable (active when `ASYNC=1`, otherwise ignored) |
| `din`  | input     | `N_BITS_IN`  | Input value |
| `dout` | output    | `N_BITS_OUT` | Re-formatted value |
