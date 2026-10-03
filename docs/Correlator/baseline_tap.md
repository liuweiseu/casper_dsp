# baseline_tap

## Description

Port of casper_library's `baseline_tap` (`casper_library_correlator.slx`, Block SID 2; `baseline_tap_init.m`). `xeng` uses one baseline tap per antenna separation, numbered `ANT_SEP` = 1 .. floor(N_ANTS/2). Each tap integrates the visibilities of antennas `j` and `(j + ANT_SEP) mod N_ANTS`.

```
a_del  ─ delay(ACC_LEN) ─ Delay(1) ─┬─ a_del_out
                                    └─ dual_pol_cmac.a1
a_ndel ─ Delay(1) ─ a_ndel_out          a_end ─ Delay(1) ─ a_end_out
rst    ─ Delay(1) ─┬─ rst_out
                   └─ dual_pol_cmac.sync
cnt = counter(0 .. N_ANTS·ACC_LEN−1, sync reset = rst)
sel = cnt < ANT_SEP·ACC_LEN                        (latency 0)
a2  = Mux(sel ? a_end : a_ndel, latency 1) ─ dual_pol_cmac.a2
sync_out = sync1                                   (straight through)
```

Frame alignment: an `rst` at cycle t0 resets the counter, so `cnt` is 0 at t0+1, and reaches the cmac as its sync at t0+1. The Mux output for cycle t0+1 arrives at t0+2, together with the cmac's first frame sample. Within each `N_ANTS·ACC_LEN` frame, the cmac's conjugated input is `a_end` for the first `ANT_SEP·ACC_LEN` samples (the antennas that wrap around) and `a_ndel` after that.

Because `a1` is `a_del` delayed `ACC_LEN+1` cycles and `a2` comes through the Mux one cycle late, `a1` lags `a2` by `ACC_LEN` samples. Each tap adds `ACC_LEN+1` cycles to `a_del` and 1 cycle to `a_ndel`, `a_end` and `rst`; `sync` passes through unchanged.

Built from `delay_bram` / `delay_srl`, `delay` ×4, `counter`, `constant`, `relational`, `multiplexer` and `dual_pol_cmac`.

## Parameters

Defaults are the stored mask values.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_ANTS` | 4 | Number of antennas |
| `ANT_SEP` | 1 | Antenna separation of this tap. `ANT_SEP·ACC_LEN` must fit the `ceil(log2 N_ANTS)+ceil(log2 ACC_LEN)`-bit counter constant, otherwise `$fatal` |
| `N_BITS` | 4 | Width of each real/imaginary part |
| `ACC_LEN` | 32 | Integration length (≥ 2) |
| `ADD_LATENCY` / `MULT_LATENCY` | 1 / 2 | cmac latencies |
| `BRAM_LATENCY` | 2 | Only used for the delay_bram legality check: `ACC_LEN > BRAM_LATENCY + 1`, otherwise `$fatal` |
| `MULT_TYPE` | 2 | 0 = behavioral HDL, 1 = embedded multiplier core, 2 = standard core. Affects resources only |
| `USE_BRAM_DELAY` | 1 | 1 = delay_bram, 0 = delay_slr. Affects resources only |
| `PLATFORM` | "GENERIC" | Passed to delay_bram |
| `N_BITS_OUT` | derived | `2·N_BITS + 1 + ceil(log2(ACC_LEN))` |

## Ports

The seven inputs and seven outputs connect one-to-one with the previous / next tap (`xeng_init.m`). The ports keep their library names, including `sync1`.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a_del` / `a_ndel` / `a_end` | input | `4*N_BITS` | Antenna streams from the previous tap |
| `acc_in` | input | `8*N_BITS_OUT` | Relay input |
| `valid_in` | input | 1 | Relay valid |
| `rst` | input | 1 | Frame start (the previous tap's `rst_out`) |
| `sync1` | input | 1 | Sync, passed through |
| `a_del_out` / `a_ndel_out` / `a_end_out` | output | `4*N_BITS` | Delayed by `ACC_LEN+1` / 1 / 1 |
| `acc_out` | output | `8*N_BITS_OUT` | `{XX, YY, XY, YX}` dumps / relay |
| `valid_out` | output | 1 | Dump / relay valid |
| `rst_out` | output | 1 | `rst` delayed by 1 |
| `sync_out` | output | 1 | `sync1` |
