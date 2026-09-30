# twiddle_pass_through

## Description

A twiddle stage that passes everything through unchanged. It corresponds to
casper_library's `twiddle_pass_through`, which `butterfly_direct` selects for
`Coeffs = [0]` (w = 1) in the first biplex stage. Every leg is a plain wire:
`ao = ai`, `bwo = bi`, `sync_out = sync_in`. There is no latency and no delay
matching.

## Parameters

| Parameter         | Default | Description |
|-------------------|---------|-------------|
| `N_INPUTS`        | 1       | Number of complex lanes |
| `INPUT_BIT_WIDTH` | 18      | Lane word width. Added for the HDL port widths; the Simulink block does not need it. |
| `ASYNC`           | 0       | Declared for traceability; must be 0 |

## Ports

These are the same ports as [`twiddle_general`](twiddle_general.md), except
that `bwo_re`/`bwo_im` are `INPUT_BIT_WIDTH` bits wide rather than
`INPUT_BIT_WIDTH+1`, as in casper_library.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock (unused) |
| `ai_re`, `ai_im`, `bi_re`, `bi_im` | input | `INPUT_BIT_WIDTH` × `N_INPUTS` | Lane inputs |
| `sync_in` | input | 1 | Sync |
| `ao_re`, `ao_im`, `bwo_re`, `bwo_im` | output | `INPUT_BIT_WIDTH` × `N_INPUTS` | `ai` and `bi` passed through |
| `sync_out` | output | 1 | `sync_in` passed through |
