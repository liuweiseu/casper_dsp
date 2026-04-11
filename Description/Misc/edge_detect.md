# edge_detect

## Description

Detects rising or falling edges on a single-bit input signal. On each clock cycle, the module compares the current input with the previous cycle's value to identify the configured edge type. The output polarity is also configurable. The output is registered (one cycle latency).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `EDGE_TYPE` | 0 | Edge to detect: 0 = rising edge, 1 = falling edge |
| `OUTPUT_POL` | 0 | Output polarity: 0 = active high, 1 = active low |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `din` | input | 1 | Input signal to monitor |
| `dout` | output | 1 | Edge detection output; pulses for one cycle when the configured edge is detected |
