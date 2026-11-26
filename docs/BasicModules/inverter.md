# inverter

## Description

A bitwise inverter with optional pipeline delay. The input word is bitwise inverted
combinationally, then optionally delayed by `LATENCY` flip-flop pipeline stages.
When `LATENCY = 0` the output is purely combinational with no clock
dependency. The default `LATENCY = 1` matches the Xilinx Inverter block. An
optional enable (`USE_ENABLE`) holds the pipeline registers while `en` is
low, as in the Xilinx block's "Provide enable port". All pipeline stages are
initialized to zero.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8       | Data bit width for input and output |
| `LATENCY` | 1       | Pipeline stages on output; `0` = combinational pass-through |
| `USE_ENABLE` | 0    | `1` = the pipeline registers update only when `en` is high (no effect when `LATENCY = 0`) |

## Ports

| Port   | Direction | Width    | Description |
|--------|-----------|----------|-------------|
| `clk`  | input     | 1        | Clock signal (unused when `LATENCY = 0`) |
| `en`   | input     | 1        | Pipeline enable (used when `USE_ENABLE = 1`; default 1, may be left unconnected) |
| `din`  | input     | `NBITS`  | Input data |
| `dout` | output    | `NBITS`  | Bitwise-inverted output, delayed by `LATENCY` clock cycles |
