# tap_real

## Description

A middle tap of a real PFB FIR; pfb_fir_real uses `TotalTaps − 2` of them.
It corresponds to casper_library's `tap_real`, and is built from its internal
diagram in `casper_library_pfbs.slx`:

```
din ─┬─► delay_bram (DELAY) ───────────────────────────────────► dout
     └─► Fix_DATA_WIDTH_(DATA_WIDTH−1) ──────────────────┐
coeff ─┬─► [COEFF_WIDTH−1 : 0] ─► Fix_COEFF_WIDTH_COEFF_FRAC_WIDTH ─┴► Mult (Full, MULT_LATENCY) ─► taps_out
       └─► [MSB : COEFF_WIDTH] ─────────────────────────────► coeff_out   (no delay)
sync ─► sync_delay (DELAY) ────────────────────────────────────► sync_out
```

- The tap multiplies **its own, undelayed** input sample by the **lowest**
  `COEFF_WIDTH` bits of the coefficient bus.
- It forwards the rest of the bus unchanged, without delay.
- Only the data ([`delay_bram`](../Delays/delay_bram.md)) and the sync
  ([`sync_delay`](../Delays/sync_delay.md)) advance by `DELAY` per hop.
  pfb_fir_real sets `DELAY = 2^(PFBSize−n_inputs)·n_pol_blocks`.

So, within one chain, tap `t` multiplies the sample that is `(t−1)·DELAY`
cycles older than the first tap's, using the same coefficient bus.
[`pfb_coeff_gen`](pfb_coeff_gen.md) puts ROM 1 in the MSBs of that bus, so
tap `t` uses ROM `TotalTaps+1−t`. The chain therefore computes the
windowed-presum PFB

```
y_c(f) = Σ_{j ≡ c (mod 2^PFBSize)} h[j] · x[(f − TotalTaps + 1)·2^PFBSize + j]
```

The test data generator checks this on integer data: a whole
first_tap_real → tap_real → last_tap_real chain matches the definition
exactly in 5 configurations (PFBSize 4–6, 2–8 taps, n_inputs 0–2,
n_pol_blocks 1–3). Per-hop delays of `DELAY−1`, `DELAY+1` and 0 all give
wrong outputs.

`taps_out` is the full-precision product: `DATA_WIDTH+COEFF_WIDTH` bits,
binary point `DATA_WIDTH−1+COEFF_FRAC_WIDTH`, signed.

`N_COEFFS` is the number of coefficients on the incoming bus. casper infers
the bus width; here it must be given, and `coeff_out` carries
`N_COEFFS−1` coefficients. `USE_HDL` and `USE_EMBEDDED` (the multiplier
implementation) are declared for traceability and ignored.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MULT_LATENCY` | 2 | Multiplier latency |
| `COEFF_WIDTH` | 12 | Coefficient width (casper `coeff_width`) |
| `COEFF_FRAC_WIDTH` | 11 | Coefficient binary point (pfb_fir_real: `CoeffBitWidth−1`) |
| `DELAY` | 4 | Data / sync delay per hop |
| `DATA_WIDTH` | 8 | Data width (binary point `DATA_WIDTH−1`) |
| `BRAM_LATENCY` | 1 | casper delay_bram latency (the total delay is `DELAY` either way) |
| `N_COEFFS` | 3 | Coefficients on the incoming bus (≥ 2) |
| `PLATFORM` | `"GENERIC"` | Memory primitives of the delay |
| `USE_HDL`, `USE_EMBEDDED` | 1, 0 | Ignored |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | `DATA_WIDTH` | Data |
| `sync` | input | 1 | Sync |
| `coeff` | input | `N_COEFFS·COEFF_WIDTH` | Coefficient bus; own coefficient in the LSBs |
| `dout` | output | `DATA_WIDTH` | `din` delayed `DELAY` |
| `sync_out` | output | 1 | `sync` through `sync_delay(DELAY)` |
| `coeff_out` | output | `(N_COEFFS−1)·COEFF_WIDTH` | Rest of the bus (no delay) |
| `taps_out` | output | `DATA_WIDTH+COEFF_WIDTH` | Product, `MULT_LATENCY` cycles later |
