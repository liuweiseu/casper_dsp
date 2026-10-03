# sample_and_hold

## Description

Port of casper_library's `sample_and_hold` (`casper_library_misc.slx`, SID 158; the block has no init script). A free-running counter restarts on `sync` or when it reaches `PERIOD-1`. Each restart enables the output register one cycle later, so `dout` takes `din` from that cycle.

```
cnt  : counter, ceil(log2(PERIOD)) bits, sync reset = clr
clr  = (cnt >= PERIOD-1) | sync
dout : register (power-on 0), d = din, en = delay(clr, 1)
```

A `sync` at cycle t makes `dout` show `din(t+1)` from cycle t+2. Without `sync`, `din` is resampled every `PERIOD` cycles.

Built from `counter`, `constant`, `relational`, `logical`, `delay` and `register`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PERIOD` | 1024 | Sample period in clocks (mask parameter, stored default). Must be ≥ 2. |
| `BITWIDTH` | 32 | Width of `din`/`dout`. Not a mask parameter: Simulink inherits the width from the input. |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Restarts the sample period |
| `din` | input | `BITWIDTH` | Value to sample |
| `dout` | output | `BITWIDTH` | Held sample |
