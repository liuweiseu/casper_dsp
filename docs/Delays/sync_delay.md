# sync_delay

## Description

Delays a sync pulse by `DELAY_LEN` cycles. It corresponds to casper_library's
`sync_delay`. Following `sync_delay_init.m`, it uses a loadable down counter
instead of a `DELAY_LEN`-deep shift register:

```
din = 1          : cnt <= DELAY_LEN    (a pulse restarts the delay)
else if cnt != 0 : cnt <= cnt − 1
dout             = (cnt == 1)
```

A single pulse on `din` reappears on `dout` exactly `DELAY_LEN` cycles later.
This differs from a plain delay line when pulses are closer together than
`DELAY_LEN`: each new pulse restarts the count, so only the last one comes
out. casper sync pulses (one per frame) are always at least `DELAY_LEN` apart,
so this does not arise in normal use.

- `DELAY_LEN = 0` passes `din` straight through.
- The counter is a [`register`](../BasicModules/register.md) and powers up to 0.
- casper's `use_enable` (`sync_delay_en`) and `prog_delay` variants are not
  implemented.

[`fft_stage_n`](../FFTs/fft_stage_n.md) uses it to delay the butterfly sync.

## Parameters

| Parameter   | Default | Description |
|-------------|---------|-------------|
| `DELAY_LEN` | 16      | Delay in cycles; `0` = pass-through |

## Ports

| Port   | Direction | Width | Description |
|--------|-----------|-------|-------------|
| `clk`  | input     | 1     | Clock |
| `din`  | input     | 1     | Sync pulse in |
| `dout` | output    | 1     | Sync pulse, `DELAY_LEN` cycles later |
