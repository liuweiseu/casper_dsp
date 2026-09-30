# pipeline

## Description

A plain register pipeline with no reset and no enable: `dout` is `din`
delayed by `LATENCY` clock cycles. It is a thin wrapper around
[`delay_srl`](delay_srl.md) with `USE_RST = 0` and `USE_ENABLE = 0`. The
parameter name follows casper_library's `delays/pipeline` block. Every stage
powers up to 0.

## Parameters

| Parameter  | Default | Description |
|------------|---------|-------------|
| `BITWIDTH` | 8       | Data width |
| `LATENCY`  | 1       | Number of register stages; `0` = combinational pass-through |

## Ports

| Port   | Direction | Width      | Description |
|--------|-----------|------------|-------------|
| `clk`  | input     | 1          | Clock (unused when `LATENCY = 0`) |
| `din`  | input     | `BITWIDTH` | Input |
| `dout` | output    | `BITWIDTH` | `din` delayed by `LATENCY` cycles |
