# square_transposer

## Description

Transposes N × N blocks (N = 2^`N_INPUTS` lanes × N cycles): sample `i`
of input lane `q` in a block comes out as sample `q` of output lane `i`. It
corresponds to casper_library's `square_transposer` (synchronous path), built
as `square_transposer_init.m` draws it, from delays and a
[`barrel_switcher`](barrel_switcher.md), without RAM:

```
din[q] ─► delay q ─► barrel_switcher input (N − q) mod N
barrel_switcher output q ─► delay N−1−q ─► dout[q]
sel  = N_INPUTS-bit down counter, cleared by sync (0, N−1, N−2, …)
sync ─► barrel_switcher (N_INPUTS) ─► delay N−1 ─► sync_out
```

A block starts the cycle after `sync`. Every path has latency
`N_INPUTS + N − 1`, so the transposed block starts the cycle after
`sync_out`. Because the samples of a block pass the barrel switcher over
`2N − 1` cycles, the next sync must come no earlier than `2N − 1` cycles
later; casper syncs come once per frame, far apart. casper's
`fft_unscrambler` uses it to regroup the outputs of parallel FFTs.

With `ASYNC = 1` (casper `async`) the block works on the stream of valid
samples: `en` enables the select counter and the input delays, the
barrel_switcher's `dvalid` (`en` delayed `N_INPUTS`) enables the output and
sync delays and is the `dvalid` output. A `sync` on an `en = 0` cycle still
clears the counter but is not stored by the sync delay. Verified against
Simulink (MATLAB R2021a) with random `en`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | log2 of the number of lanes (≥ 1) |
| `DATA_WIDTH` | 8 | Bits per lane |
| `ASYNC` | 0 | casper `async`: `1` = gated delays and counter, `dvalid` output (see above) |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Block sync: the block starts the next cycle |
| `din` | input | `DATA_WIDTH` × 2^`N_INPUTS` | Input lanes |
| `en` | input | 1 | Async enable (used when `ASYNC = 1`; default 1) |
| `sync_out` | output | 1 | `sync` delayed `N_INPUTS + N − 1` cycles |
| `dout` | output | `DATA_WIDTH` × 2^`N_INPUTS` | Transposed lanes |
| `dvalid` | output | 1 | `en` delayed `N_INPUTS` (the barrel_switcher's `dvalid`) when `ASYNC = 1`, else 0 |
