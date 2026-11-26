# cmac

## Description

Port of casper_library's `cmac` (`casper_library_correlator.slx`, Block SID 810). The block has no `_init.m`: the mask initialization is stored in `system_root.xml` and the diagram in `system_810.xml`. It computes `a·conj(b)` at full precision, accumulates it over `ACC_LEN` samples, and inserts each finished integration into a relay chain (`acc_in` → `acc_out`).

```
a, b   ─ cmult (conjugated, full precision, latency MULT+ADD) ─ re / im ─ cmac_acc ×2 ─ acc_out
acc_in ─ re / im ──────────────────────────────────────────────────────┘
sync   ─ pipeline(MULT+ADD-1) ─ counter (0 .. ACC_LEN-1, sync reset) ─ (cnt == 0, latency 1) ─ rst
valid_in ─ imaginary cmac_acc ─ valid_out   (the real cmac_acc gets valid_in = 0)
```

Derived values (mask initialization):

- `BIT_GROWTH = ceil(log2(ACC_LEN))`
- `N_BITS_OUT = N_BITS_A + N_BITS_B + 1 + BIT_GROWTH`
- `BIN_PT_OUT = BIN_PT_A + BIN_PT_B`

The products are full precision and `N_BITS_OUT` covers the worst-case growth, so every sum is exact.

### Timing

Assume `sync` arrives at cycle S and the first sample of the frame at S+1.

- `rst` first pulses at S+MULT+ADD+1, in step with the first product, and then every `ACC_LEN` cycles. The counter runs freely, so `rst` keeps repeating even without `sync`.
- Each integration appears on `acc_out` with `valid_out = 1` two cycles after its `rst`.
- The first complete integration therefore appears at S+MULT+ADD+3+ACC_LEN.
- The dump at S+MULT+ADD+3 also has `valid_out = 1`, but holds the partial sum from before `sync`.
- `acc_in` → `acc_out` and `valid_in` → `valid_out` each take 2 cycles.

### Notes from the library

- **The conjugated input is `b`**, matching cmult's wiring.
- **The stored `cmult*` is an older copy without `pipeline_cmult_en`.** That option therefore defaults to off and adds no extra latency, even though `multiplier_implementation` defaults to the embedded core.
- **Constraint A:** `c_to_ri2` reinterprets `acc_in` with binary point `n_bits_out − bit_growth − 3 = N_BITS_A + N_BITS_B − 2`, hardcoded. The accumulator, however, uses `BIN_PT_A + BIN_PT_B`. When the two differ, Simulink's full-precision relay Mux aligns the binary points, so `acc_out` grows wider than `2·N_BITS_OUT` and `acc_in` is shifted. Fixed-width ports cannot express that, so the module raises a `$fatal`. The defaults satisfy the constraint, and so does `dual_pol_cmac`, which always uses `n_bits − 1`.

Built from `cmult`, `c_to_ri` ×2, `pipeline`, `counter`, `constant`, `relational`, `cmac_acc` ×2 and `ri_to_c`.

## Parameters

Names and defaults are the stored mask values.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ACC_LEN` | 128 | Integration length. Must be ≥ 2; any value works, not only powers of 2 |
| `N_BITS_A` / `BIN_PT_A` | 4 / 3 | Format of each part of `a` |
| `N_BITS_B` / `BIN_PT_B` | 4 / 3 | Format of each part of `b`. The binary points only enter constraint A |
| `MULT_LATENCY` / `ADD_LATENCY` | 1 / 1 | cmult latencies. Their sum must be ≥ 1 |
| `MULTIPLIER_IMPLEMENTATION` | 2 | 0 = behavioral HDL, 1 = standard core, 2 = embedded multiplier core. Affects resources only |
| `QUANTIZATION` / `OVERFLOW` | 0 / 0 | Greyed out on the mask and unused. Declared only |
| `IN_LATENCY` / `CONV_LATENCY` | 0 / 0 | Greyed out; the mask always passes 0 to cmult. Declared only (a nonzero value gives a `$warning`) |
| `BIT_GROWTH` / `N_BITS_OUT` / `BIN_PT_OUT` | derived | See above. Do not override |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `a` | input | `2*N_BITS_A` | `{re, im}`, real part in the MSBs |
| `b` | input | `2*N_BITS_B` | `{re, im}`, the conjugated input |
| `acc_in` | input | `2*N_BITS_OUT` | Relay input `{re, im}` |
| `sync` | input | 1 | Realigns the integration, one cycle before the first sample |
| `valid_in` | input | 1 | Relay valid |
| `acc_out` | output | `2*N_BITS_OUT` | `{re, im}`: an integration two cycles after each `rst`, otherwise `acc_in` delayed 2 |
| `valid_out` | output | 1 | 1 on dumps, otherwise `valid_in` delayed 2 |
