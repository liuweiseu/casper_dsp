# barrel_switcher

## Description

Pipelined lane rotation: `dout[k] = din[(k + sel) mod N]`, N =
2^`N_INPUTS`, `N_INPUTS` cycles later. It corresponds to
casper_library's `barrel_switcher` (`barrel_switcher_init.m`), used inside
[`square_transposer`](square_transposer.md).

The lanes pass through `N_INPUTS` stages of 2:1
[`multiplexer`](../BasicModules/multiplexer.md)s with latency 1. In stage `j`
(1 … `N_INPUTS`) lane `k` keeps its own value or takes lane
`(k + N/2^j) mod N` of the previous stage, selected by bit
`N_INPUTS − j` of `sel` (MSB first). That bit is delayed `j − 1` cycles
so that it meets the data it belongs to, so `sel` is sampled together with
`din`. `sync_out` is `sync_in` delayed `N_INPUTS` cycles.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | log2 of the number of lanes (≥ 1) |
| `DATA_WIDTH` | 8 | Bits per lane |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sel` | input | `N_INPUTS` | Rotation amount, aligned with `din` |
| `sync_in` | input | 1 | Sync in |
| `din` | input | `DATA_WIDTH` × 2^`N_INPUTS` | Input lanes |
| `dout` | output | `DATA_WIDTH` × 2^`N_INPUTS` | Rotated lanes |
| `sync_out` | output | 1 | `sync_in` delayed `N_INPUTS` cycles |
