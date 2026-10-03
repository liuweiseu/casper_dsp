# xeng_descramble

## Description

Port of casper_library's `xeng_descramble` (`casper_library_correlator.slx`, Block SID 411). The block has no `_init.m`: the mask initialization is stored in `system_root.xml` and the diagram in `system_411.xml`. It takes the X-engine's tap-ordered relay stream and reorders it into one word per baseline (element). The wrapped-around baselines are conjugated on the way. Every element is then read out as `DEMUX_FACTOR` narrow words.

```
acc ─ write_ctrl ─ data ─ x_cast ─┐
                 ─ addr, we ──────┴─ dual-port RAM, port B (wide 8P bits, E+1 words)
start (write_ctrl) ─ read_ctrl ─ addr ─ port A (narrow OW bits, latency RAM_LATENCY) ─ acc_out
valid_out = delay(read_ctrl.enable, RAM_LATENCY)
sync_out  = delay(start & sync_seen, RAM_LATENCY),  sync_seen = register(d = en = sync, rst = start)
```

Input stream: `acc` carries four complex values `{c3, c2, c1, c0}`, each `{re, im}` of `W` bits. Every antenna line delivers a burst of `T = N/2+1` consecutive valid words, one per tap; this is what the X-engine's relay chain produces.

**write_ctrl** counts tap, line and element, then:
- Words with `line + tap < T−1` (the "last triangle") are conjugated, with c1 and c0 swapped, and written from address `PIVOT` up.
- Their tap-0 words are blanked (not written).
- All other words are written from address 0 up, in arrival order.
- `start` fires when the element counter reaches `ceil(3·NV/4)`.

**read_ctrl** then reads the `D·E` narrow words, one every `DEL+1` cycles. Narrow word `r` is block `r % D` of element `r / D`, counted from the MSB of the stored word. Each 8-field word passes through x_cast (block reversal, sign extension to `P` bits) on its way in, and the narrow port is LSB-first, so the blocks come out in this order.

Address map for N = 8 (rows = lines, columns = taps 0..4; `*` = conjugated, `–` = blank):

```
L0: –  30* 31* 32* 0      L4: 10 11 12 13 14
L1: –  33* 34* 1   2      L5: 15 16 17 18 19
L2: –  35* 3   4   5      L6: 20 21 22 23 24
L3: –  6   7   8   9      L7: 25 26 27 28 29
```

The conjugated region (`PIVOT .. E−1`) of each readout is taken from the first lines of the *next* output window. That is where the X-engine emits a frame's wrapped-around baselines: its taps' `a_end` inputs carry the previous frame's antennas. The readout reaches those addresses after the next window has written them. `negedge_delay` keeps accepting words for `ceil(N/2)·ACC_LEN` cycles after `win_valid` falls, so the last frame also gets them.

Derived values (mask initialization, N = `NUM_ANTS`, L = `ACC_LEN`, D = `DEMUX_FACTOR`):

| Name | Value |
|------|-------|
| `T`, `NV`, `E` | `N/2+1`, `N·T`, `N(N+1)/2` |
| `PIVOT` | `N/2·T + T·N/4` |
| `W` | `2·N_BITS + floor(log2 L) + 1` (one bit less than the taps' `N_BITS_OUT` when L is not a power of 2) |
| `P`, `OW` | `2^ceil(log2 W)`, `8P/D` |
| `DEL` | `floor(L·N/NV/D) − 1`. A negative value makes the mask show an errordlg and use 0; here it gives a `$warning` and 0 |
| `CNT` | `D·E − 1` if `DEL = 0`, else `D·E` |

Defaults (N 8, N_BITS 4, L 128, D 8): W = P = OW = 16, DEL = 2, CNT = 288.

**Power-on:** read_ctrl's `done` register starts at 0, so a read pass of `D·E` words runs with `valid_out = 1` before any `start`; `sync_out` stays 0 during it. The library RAM has `initVector = [1:36*8]`, a leftover from the N = 8 default. This RAM powers up to 0, so that pass reads zeros. That is the only deviation from the diagram.

Built from `write_ctrl`, `x_cast`, `read_ctrl` (in `Correlator/Internal`), `dual_port_ram`, `pipeline`, `delay`, `register` and `logical`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `NUM_ANTS` | 8 | Number of antennas (mask). Must be even and ≥ 4 |
| `N_BITS` | 4 | X-engine input bits (mask) |
| `ACC_LEN` | 128 | Integration length (mask) |
| `DEMUX_FACTOR` | 8 | Narrow words per element: 1, 2, 4 or 8 (mask) |
| `RAM_LATENCY` | 1 | Read-side latency (RAM, `valid_out`, `sync_out`). Not a mask parameter; 2 in `xeng_descramble_4ant` |
| `PLATFORM` | "GENERIC" | `dual_port_ram` vendor |
| `W` / `P` / `OW` | derived | See above. Do not override |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `acc` | input | `8*W` | `{c3, c2, c1, c0}`, each `{re, im}` |
| `valid` | input | 1 | X-engine valid |
| `sync` | input | 1 | Sync (also resets the tap/line/element counters one cycle later) |
| `win_valid` | input | 1 | Window valid. Its rising edge resets the counters; its falling edge is extended by `negedge_delay` |
| `acc_out` | output | `OW` | Narrow element words |
| `valid_out` | output | 1 | Narrow word valid |
| `sync_out` | output | 1 | Marks a readout start that followed a sync |
