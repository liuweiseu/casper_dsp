# addersubtracter

Fixed-point pipelined adder/subtracter, `c = a ± b`. Matches the Xilinx
System Generator `AddSub` block (`xbsIndex_r4/AddSub`) with its Basic-tab
options, as used throughout mlib_devel (e.g. `addsub_re` / `addsub_im`
inside `cmult`).

Inputs are aligned at their binary points, then added or subtracted at full
precision: the output binary point is `max(BIN_PT_A, BIN_PT_B)`, the integer
part is `max` of the input integer widths, and one growth bit is added. No
quantization or overflow logic (full precision only).

The operation is selected by `MODE`: fixed addition, fixed subtraction, or
runtime selection through the `sub` port (0 = add, 1 = subtract). The result
passes through `LATENCY` pipeline stages (0 = combinational). With `ASYNC=1`
the `en` port acts as a clock enable on every pipeline stage.

Carry semantics follow the Xilinx `c_addsub` core: with `USE_CARRY_IN=1`,
addition computes `a + b + cin` and subtraction computes `a - b - 1 + cin`
(`a + ~b + cin`). With `USE_CARRY_OUT=1`, `cout` is the carry out of the
result MSB (for subtraction this is the not-borrow flag); otherwise `cout`
is constant 0.

## Parameters

| Parameter       | Default | Description |
|-----------------|---------|-------------|
| `N_BITS_A`      | 18      | Bit width of input `a` |
| `BIN_PT_A`      | 17      | Binary point of input `a` |
| `TYPE_A`        | 1       | Arithmetic type of `a`: 0 = Unsigned, 1 = Signed (2's comp) |
| `N_BITS_B`      | 18      | Bit width of input `b` |
| `BIN_PT_B`      | 17      | Binary point of input `b` |
| `TYPE_B`        | 1       | Arithmetic type of `b`: 0 = Unsigned, 1 = Signed (2's comp) |
| `MODE`          | 0       | 0 = Addition, 1 = Subtraction, 2 = Addition or subtraction (`sub` port) |
| `USE_CARRY_IN`  | 0       | 1 = `cin` port active, 0 = ignored |
| `USE_CARRY_OUT` | 0       | 1 = `cout` port active, 0 = constant 0 |
| `ASYNC`         | 0       | 1 = `en` port gates the pipeline; 0 = free-running |
| `LATENCY`       | 1       | Number of output pipeline stages; 0 = combinational |

## Ports

| Port   | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk`  | input     | 1     | Clock |
| `rst`  | input     | 1     | Synchronous reset (clears the pipeline) |
| `en`   | input     | 1     | Pipeline clock enable (active when `ASYNC=1`, otherwise ignored) |
| `sub`  | input     | 1     | Operation select (active when `MODE=2`): 0 = add, 1 = subtract |
| `cin`  | input     | 1     | Carry in (active when `USE_CARRY_IN=1`, otherwise ignored) |
| `a`    | input     | `N_BITS_A` | First operand |
| `b`    | input     | `N_BITS_B` | Second operand |
| `c`    | output    | `max(int widths) + max(BIN_PT_A, BIN_PT_B) + 1` | Sum or difference |
| `cout` | output    | 1     | Carry out of the result MSB (0 when `USE_CARRY_OUT=0`) |
