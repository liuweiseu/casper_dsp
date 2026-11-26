# auto_tap

## Description

Port of casper_library's `auto_tap` (`casper_library_correlator.slx`, Block SID 1; `auto_tap_init.m`). It is the first tap of the X-engine: it computes each antenna's autocorrelations and closes the antenna loop.

```
a_del, a_ndel ─┬─ a_del_out, a_ndel_out            (0 cycles)
               └─ dual_pol_cmac(a1 = a_del, a2 = a_ndel, acc_in, sync = sync_in, valid_in) ─ acc_out, valid_out
sync_in ─┬─ rst_out                                (0 cycles)
         └─ sync_delay(S) ─ sync_out
a_loop  ─ delay(D) ─ a_end_out                     (delay_bram, or delay_slr)
```

The two delays are:

```
D = (ACC_LEN−1)·ceil(N_ANTS/2) + N_ANTS mod 2
S = ADD_LATENCY + MULT_LATENCY + ACC_LEN + floor(N_ANTS/2 + 1) + 1
```

With the stored mask values (N_ANTS 4, ACC_LEN 64, ADD 1, MULT 2) these give D = 126 and S = 71, the `DelayLen` values stored in the `.slx`.

In `xeng`, `a_loop` is the last `baseline_tap`'s `a_del_out`. Each of the `floor(N_ANTS/2)` baseline taps delays `a_del` by `ACC_LEN+1`, so `a_end_out` lags the antenna stream by `floor(N_ANTS/2)·(ACC_LEN+1) + D = N_ANTS·ACC_LEN` cycles, exactly one frame. The test-data generator checks this for several `N_ANTS`/`ACC_LEN`, and also checks that the chained taps pair the same time samples of two antennas, covering every baseline.

Built from `dual_pol_cmac`, `delay_bram` / `delay_srl` and `sync_delay`.

## Parameters

Defaults are the stored mask values. `auto_tap_init.m` has its own defaults (`acc_len` 32, `mult_type` 1), which are not used.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_ANTS` | 4 | Number of antennas |
| `N_SIMULTAN` | 2 | Disabled on the mask and not read by the init script. Declared only |
| `N_BITS` | 4 | Width of each real/imaginary part |
| `ACC_LEN` | 64 | Integration length (≥ 2) |
| `ADD_LATENCY` / `MULT_LATENCY` | 1 / 2 | cmac latencies |
| `BRAM_LATENCY` | 2 | Only used for the delay_bram legality check: `D > BRAM_LATENCY + 1`, otherwise `$fatal` |
| `MULT_TYPE` | 0 | 0 = behavioral HDL, 1 = embedded multiplier core, 2 = standard core. Affects resources only |
| `USE_BRAM_DELAY` | 1 | 1 = delay_bram, 0 = delay_slr. Affects resources only |
| `PLATFORM` | "GENERIC" | Passed to delay_bram |
| `N_BITS_OUT` | derived | `2·N_BITS + 1 + ceil(log2(ACC_LEN))` |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a_del` / `a_ndel` | input | `4*N_BITS` | Antenna stream `{X.re, X.im, Y.re, Y.im}` |
| `a_loop` | input | `4*N_BITS` | Loop-back from the last baseline tap |
| `acc_in` | input | `8*N_BITS_OUT` | Relay input |
| `valid_in` | input | 1 | Relay valid |
| `sync_in` | input | 1 | Sync |
| `a_del_out` / `a_ndel_out` | output | `4*N_BITS` | `a_del` / `a_ndel` |
| `a_end_out` | output | `4*N_BITS` | `a_loop` delayed by `D` |
| `acc_out` | output | `8*N_BITS_OUT` | `{XX, YY, XY, YX}` dumps / relay |
| `valid_out` | output | 1 | Dump / relay valid |
| `rst_out` | output | 1 | `sync_in`, drives the next tap's counter |
| `sync_out` | output | 1 | `sync_in` delayed by `S` |
