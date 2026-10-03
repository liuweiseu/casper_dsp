# xeng

## Description

Port of casper_library's `xeng` (`casper_library_correlator.slx`, Block SID 410; `xeng_init.m`), the windowed CASPER X-engine with descramble. The library stores an empty shell, because `n_ants = 0` makes the init script clear the block, so the structure is taken from `xeng_init.m`:

```
ant ─┬─ auto_tap (a_del = a_ndel = ant, acc_in = 0, valid_in = 0, sync_in)
     │     1..7 ─► baseline_tap1 ─► … ─► baseline_tapK      (K = N_ANTS/2, output p → input p)
     │     a_loop ◄── baseline_tapK.a_del_out
window_valid ─ window_delay(XENG_DELAY) ──────────────► descramble.win_valid
baseline_tapK acc_out[8W−1:0] / valid_out / sync_out ─► descramble acc / valid / sync
descramble ─► acc, valid, sync_out
mcnt_in ─ sample_and_hold(sync_in) ─ sample_and_hold(tapK.sync_out)
        ─ sample_and_hold(descramble.sync_out) ─ delay(1) ─ mcnt_out          (period N_ANTS·ACC_LEN)
descramble = xeng_descramble_4ant for 4 antennas, xeng_descramble otherwise
XENG_DELAY = ADD_LATENCY + MULT_LATENCY + ACC_LEN + floor(N_ANTS/2+1) + 1
```

**Antenna input.** `ant` is time-multiplexed: frame f, antenna j and sample s arrive at cycle `sync + 1 + (f·N_ANTS + j)·ACC_LEN + s`. Each word is `{X.re, X.im, Y.re, Y.im}`.

**Antenna loop.** With the loop closed, `auto_tap.a_end_out` lags `ant` by exactly `N_ANTS·ACC_LEN` cycles; the testbench checks this inside the RTL. Tap k integrates antenna j × conj(antenna (j+k) mod N). The dumps of all taps for one antenna line reach the end of the relay chain as a burst of K+1 consecutive words, which is the order `xeng_descramble` expects.

**Readout.** After the descramble, each readout is the `E = N(N+1)/2` dual-polarisation visibilities of one complete data frame, one element per baseline (x ≤ y). Each element is `{XX, YY, XY, YX}` = `Σ x·conj(y)` over `ACC_LEN` samples (XY = x.X·conj(y.Y)), read out as `DEMUX_FACTOR` words. The element order for 8 antennas is:

```
(0,0) (0,1) (1,1) (0,2) (1,2) (2,2) (0,3) (1,3) (2,3) (3,3) (0,4) (1,4) (2,4) (3,4) (4,4)
(1,5) (2,5) (3,5) (4,5) (5,5) (2,6) (3,6) (4,6) (5,6) (6,6) (3,7) (4,7) (5,7) (6,7) (7,7)
(0,5) (0,6) (0,7) (1,6) (1,7) (2,7)
```

The last group is the conjugated region. It comes from the next output window, where the X-engine emits the frame's wrapped-around baselines.

The test-data generator checks this end to end for 4, 6, 8 and 10 antennas. One configuration family breaks frame consistency, in the library as well: 8 antennas with `ACC_LEN·N/(NV·D)` = 1.6. There the read pace 1.6 rounds down to `DEL = 0`, so the last conjugated element is read before the next window rewrites it and comes from the previous frame. A survey of N ∈ {4…12}, ACC_LEN ∈ {8…128}, D ∈ {1, 2, 4, 8} found no other case.

**Tap output to descramble.** The taps produce 8 `N_BITS_OUT`-bit parts (`2·N_BITS + 1 + ceil(log2 ACC_LEN)`). The descramble slices `W`-bit fields (`2·N_BITS + floor(log2 ACC_LEN) + 1`) at offsets k·W from the LSB of whatever it receives, so feeding it the low 8W bits is equivalent. When `ACC_LEN` is a power of 2, W = N_BITS_OUT and nothing is lost. Otherwise W is one bit narrower and the fields are misaligned, each mixing bits of neighbouring parts, exactly as in the library; the module issues a `$warning` in that case.

**Power-on.** If `window_valid` is high from power-on, `window_delay` still sees a rising edge at cycle 0 and its output rises at `XENG_DELAY` (see `window_delay`). The descramble's power-on read pass (`D·E` words of zeros) also appears on `acc`/`valid`.

Built from `auto_tap`, `baseline_tap` ×K, `window_delay`, `xeng_descramble` / `xeng_descramble_4ant`, `sample_and_hold` ×3 and `delay`.

## Parameters

Defaults are the stored mask values, except `N_ANTS`. The stored `n_ants = 0` is the empty-shell value, so `N_ANTS` uses the `xeng_init.m` default of 8.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_ANTS` | 8 | Number of antennas. Must be even and ≥ 4: the mask silently raises values below 4 to 4, 5 is a mask error, and the descramble needs an even count. Other values give a `$fatal` |
| `N_BITS` | 4 | Bits per real/imaginary sample |
| `ACC_LEN` | 128 | Integration length. Must be > floor(N_ANTS/2 + 1) (mask error otherwise, here `$fatal`) |
| `DEMUX_FACTOR` | 4 | Output words per element: 1, 2, 4 or 8 |
| `ADD_LATENCY` / `MULT_LATENCY` | 1 / 1 | cmac latencies |
| `BRAM_LATENCY` | 2 | delay_bram legality checks in the taps |
| `USE_DED_MULT` | 1 | Declared only. The mask passes it, but `xeng_init.m` reads `mult_type`, which falls back to its default of 1 (embedded multipliers) for every tap |
| `USE_BRAM_DELAY` | 1 | 1 = delay_bram, 0 = delay_slr in the taps. Affects resources only |
| `MCNT_BITS` | 32 | Width of `mcnt_in`/`mcnt_out`. Not a mask parameter; Simulink inherits it |
| `PLATFORM` | "GENERIC" | RAM vendor |
| `N_BITS_OUT` / `W` / `OW` | derived | Do not override |

## Ports

Port numbers follow the order in which `xeng_init.m` creates the ports. The older xeng in `casper_library/Tests/xeng_test.mdl` confirms the original three of each (sync_in, ant, window_valid; sync_out, acc, valid); the mcnt ports were added later as port 4.

| # | Port | Direction | Width | Description |
|---|------|-----------|-------|-------------|
| | `clk` | input | 1 | Clock |
| 1 | `sync_in` | input | 1 | Sync, one cycle before a frame |
| 2 | `ant` | input | `4*N_BITS` | Antenna stream |
| 3 | `window_valid` | input | 1 | Integration window |
| 4 | `mcnt_in` | input | `MCNT_BITS` | Master count |
| 1 | `sync_out` | output | 1 | Readout start after a sync |
| 2 | `acc` | output | `OW` | Visibility words |
| 3 | `valid` | output | 1 | Word valid |
| 4 | `mcnt_out` | output | `MCNT_BITS` | mcnt of the readout |
