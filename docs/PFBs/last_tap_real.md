# last_tap_real

## Description

The last tap of a real PFB FIR. It corresponds to casper_library's
`last_tap_real`, built from its internal diagram in
`casper_library_pfbs.slx`; `last_tap_real_init.m` only sets the multiplier
implementation.

```
din   ─► Fix_BIT_WIDTH_IN_(BIT_WIDTH_IN−1) ──────────┐
coeff ─► Fix_COEFF_BIT_WIDTH_(COEFF_BIT_WIDTH−1) ─────┴► Mult (Full, MULT_LATENCY) ─► tap_out
sync  ─► Delay (MULT_LATENCY) ─────────────────────────────────────► sync_out
```

Nothing is forwarded. `coeff` is the last coefficient left on the bus,
which is ROM 1 of [`pfb_coeff_gen`](pfb_coeff_gen.md). In pfb_fir_real,
`tap_out` is the [`adder_tree`](../Misc/adder_tree.md)'s last data input and
`sync_out` its `sync`. Every tap's multiplier has the same `MULT_LATENCY`,
so these line up with all the products.

`tap_out` has `BIT_WIDTH_IN+COEFF_BIT_WIDTH` bits, binary point
`BIT_WIDTH_IN+COEFF_BIT_WIDTH−2`, signed. `USE_HDL` and `USE_EMBEDDED` are
declared and ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BIT_WIDTH_IN` | 8 | Data width |
| `COEFF_BIT_WIDTH` | 8 | Coefficient width |
| `MULT_LATENCY` | 2 | Multiplier latency (also the sync delay) |
| `USE_HDL`, `USE_EMBEDDED` | 1, 0 | Ignored |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | `BIT_WIDTH_IN` | Data |
| `sync` | input | 1 | Sync |
| `coeff` | input | `COEFF_BIT_WIDTH` | Last coefficient |
| `tap_out` | output | `BIT_WIDTH_IN+COEFF_BIT_WIDTH` | Product, `MULT_LATENCY` cycles later |
| `sync_out` | output | 1 | `sync` delayed `MULT_LATENCY` |
