# window_delay

## Description

Port of casper_library's `window_delay` (`casper_library_delays.slx`, SID 240; no init script). It delays a window (level) signal by `DELAY` cycles. Instead of a `DELAY`-deep shift register, it delays the signal's edges with two `sync_delay` counters.

```
rise = rising edge of din, fall = falling edge of din   (edge_detect)
dout : register (power-on 0), d = en = sync_delay(rise, DELAY-1),
                              rst    = sync_delay(fall, DELAY-1)
```

`dout(t) = din(t-DELAY)` holds as long as same-kind edges are at least `DELAY-1` cycles apart. A closer edge restarts its `sync_delay` and the earlier edge is lost, which is also how Simulink behaves.

The edge detectors power on with a previous value of 0, so `din = 1` from cycle 0 counts as a rising edge and `dout` rises at cycle `DELAY`. A delayed rise and a delayed fall can never coincide, so the register's reset/enable priority does not matter.

Built from `edge_detect` ×2, `sync_delay` ×2 and `register`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DELAY` | 10 | Delay in cycles (mask parameter, stored default). The mask does not check it; values below 1 trigger a `$fatal`. |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | 1 | Window signal |
| `dout` | output | 1 | `din` delayed by `DELAY` cycles |
