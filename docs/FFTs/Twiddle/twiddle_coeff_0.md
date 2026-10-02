# twiddle_coeff_0

## Description

A twiddle stage for `Coeffs = [0]` (w = 1), with delay matching. It
corresponds to casper_library's `twiddle_coeff_0`. Every leg (`ai → ao`,
`bi → bwo`, `sync_in → sync_out`) is only delayed, through a
[`pipeline`](../../Delays/pipeline.md) of

```
LATENCY = 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY
```

This is casper_library's formula. Its source comments that the latency "must
match twiddle_general with single coefficient", so that `butterfly_direct`
can swap twiddle variants transparently. In this repo that holds for a
[`twiddle_general`](twiddle_general.md) with `BRAM_LATENCY = 1`. As in
casper_library, `BRAM_LATENCY` is accepted but does not enter the formula.

## Parameters

| Parameter         | Default | Description |
|-------------------|---------|-------------|
| `N_INPUTS`        | 1       | Number of complex lanes |
| `INPUT_BIT_WIDTH` | 18      | Lane word width (added for the HDL port widths) |
| `MULT_LATENCY`    | 2       | Enters `LATENCY` |
| `ADD_LATENCY`     | 1       | Enters `LATENCY` |
| `BRAM_LATENCY`    | 1       | Accepted for traceability; unused (as in casper_library) |
| `CONV_LATENCY`    | 1       | Enters `LATENCY` |
| `ASYNC`           | 0       | Declared for traceability; must be 0 |

## Ports

The ports are the same as [`twiddle_pass_through`](twiddle_pass_through.md).
All outputs are delayed by `LATENCY`, and `bwo` keeps the input width.
