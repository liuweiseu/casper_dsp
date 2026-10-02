# bi_real_unscr_4x

## Description

Unscrambles a biplex FFT of four real signals. It is the back end of
casper's `fft_biplex_real_4x`. It corresponds to casper_library's
`bi_real_unscr_4x` (fixed point, sync mode, `bi_real_unscr_4x_init.m`).

[`biplex_core`](../biplex_core.md) gets `z1 = pol1 + j·pol2` and
`z2 = pol3 + j·pol4`. Per frame of `N = 2^FFT_SIZE` cycles it outputs `z1` in
the first half-frame and `z2` in the second; `even` carries bins
`bit_rev(k)` and `odd` bins `bit_rev(k) + N/2`. This block turns that into
the full `N`-bin spectra of the four real signals, one bin per cycle, all
four at once on `pol1_out … pol4_out`. With `HALF = N/2`:

```
even ─► reorder_even (map bit_rev(k))        ─► Z[k]
odd  ─► reorder_odd  (map bit_rev(HALF−1−k)) ─► delay 1 ─► Z[N−k]
count = FFT_SIZE-bit counter, cleared by reorder_even's sync_out
r0 = (count == HALF), r1 = (count == 0)                 (Relational a=b)
mux0 = r0 ? odd : even      mux1 = r1 ? even : odd       (Mux, latency 1)
mux2 = r1 ? odd : even      mux3 = r0 ? even : odd
hilbert0(mux0, mux1) ─► delay HALF ─┬─► mirror_spectrum din0 / din1
hilbert1(mux2, mux3) ───────────────┼─► mirror_spectrum din2 / din3
                                    └─► reorder_out (map HALF−1−k, 4 streams)
                                          ─► delay 1 ─► mirror_spectrum reo_in0 … 3
sync: reorder_even sync_out ─► delay ADD+CONV+1 ─► delay HALF ─► mirror_spectrum
```

- Each [`hilbert`](hilbert.md) splits a `z` into its two real-signal spectra.
  `hilbert0` works on `z1` (first half-frame) and is delayed half a frame so
  that it lines up with `hilbert1` on `z2`.
- `r0` and `r1` handle bins 0 and `N/2`. For those, `Z[N−k]` would come from
  the other half-frame.
- [`mirror_spectrum`](mirror_spectrum.md) fills in bins above `N/2` as
  conjugates of the reversed lower bins.

The test data generator feeds the [`biplex_core`](../biplex_core.md) reference
model's output for four random real signals through the reference model of
this block. It checks with numpy that every output frame is the FFT of the
four input signals, to within about 2.5 LSB.

### casper parameters derived inside

| Quantity | Value (as `bi_real_unscr_4x_init.m`) |
|----------|--------------------------------------|
| reorder `map_latency` | `3` if `BRAM_MAP`, else `1` |
| reorder `fanout_latency` | `max(0, FFT_SIZE + ceil(log2(N_BITS·N_INPUTS·2)) − 15)` |
| half-frame data delays | [`delay_bram`](../../Delays/delay_bram.md) if `BRAM_DELAYS` or `HALF > 52`, else [`delay_srl`](../../Delays/delay_srl.md) |
| half-frame sync delay | [`sync_delay`](../../Delays/sync_delay.md) if `HALF > 52`, else `delay_srl` |
| mirror_spectrum `bram_latency` / `negate_latency` | `BRAM_LATENCY + map_latency + 2 + fanout_latency` / `0` |

### Maps

The three [`reorder`](../../Reorder/reorder.md)s read their maps from
`MAP_DIR` + `map_even.mem`, `map_odd.mem` and `map_out.mem`. Generate them
with:

```bash
for m in even odd out; do
  python3 rtl/Reorder/scripts/gen_reorder_map.py --bi-real $m --fft-size F -o DIR/map_$m.mem
done
```

The reorders need a sync every `N` cycles (one per frame), as `biplex_core`
provides.

### FFT_SIZE = 2 (casper behaviour)

For `FFT_SIZE = 2` the even map is the identity, so the even reorder has
order 1. `reorder_init.m` makes an order-1 reorder one cycle slower than an
order-2 one (the odd map), so even and odd are misaligned by a cycle and
casper's block does not compute an FFT. This module reproduces casper
bit-exactly, including this case. Use `FFT_SIZE ≥ 3`.

### Not implemented

`ASYNC` (casper's `en` / `dvalid`) must be 0. `DSP48_ADDERS` is ignored.
Floating point is not implemented.

Inside the reorders, the complex lanes are packed `{im, re}` per lane, lane 0
lowest.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | Complex lanes |
| `FFT_SIZE` | 3 | log2 of the FFT length (≥ 2, see above) |
| `N_BITS` | 18 | Width of the real and imaginary parts (signed) |
| `BIN_PT` | 17 | Binary point |
| `ADD_LATENCY` | 1 | hilbert adder latency |
| `CONV_LATENCY` | 1 | hilbert convert latency |
| `BRAM_LATENCY` | 2 | Reorder RAM latency |
| `BRAM_MAP` | 0 | casper `bram_map`: map latency 3 instead of 1 |
| `BRAM_DELAYS` | 0 | casper `bram_delays`: RAM half-frame delays |
| `MAP_DIR` | `""` | Directory prefix of the three map files |
| `PLATFORM` | `"GENERIC"` | Memory primitives: `GENERIC`, `XILINX`, `ALTERA` |
| `DSP48_ADDERS` | 0 | Ignored |
| `ASYNC` | 0 | Must be 0 |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | biplex_core `sync_out` |
| `even_re`, `even_im` | input | `N_BITS` × `N_INPUTS` | biplex_core `out1` |
| `odd_re`, `odd_im` | input | `N_BITS` × `N_INPUTS` | biplex_core `out2` |
| `sync_out` | output | 1 | Sync, one cycle before bin 0 |
| `pol<i>_out_re`, `pol<i>_out_im` (i = 1 … 4) | output | `N_BITS` × `N_INPUTS` | Spectrum of real signal i, bins 0 … N−1 |
