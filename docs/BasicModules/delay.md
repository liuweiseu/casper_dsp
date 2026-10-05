# delay

## Description

A shift-register pipeline delay modelled on the Xilinx System Generator Delay block. The input is delayed by `LATENCY` clock cycles. `LATENCY = 0` is a plain wire, and `rst`/`en` are then ignored. All stages power on at zero.

On each clock edge (from the Sysgen block model `data/sysgen/block_models/xlDelay.sgm`):

- `rst` (when `USE_RST = 1`) clears every stage.
- `en`, or always when `USE_ENABLE = 0`, then shifts: stage 0 takes `din`, and each later stage takes the one before it.

The two apply in that order. So when `rst` and `en` are high together, stage 0 takes `din` and the other stages clear.

`rst` and `en` have default values (0 and 1). An instance that does not use them may leave them unconnected.

Mask mapping: `latency` → `LATENCY`, `rst` → `USE_RST`, `en` → `USE_ENABLE`. `reg_retiming` only selects the HDL style.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `LATENCY` | 1 | Number of clock cycles of delay; 0 = wire |
| `BITWIDTH` | 1 | Data bit width |
| `USE_RST` | 0 | 1 = `rst` synchronously clears every stage |
| `USE_ENABLE` | 0 | 1 = shift only when `en` is high |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `din` | input | `BITWIDTH` | Input data |
| `rst` | input | 1 | Synchronous reset, clears all stages (used when `USE_RST = 1`; default 0) |
| `en` | input | 1 | Shift enable (used when `USE_ENABLE = 1`; default 1) |
| `dout` | output | `BITWIDTH` | Output data, delayed by `LATENCY` clock cycles |
