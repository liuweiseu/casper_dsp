# register

## Description

A register with enable control. On each rising clock edge, if reset is asserted the output is cleared to zero; if enable is asserted the input data is latched to the output. The output holds its value when enable is de-asserted.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BITWIDTH` | 1 | Data bit width |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `rst` | input | 1 | Synchronous reset (active high); clears output to zero |
| `en` | input | 1 | Enable signal (active high); latches input data to output |
| `d` | input | `BITWIDTH` | Input data |
| `q` | output | `BITWIDTH` | Output data |
