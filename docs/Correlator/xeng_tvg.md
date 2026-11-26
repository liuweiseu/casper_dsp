# xeng_tvg

## Description

Port of casper_library's `xeng_tvg` (`casper_library_correlator.slx`, Block SID 717; there is no `_init.m`, and the mask parameters are used directly by the diagram). It is a test-vector source placed in front of an X-engine input:

| `tvg_sel` | `data_out` |
|-----------|------------|
| 0 | `data_in`, passed through |
| 1 | `{c, ~c, c, ~c}`: four 4-bit fields, where c is the antenna count |
| 2 | Constant `{0.1, −0.75, 0.5, −0.25}` as Fix_4_3 = `16'h1A4E` |
| 3 | `tv[k][15:0]` for antenna k = 0..7 (repeating) |

When `tvg_sel ≠ 0`, `sync` and `valid` are generated internally as well. The internal sync has period `2^SYNC_PERIOD` (first pulse at t = 2) and `valid` is 1.

```
use_tvg  = Delay(tvg_sel ≠ 0 (latency 1), 1)
sync_int = use_tvg ? edge2(Counter4[SYNC_PERIOD]) : sync
ant_en   = edge(Counter[X_INT_BITS])                       (Counter reset by sync_int)
Counter1 4-bit up, Counter2 3-bit up, Counter3 4-bit down from 15; rst = Delay(sync_int, 1), en = ant_en
data_out = Mux(Delay(tvg_sel, 1); Delay(data_in, 2), Delay({C1, C3, C1, C3}, 1), 16'h1A4E, Mux8(Counter2; tv[k][15:0]))
valid_out = Delay(use_tvg ? 1 : valid_in, 3)
sync_out  = Delay(sync_int, 3)
```

After a sync at t0, `data_out` at t0+4 is antenna 0: `0x0F0F` in mode 1, `tv0` in mode 3. A new antenna follows every `2^X_INT_BITS` cycles.

### Notes

- **Mode-2 constant.** Sysgen's Constant rounds 0.1 to Fix_4_3: the stored Constant7 block shows the quantized value `0.125` on its icon, i.e. `4'b0001`. So the constant is `16'h1A4E`, not `16'h0A4E`.
- **Counter3 resets to 15.** This uses the `counter` parameter `RST_VAL`. Counter2 and Counter3 always equal `Counter1[2:0]` and `~Counter1`.
- **Reset beats enable.** In Counter1..3, reset has priority over enable. When `sync_int` resets Counter while its MSB is 1, the resulting spurious `ant_en` arrives one cycle later, together with the delayed reset, and is swallowed.
- **`tv0..tv7` are software registers.** In the library they are xps software registers (32-bit, From Processor). Here they form an 8 × 32-bit input port, and only `[15:0]` is used.
- **Selects are not aligned at a mode switch.** Data is selected by `tvg_sel(t−2)`, while valid/sync use `tvg_sel(t−5)`, as in the diagram.

Built from `constant`, `relational`, `delay`, `counter` ×5, `edge_detect` ×2 and `multiplexer` ×4.

## Parameters

Names and defaults are the stored mask values.

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ANT_BITS` | 2 | Not referenced by the diagram; declared only. The antenna counters have fixed widths |
| `X_INT_BITS` | 5 | Each antenna lasts `2^X_INT_BITS` cycles |
| `SYNC_PERIOD` | 15 | Internal sync period `2^SYNC_PERIOD` |
| `DATA_WIDTH` | 16 | Width of `data_in`. Not a mask parameter (Simulink inherits it) |
| `OUT_WIDTH` | derived | `max(DATA_WIDTH, 16)` (full-precision Mux; `data_in` is taken as unsigned) |

## Ports

| # | Port | Direction | Width | Description |
|---|------|-----------|-------|-------------|
| | `clk` | input | 1 | Clock |
| 1 | `tvg_sel` | input | 2 | Mode |
| 2 | `sync` | input | 1 | External sync (mode 0) |
| 3 | `data_in` | input | `DATA_WIDTH` | X-engine input data |
| 4 | `valid_in` | input | 1 | External valid (mode 0) |
| | `tv` | input | `[8][32]` | Software registers tv0..tv7 |
| 1 | `sync_out` | output | 1 | Sync |
| 2 | `data_out` | output | `OUT_WIDTH` | Selected data |
| 3 | `valid_out` | output | 1 | Valid |
