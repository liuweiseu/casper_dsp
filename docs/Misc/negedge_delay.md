# negedge_delay

## Description

Port of casper_library's `negedge_delay` (`casper_library_misc.slx`, SID 77). It stretches the falling edge of a level signal: `dout` stays high for `PULSE_LEN` cycles after `din` drops.

```
bits = ceil(log2(PULSE_LEN+1))
ne   = falling edge of din (edge_detect)
cnt  : counter, bits wide, sync reset = ne, enable = run
run  = (cnt <= PULSE_LEN-2)
dout = din | delay(din, 1) | run
```

Equivalently, `dout(t) = OR(din(t-PULSE_LEN) .. din(t)) | (t <= PULSE_LEN-2)`. Because the counter powers on at 0, `dout` is high for the first `PULSE_LEN-1` cycles regardless of `din`.

Built from `edge_detect`, `counter`, `constant`, `relational`, `delay` and `logical`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `PULSE_LEN` | 5 | Length of the stretch (mask parameter, stored default). Values below 3 trigger a `$fatal`, matching the mask's "Minimum length is 3." |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | 1 | Level input |
| `dout` | output | 1 | `din` with each falling edge delayed by `PULSE_LEN` cycles |
