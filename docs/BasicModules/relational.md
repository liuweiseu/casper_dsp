# relational

## Description

Compares two unsigned input buses `a` and `b` and outputs a single-bit result
according to the selected comparison operator. An optional pipeline register can
be inserted via the `LATENCY` parameter.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8       | Bit width of inputs `a` and `b` |
| `COMP`    | 0       | Comparison operator (see table below) |
| `LATENCY` | 1       | `0` = combinational output; `>=1` = number of pipeline register stages |

### `COMP` values

| Value | Operation       | Expression  |
|-------|-----------------|-------------|
| 0     | Equal           | `a == b`    |
| 1     | Not equal       | `a != b`    |
| 2     | Less than       | `a < b`     |
| 3     | Greater than    | `a > b`     |
| 4     | Less or equal   | `a <= b`    |
| 5     | Greater or equal| `a >= b`    |

All comparisons are **unsigned**.

## Ports

| Port  | Direction | Width    | Description |
|-------|-----------|----------|-------------|
| `clk` | input     | 1        | Clock signal (unused when `LATENCY=0`) |
| `a`   | input     | `NBITS`  | First operand |
| `b`   | input     | `NBITS`  | Second operand |
| `out` | output    | 1        | Comparison result (`1` = true, `0` = false) |

## Behaviour

`out` reflects the result of comparing `a` and `b` using the operator selected
by `COMP`. With `LATENCY=0` the output is purely combinational; with `LATENCY=N`
the result passes through `N` pipeline registers, introducing `N` clock cycles
of latency.
