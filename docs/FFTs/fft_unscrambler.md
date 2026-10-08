# fft_unscrambler

## Description

Reorders the outputs of casper's `fft_direct` into natural order. It
corresponds to casper_library's `fft_unscrambler` (fixed point, sync mode,
`fft_unscrambler_init.m`), as `fft_wideband_real` uses it. There are
`G = 2^N_INPUTS` input groups, each carrying `N_STREAMS` complex signals:

```
each group's N_STREAMS signals ─► one word (casper bus_create)
G words ─► square_transposer (its N_INPUTS = N_INPUTS)
        ─► reorder (G streams, MAP_LEN = 2^(FFT_SIZE−N_INPUTS))
        ─► split back into N_STREAMS signals per group (bus_expand)
sync ─► square_transposer ─► reorder ─► sync_out
```

The first stage is a [`square_transposer`](../Reorder/square_transposer.md)
and the second a [`reorder`](../Reorder/reorder.md).

### Map and order

casper builds the map as

```
part = [0 : 2^(FFT_SIZE−2·N_INPUTS) − 1] · G
map  = [part + 0, part + 1, …, part + G − 1]
```

In other words, `map[k]` rotates the `m`-bit index `k` left by
`N_INPUTS` bits, where `m = FFT_SIZE − N_INPUTS`. Its order is
therefore `m / gcd(m, N_INPUTS)`. The module computes this itself and
passes it to the reorder; it often exceeds 2, and `reorder` supports every
order. The formula was checked against casper's `compute_order` for all 61
valid combinations with `FFT_SIZE ≤ 16`.

Generate `MAP_INIT_FILE` with:

```bash
python3 rtl/Reorder/scripts/gen_reorder_map.py --unscrambler --fft-size FFT_SIZE \
        --log2-n-groups N_INPUTS -o map.mem
```

### Derived reorder parameters (as `fft_unscrambler_init.m`)

| Quantity | Value |
|----------|-------|
| `bram_map` | `2^(FFT_SIZE−1)·(FFT_SIZE−1) ≥ 2^COEFFS_BIT_LIMIT` and `2^(FFT_SIZE−1) ≥ BRAM_LATENCY` |
| `map_latency` | `bram_map ? (FFT_SIZE−1 > 11 ? 3 : 2) : 1` |
| `fanout_latency` | `max(0, (FFT_SIZE−N_INPUTS) + ceil(log2(N_BITS_IN·N_INPUTS·2)) − 15 + 2)` |

casper uses `n_inputs` (= `N_INPUTS`) in the `fanout_latency` formula,
not `2^n_inputs`; this module does the same.

### Ports, sync and limits

- Element `k` of `din` / `dout` is casper's `in<s><g>` / `out<s><g>` with
  `k = s·G + g` (stream `s`, group `g`), the casper port order.
- The reorder needs a sync every `ORDER · 2^(FFT_SIZE−N_INPUTS)` cycles
  (or a multiple of that).
- `1 ≤ N_INPUTS < FFT_SIZE − 2` is required. casper raises an error
  for `n_inputs ≥ FFTSize − 2`, and its square_transposer is an empty block
  for `n_inputs = 0`.
- `2·N_INPUTS ≤ FFT_SIZE` is also required; otherwise casper's `part`,
  and so its map, is empty.
- `ASYNC` (casper's `en` / `dvalid`) must be 0. Floating point is not
  implemented.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_STREAMS` | 2 | Complex signals per group |
| `FFT_SIZE` | 15 | casper `FFTSize` of the unscrambler (fft_wideband_real passes its own FFTSize − 1) |
| `N_INPUTS` | 2 | casper `n_inputs`: log2 of the number of groups |
| `N_BITS_IN` | 18 | Width of the real and imaginary parts |
| `BRAM_LATENCY` | 2 | Reorder RAM latency |
| `COEFFS_BIT_LIMIT` | 8 | Threshold for a BRAM map (see above) |
| `MAP_INIT_FILE` | `""` | Unscrambler map (from `gen_reorder_map.py --unscrambler`) |
| `PLATFORM` | `"GENERIC"` | Memory primitives: `GENERIC`, `XILINX`, `ALTERA` |
| `ASYNC` | 0 | Must be 0 |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Frame sync |
| `din_re`, `din_im` | input | `N_BITS_IN` × `N_STREAMS·G` | Inputs, element `s·G + g` |
| `sync_out` | output | 1 | Sync of the reorder output |
| `dout_re`, `dout_im` | output | `N_BITS_IN` × `N_STREAMS·G` | Unscrambled outputs, element `s·G + g` |
