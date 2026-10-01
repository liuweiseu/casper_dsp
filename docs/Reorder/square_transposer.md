# square_transposer

## Description

Transposes N × N blocks (N = 2^`LOG2_N_LANES` lanes × N cycles): sample `i`
of input lane `q` in a block comes out as sample `q` of output lane `i`. It
corresponds to casper_library's `square_transposer` (synchronous path), built
as `square_transposer_init.m` draws it, from delays and a
[`barrel_switcher`](barrel_switcher.md), without RAM:

```
din[q] ─► delay q ─► barrel_switcher input (N − q) mod N
barrel_switcher output q ─► delay N−1−q ─► dout[q]
sel  = LOG2_N_LANES-bit down counter, cleared by sync (0, N−1, N−2, …)
sync ─► barrel_switcher (LOG2_N_LANES) ─► delay N−1 ─► sync_out
```

A block starts the cycle after `sync`. Every path has latency
`LOG2_N_LANES + N − 1`, so the transposed block starts the cycle after
`sync_out`. Because the samples of a block pass the barrel switcher over
`2N − 1` cycles, the next sync must come no earlier than `2N − 1` cycles
later; casper syncs come once per frame, far apart. casper's
`fft_unscrambler` uses it to regroup the outputs of parallel FFTs.

`ASYNC` (casper's asynchronous variant) is declared for traceability and must
be 0.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `LOG2_N_LANES` | 1 | log2 of the number of lanes (≥ 1) |
| `DATA_WIDTH` | 8 | Bits per lane |
| `ASYNC` | 0 | Must be 0 |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Block sync: the block starts the next cycle |
| `din` | input | `DATA_WIDTH` × 2^`LOG2_N_LANES` | Input lanes |
| `sync_out` | output | 1 | `sync` delayed `LOG2_N_LANES + N − 1` cycles |
| `dout` | output | `DATA_WIDTH` × 2^`LOG2_N_LANES` | Transposed lanes |
