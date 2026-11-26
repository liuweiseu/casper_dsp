# write_ctrl

## Description

The write-side controller of `xeng_descramble` (`system_478`; `xeng_descramble_4ant`'s copy is `system_995`). It is not a library block.

```
rst_in   = delay(sync, 1) | rise(window_valid)
valid_in = delay(negedge_delay(window_valid, ceil(N/2)·ACC_LEN) & xeng_valid, 1)
rst = delay(rst_in, 1),  vld = delay(valid_in, 1),  dat = delay(data_in, 2)
tap     0..T−1   rst = rst_in, en = (tap == T−1) | valid_in
line    0..N−1   rst = rst_in, en = (tap == T−1) & valid_in
element 0..NV−1  rst = rst_in, en = valid_in
last  = ~delay(tap ≥ T−1−line, 1)          (signed compare)
blank = delay(tap == 0, 1) & last
Counter3 0..PIVOT−1        rst = rst, en = vld & ~last
Counter2 PIVOT..E−1        reset and wrap to PIVOT, rst = rst, en = last & ~blank & vld
write_addr = last ? Counter2 : Counter3,   enable = vld & ~blank
data_out   = last ? {conj c3, conj c2, conj c0, conj c1} : dat      (W-bit Wrap negate of im)
start_readout = rise(delay(element == ceil(3·NV/4), 1))
```

Some details:

- **The tap counter's enable is an OR.** After the last tap it wraps on the next cycle even without a valid word. The X-engine delivers each line as a burst of T consecutive words, so this works there. A hole just before a burst's last word shifts the map, exactly as in the diagram, and one test set covers it.
- **`T−1−line` is signed.** It comes from a full-precision AddSub, so the compare uses `relational` with `SIGNED = 1` and a zero-extended tap.
- **Counter2 relies on the `counter` `RST_VAL` parameter** (Xilinx `start_count` on reset).

Built from `delay`, `edge_detect` ×2, `negedge_delay`, `counter` ×5, `constant`, `relational` ×4, `multiplexer` ×2 and `negate` ×4.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_ANTS` | 8 | N |
| `ACC_LEN` | 128 | Integration length (for the negedge_delay pulse length) |
| `W` | 16 | Width of each real / imaginary part |
| `T`, `NV`, `E`, `PIVOT`, `WA_BITS`, `K_START`, `PULSE_LEN` | derived | `xeng_descramble` mask initialization values |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `sync` / `xeng_valid` / `window_valid` | input | 1 | See above |
| `data_in` | input | `8*W` | `{c3, c2, c1, c0}` |
| `start_readout` | output | 1 | Starts read_ctrl |
| `write_addr` | output | `WA_BITS` | Element address |
| `data_out` | output | `8*W` | Word to store (possibly conjugated) |
| `enable` | output | 1 | Write enable |
