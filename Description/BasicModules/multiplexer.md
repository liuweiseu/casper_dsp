# multiplexer

## Description

Selects one of `NINPUTS` input buses and forwards it to the output.
The selection is controlled by the `sel` signal. An optional pipeline
register can be inserted via the `LATENCY` parameter.

## Parameters

| Parameter  | Default | Description |
|------------|---------|-------------|
| `NBITS`    | 8       | Bit width of each input and the output |
| `NINPUTS`  | 2       | Number of input buses to select from |
| `LATENCY`  | 1       | `0` = combinational output; `>=1` = number of pipeline register stages |

## Ports

| Port   | Direction | Width                   | Description |
|--------|-----------|-------------------------|-------------|
| `clk`  | input     | 1                       | Clock signal (unused when `LATENCY=0`) |
| `din`  | input     | `NBITS` × `NINPUTS`     | Input buses (unpacked array: `din[0]` … `din[NINPUTS-1]`) |
| `sel`  | input     | `⌈log₂(NINPUTS)⌉`       | Selects which input is forwarded to the output |
| `dout` | output    | `NBITS`                 | Selected output |

## Behaviour

`dout` reflects `din[sel]`. With `LATENCY=0` the output is purely
combinational; with `LATENCY=N` the result passes through `N` pipeline
registers, introducing `N` clock cycles of latency.
