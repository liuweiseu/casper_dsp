# delay

## Description

A shift-register based pipeline delay. The input data is delayed by `LATENCY` clock cycles before appearing at the output. All stages are initialized to zero at simulation start.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `LATENCY` | 1 | Number of clock cycles of delay |
| `BITWIDTH` | 1 | Data bit width |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `din` | input | `BITWIDTH` | Input data |
| `dout` | output | `BITWIDTH` | Output data, delayed by `LATENCY` clock cycles |
