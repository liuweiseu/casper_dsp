# register

## Description

A parameterized synchronous register. On each rising clock edge the output is updated according to the active combination of `USE_RST` and `USE_ENABLE`. When neither feature is needed the module becomes a plain D flip-flop array that latches the input every cycle.

## Parameters

| Parameter    | Default | Description |
|--------------|---------|-------------|
| `BITWIDTH`   | 1       | Data bit width |
| `USE_RST`    | 1       | `1` = include synchronous reset logic (`rst` pin loads `INIT_VAL` when asserted); `0` = reset pin is ignored |
| `USE_ENABLE` | 1       | `1` = include enable logic (`en` pin must be asserted to latch input data); `0` = enable pin is ignored and data is latched every cycle |
| `INIT_VAL`   | 0       | Value loaded into `q` when `rst` is asserted. Only the lower `BITWIDTH` bits are used |

## Ports

| Port  | Direction | Width      | Description |
|-------|-----------|------------|-------------|
| `clk` | input     | 1          | Clock signal |
| `rst` | input     | 1          | Synchronous reset (active high); loads `INIT_VAL` into output. Has effect only when `USE_RST=1` |
| `en`  | input     | 1          | Enable signal (active high); gates data latching. Has effect only when `USE_ENABLE=1` |
| `d`   | input     | `BITWIDTH` | Input data |
| `q`   | output    | `BITWIDTH` | Registered output data |

## Behaviour by parameter combination

| `USE_RST` | `USE_ENABLE` | Behaviour |
|-----------|--------------|-----------|
| 1         | 1            | `rst` loads `INIT_VAL`; `en` gates latching; `rst` takes priority over `en` |
| 1         | 0            | `rst` loads `INIT_VAL`; `d` is always latched when not in reset |
| 0         | 1            | `en` gates latching; no reset available |
| 0         | 0            | `d` is latched every clock cycle (plain register) |
