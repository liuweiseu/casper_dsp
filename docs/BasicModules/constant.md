# constant

## Description

Outputs a fixed compile-time constant. The output is a purely combinational
assignment; no clock is required.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NBITS`   | 8       | Output bit width |
| `VAL`     | 0       | Constant value to output; only the lower `NBITS` bits are used |

## Ports

| Port  | Direction | Width   | Description |
|-------|-----------|---------|-------------|
| `out` | output    | `NBITS` | Constant output, always equal to `VAL[NBITS-1:0]` |
