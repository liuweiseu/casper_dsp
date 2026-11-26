# dual_pol_cmac

## Description

Port of casper_library's `dual_pol_cmac` (`casper_library_correlator.slx`, Block SID 814; the mask initialization is in `system_root.xml`, the diagram in `system_814.xml`). It runs four `cmac`s, one for each polarisation product of two dual-polarisation complex inputs.

| cmac | a | b (conjugated) | acc_in / acc_out slice |
|------|---|----------------|------------------------|
| `cmac` (XX) | a1 p0 | a2 p0 | `[8m-1 -: 2m]` |
| `cmac1` (YY) | a1 p1 | a2 p1 | `[6m-1 -: 2m]` |
| `cmac2` (XY) | a1 p0 | a2 p1 | `[4m-1 -: 2m]` |
| `cmac3` (YX) | a1 p1 | a2 p0 | `[2m-1 -: 2m]` |

- `a1`/`a2` are `{p0, p1}` with p0 in the MSBs. Each polarisation is a `{re, im}` word.
- `m = N_BITS_OUT = 2·N_BITS_IN + 1 + ceil(log2(ACC_LEN))`.
- `acc_out = {XX, YY, XY, YX}`, with XX in the MSBs.
- All four cmacs share `sync`, and each has its own sync-to-rst chain, as in the diagram.
- Only `cmac3` sees `valid_in` (the other three get a constant 0), and its `valid_out` is the block's `valid_out`.

The mask always gives every cmac `bin_pt = N_BITS_IN − 1`, so `BIN_PT_IN` is declared only and cmac's constraint A always holds. Timing is the same as `cmac`.

## Parameters

Names and defaults are the stored mask values.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ACC_LEN` | 128 | Integration length (≥ 2) |
| `N_BITS_IN` | 4 | Width of each real / imaginary part |
| `BIN_PT_IN` | 3 | Declared only. The mask passes `N_BITS_IN − 1` to the cmacs |
| `MULT_LATENCY` / `ADD_LATENCY` | 1 / 1 | cmac latencies |
| `MULTIPLIER_IMPLEMENTATION` | 2 | Embedded multiplier core. Affects resources only |
| `N_BITS_OUT` | derived | See above. Do not override |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a1` / `a2` | input | `4*N_BITS_IN` | `{p0.re, p0.im, p1.re, p1.im}` |
| `acc_in` | input | `8*N_BITS_OUT` | Relay input `{XX, YY, XY, YX}` |
| `sync` | input | 1 | Realigns the integrations |
| `valid_in` | input | 1 | Relay valid |
| `acc_out` | output | `8*N_BITS_OUT` | `{XX, YY, XY, YX}` |
| `valid_out` | output | 1 | Dump / relay valid |
