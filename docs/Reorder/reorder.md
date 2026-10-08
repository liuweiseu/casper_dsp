# reorder

## Description

Permutes every frame of `MAP_LEN` samples by a fixed map: output step `k` of
a frame is input sample `map[k]` of the previous frame. It corresponds to
casper_library's `reorder` with `double_buffer = 0` and `en` always 1, as
casper's FFT blocks use it. All `N_INPUTS` streams share the addresses and
are stored side by side in one read-before-write
[`single_port_ram`](../Delays/single_port_ram.md).

In the f-th frame after a sync the RAM is addressed with `map^f(k)` (the map
composed f times); a read-before-write access then returns the sample that
was written to that address one frame earlier. `map^f` repeats with period
`ORDER`, the lcm of the map's cycle lengths (`compute_order.m`). As in
`reorder_init.m`, `ORDER` selects the address generator:

| `ORDER` | Implementation |
|---------|----------------|
| 1 | identity map: a [`delay_bram`](../Delays/delay_bram.md) of `MAP_LEN + BRAM_LATENCY + FANOUT_LATENCY` |
| 2 | `(MAP_BITS+1)`-bit frame counter; address = MSB ? `map[k]` : `k` |
| > 2 | `current_map` [`dual_port_ram`](../Delays/dual_port_ram.md) holding `map^f`: identity in the first frame after a sync, then updated in place with `p_{f+1}[k] = map[p_f[k]]` |

All orders are supported, so every map that `fft_unscrambler` or
`bi_real_unscr_4x` generates can be used (fft_unscrambler maps reach orders
above 2 for most `FFTSize` / `n_inputs` combinations).

### Generating the map

`MAP_INIT_FILE` holds the map, row `k` = `map[k]` as one hexadecimal word.
Generate it, and the matching `MAP_LEN` and `ORDER`, with
`rtl/Reorder/scripts/gen_reorder_map.py`:

```bash
python3 rtl/Reorder/scripts/gen_reorder_map.py --map 0 7 1 3 2 5 6 4 -o map.mem
python3 rtl/Reorder/scripts/gen_reorder_map.py --bi-real even --fft-size 5 -o even.mem
python3 rtl/Reorder/scripts/gen_reorder_map.py --unscrambler --fft-size 8 --log2-n-groups 2 -o unscr.mem
```

`MAP_LEN` must be a power of two.

### Timing

With `REP = log2(N_INPUTS)` (casper's fan-out tree for the address) and

```
PRE = MAP_LATENCY + 1    (ORDER = 2)
PRE = MAP_LATENCY + 2    (ORDER = 1 or > 2)
```

the data reach the RAM `PRE + REP` cycles after `din` and leave it
`BRAM_LATENCY + FANOUT_LATENCY` cycles later. `sync_out` is `sync` delayed by
`PRE + REP`, then by a [`sync_delay`](../Delays/sync_delay.md) of `MAP_LEN`,
then by `BRAM_LATENCY + FANOUT_LATENCY`, so it marks the first sample of the
first reordered frame. `valid` rises `PRE + REP + BRAM_LATENCY +
FANOUT_LATENCY` cycles after power-up and stays high (en = 1).

### Sync

The frame counter is cleared by `sync`, so syncs must come every
`ORDER · MAP_LEN` cycles (or a multiple), as casper designs guarantee: then
the frame after a sync (identity addresses) follows a frame addressed with
`map^(ORDER-1)`. Syncs closer together than two cycles are not supported for
`ORDER > 2`.

### Not implemented

`DOUBLE_BUFFER` and `SOFTWARE_CONTROLLED` are declared for traceability and
must be 0 (`$fatal` otherwise); `BRAM_MAP` (memory type of the map ROM) is
ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | Number of parallel streams reordered with the same map |
| `N_BITS` | 8 | Bits per stream sample |
| `MAP_LEN` | 8 | Frame length (power of two ≥ 2) |
| `ORDER` | 4 | Order of the map (from `gen_reorder_map.py`) |
| `MAP_INIT_FILE` | `""` | Map table, one hex word per line |
| `MAP_LATENCY` | 2 | casper `map_latency` |
| `BRAM_LATENCY` | 1 | Data RAM read latency (≥ 1) |
| `FANOUT_LATENCY` | 0 | casper `fanout_latency`: extra output pipeline |
| `PLATFORM` | `"GENERIC"` | Memory primitives: `GENERIC`, `XILINX`, `ALTERA` |
| `DOUBLE_BUFFER` | 0 | Must be 0 |
| `SOFTWARE_CONTROLLED` | 0 | Must be 0 |
| `BRAM_MAP` | 1 | Ignored |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Frame sync; clears the frame counter |
| `din` | input | `N_BITS` × `N_INPUTS` | Input streams |
| `sync_out` | output | 1 | Marks the first sample of the first reordered frame |
| `valid` | output | 1 | High once the pipeline has filled |
| `dout` | output | `N_BITS` × `N_INPUTS` | Reordered streams |
