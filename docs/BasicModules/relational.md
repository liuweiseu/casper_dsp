# relational

## Description

Compares two input buses `a` and `b` (unsigned, or two's complement with `SIGNED = 1`) and outputs a single-bit result
according to the selected comparison operator. An optional pipeline register can
be inserted via the `LATENCY` parameter.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8       | Bit width of inputs `a` and `b` |
| `COMP`    | 0       | Comparison operator (see table below) |
| `LATENCY` | 1       | `0` = combinational output; `>=1` = number of pipeline register stages |
| `SIGNED`  | 0       | `0` = unsigned comparison; `1` = `a` and `b` are two's complement |
| `USE_ENABLE` | 0       | `1` = the pipeline registers update only when `en` is high (Xilinx "Provide enable port"); no effect when `LATENCY = 0` |

### `COMP` values

| Value | Operation       | Expression  |
|-------|-----------------|-------------|
| 0     | Equal           | `a == b`    |
| 1     | Not equal       | `a != b`    |
| 2     | Less than       | `a < b`     |
| 3     | Greater than    | `a > b`     |
| 4     | Less or equal   | `a <= b`    |
| 5     | Greater or equal| `a >= b`    |

Comparisons are unsigned by default and signed when `SIGNED = 1`.

## Ports

| Port  | Direction | Width    | Description |
|-------|-----------|----------|-------------|
| `clk` | input     | 1        | Clock signal (unused when `LATENCY=0`) |
| `en`  | input     | 1        | Pipeline enable (used when `USE_ENABLE = 1`; default 1, may be left unconnected) |
| `a`   | input     | `NBITS`  | First operand |
| `b`   | input     | `NBITS`  | Second operand |
| `out` | output    | 1        | Comparison result (`1` = true, `0` = false) |

## Behaviour

`out` reflects the result of comparing `a` and `b` using the operator selected
by `COMP`. With `LATENCY=0` the output is purely combinational; with `LATENCY=N`
the result passes through `N` pipeline registers, introducing `N` clock cycles
of latency. With `USE_ENABLE = 1` the pipeline registers hold while `en` is
low.
