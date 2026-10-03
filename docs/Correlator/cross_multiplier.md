# cross_multiplier

## Description

Port of casper_library's `cross_multiplier` (`casper_library_correlator.slx`, Block SID 71; `cross_multiplier_init.m`, whose function is misnamed `refactor_storage_init`). It multiplies every pair of input streams x ≤ y, conjugating the second one, separately for each of the `AGGREGATION` complex samples packed into a stream word:

```
din[x], din[y] ─ bus_expand / c_to_ri (per sub-stream s) ─ 4 × Delay(1) (operand fan-out registers)
  ─ cmult_4bit_hdl*: real = ac + bd, imag = bc − ad  = x · conj(y), full precision, latency MULT + ADD
  ─ convert_of (re, im) to Fix(BIT_WIDTH_OUT, BIN_PT_OUT), QUANTIZATION / OVERFLOW, latency CONV
  ─ ri_to_c / bus_create ─ dout[k]
sync_out = Delay(sync_in, 1 + MULT_LATENCY + ADD_LATENCY + CONV_LATENCY)
```

- **Multiplier:** `cmult_4bit_hdl*` is implemented by `cmult` with `CONJUGATED = 1` at full precision (`2W+1` bits, binary point `2P`), which is bit- and cycle-equivalent.
- **Overflow flag:** the `convert_of` overflow output is left unconnected, as in the library.
- **Rounding:** `convert` implements Xilinx Round (±Inf) as half away from zero and Round (even) as half to even, including on negative halves.
- **Output order:** output k enumerates x = 0..STREAMS−1, y = x..STREAMS−1. In Simulink, output `din{x}_x_din{y}*` is port `Σ_{j<x}(STREAMS−j) + (y−x) + 2`, i.e. port k+2 (port 1 is `sync_out`).
- **Packing:** sub-stream s of a word is at `[(AGG−s)·2W−1 −: 2W]`, so sub-stream 0 is in the MSBs (`bus_expand` output 1 and `bus_create` input 1 are the MSB slice). Each value is `{re, im}`. The ports are packed arrays: `din[x]` is stream x, `dout[k]` output k.

Built from `c_to_ri`, `delay`, `cmult`, `convert_of`, `ri_to_c` and `pipeline`.

## Parameters

Defaults are the stored mask values, except `STREAMS`. The library stores `streams = 0`, which builds no multipliers, and the init script has no defaults. `STREAMS` therefore defaults to 2, the smallest value with a cross product.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `STREAMS` | 2 | Number of input streams (≥ 1) |
| `AGGREGATION` | 2 | Complex samples per stream word |
| `BIT_WIDTH_IN` / `BIN_PT_IN` | 4 / 3 | Input part format (W, P) |
| `BIT_WIDTH_OUT` / `BIN_PT_OUT` | 9 / 6 | Output part format |
| `MULT_LATENCY` / `ADD_LATENCY` | 2 / 1 | Multiplier latencies |
| `OVERFLOW` | 0 | 0 = Wrap, 1 = Saturate, 2 = Error (treated as wrap in HDL) |
| `QUANTIZATION` | 0 | 0 = Truncate, 1 = Round (unbiased: ±Inf), 2 = Round (unbiased: even) |
| `CONV_LATENCY` | 0 | Output convert latency |
| `NOUT` | derived | `STREAMS(STREAMS+1)/2` |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync_in` | input | 1 | Sync |
| `din` | input | `[STREAMS][AGG·2·BIT_WIDTH_IN]` | Input streams |
| `sync_out` | output | 1 | Sync delayed by the latency |
| `dout` | output | `[NOUT][AGG·2·BIT_WIDTH_OUT]` | Products, x ≤ y order |
