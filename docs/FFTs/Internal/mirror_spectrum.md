# mirror_spectrum

## Description

Completes the upper half of four real-signal spectra. The spectrum of a
real signal is conjugate-symmetric, `X[N−k] = X*[k]`, so only bins
`0 … N/2` need to be computed. It corresponds to casper_library's
`mirror_spectrum` (fixed point, sync mode, `mirror_spectrum_init.m`).

Each of the four channels `i` has two inputs:

- `din<i>`: bins `0, 1, …` in order.
- `reo_in<i>`: the same bins in reverse order, from a reorder.

Per frame of `N = 2^FFT_SIZE` samples, counted from the cycle after `sync`:

| Frame count | `dout<i>` |
|-------------|-----------|
| `0 … 2^(FFT_SIZE−1)` | `din<i>` (delayed) |
| `2^(FFT_SIZE−1)+1 … N−1` | `conj(reo_in<i>)` |

casper compares the count with a Relational `a>b` against `2^(FFT_SIZE−1)`
and uses the result as the mux select (`d0 = din`, `d1 = conj`). With
`REP = ceil(log2(N_INPUTS))` (the latency of casper's `bus_replicate` of the
select):

```
din<i>    ─► delay 1+BRAM_LATENCY+NEGATE_LATENCY ─► mux d0 ┐
reo_in<i> ─► complex_conj (latency CC, Wrap)     ─► mux d1 ├─ mux (latency 1) ─► dout<i>
sync ─► delay 1+BRAM_LATENCY+NEGATE_LATENCY−REP ─► counter rst ─► a>b ─► delay REP ─► sel
                                                └─► delay 1+REP ─► sync_out
```

- The counter is `FFT_SIZE` bits, counts up and is cleared by the delayed
  sync.
- `CC = 3` for `NEGATE_MODE = 1` (casper `negate_mode = 'dsp48e'`), else
  `NEGATE_LATENCY`.
- `sync_out` comes `2 + BRAM_LATENCY + NEGATE_LATENCY` cycles after `sync`.
  The first output sample (count 0) comes the cycle after `sync_out`.
- `BRAM_LATENCY` describes the reorder in front of `reo_in<i>`.
  [`bi_real_unscr_4x`](bi_real_unscr_4x.md) passes `bram_latency +
  map_latency + 2 + fanout_latency` and negate latency 0.

`ASYNC` (casper's `en` / `dvalid` ports) is declared for traceability and must
be 0. Floating point is not implemented.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_INPUTS` | 1 | Complex lanes per channel |
| `FFT_SIZE` | 8 | log2 of the frame length |
| `INPUT_BIT_WIDTH` | 18 | Width of the real and imaginary parts (signed) |
| `BIN_PT_IN` | 17 | Binary point |
| `BRAM_LATENCY` | 2 | Latency of the reorder feeding `reo_in<i>` (see above) |
| `NEGATE_LATENCY` | 1 | complex_conj latency (`NEGATE_MODE = 0`) |
| `NEGATE_MODE` | 0 | `0` = logic, `1` = dsp48e (complex_conj latency 3) |
| `ASYNC` | 0 | Must be 0 |

`1 + BRAM_LATENCY + NEGATE_LATENCY ≥ REP` is required.

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` | input | 1 | Frame sync |
| `din<i>_re`, `din<i>_im` (i = 0 … 3) | input | `INPUT_BIT_WIDTH` × `N_INPUTS` | Bins in order |
| `reo_in<i>_re`, `reo_in<i>_im` (i = 0 … 3) | input | `INPUT_BIT_WIDTH` × `N_INPUTS` | Bins in reverse order |
| `sync_out` | output | 1 | Sync, one cycle before the first output sample |
| `dout<i>_re`, `dout<i>_im` (i = 0 … 3) | output | `INPUT_BIT_WIDTH` × `N_INPUTS` | Full spectra |
