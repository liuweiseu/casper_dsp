# inverter

## Description

A bitwise inverter with optional pipeline delay. The input word is bitwise inverted
combinationally, then optionally delayed by `LATENCY` flip-flop pipeline stages.
When `LATENCY = 0` (default) the output is purely combinational with no clock
dependency. All pipeline stages are initialized to zero.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8       | Data bit width for input and output |
| `LATENCY` | 0       | Pipeline stages on output; `0` = combinational pass-through |

## Ports

| Port   | Direction | Width    | Description |
|--------|-----------|----------|-------------|
| `clk`  | input     | 1        | Clock signal (unused when `LATENCY = 0`) |
| `din`  | input     | `NBITS`  | Input data |
| `dout` | output    | `NBITS`  | Bitwise-inverted output, delayed by `LATENCY` clock cycles |
