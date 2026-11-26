# xeng_descramble_4ant

## Description

Port of casper_library's `xeng_descramble_4ant` (`casper_library_correlator.slx`, Block SID 928), the 4-antenna descrambler. It is a thin wrapper around `xeng_descramble` with `NUM_ANTS = 4` and `RAM_LATENCY = 2`.

Diff of the stored diagrams (`system_928/973/995/1107` against `411/456/478/588`):

- **Read-side latency is 2:** the Dual Port RAM, the `valid_out` Delay and the `sync_out` AND each have latency 2.
- **Counter2 is a constant 9 in write_ctrl.** For 4 antennas `PIVOT = E−1 = 9`, so Counter2 (PIVOT .. E−1) would be a constant 9 anyway.
- **write_ctrl's `negedge_delay` is an inline copy.** Its stale link data names the inner edge detector "Both", but the stored detector is the falling-edge one, as in the library.
- **read_ctrl and x_cast are identical.**

Address map (N = 4): `L0: – 9* 0`, `L1: – 1 2`, `L2: 3 4 5`, `L3: 6 7 8`.

Defaults (N_BITS 8, ACC_LEN 256, DEMUX 1): W = 25, P = 32, OW = 256, DEL = 84, CNT = 10.

See `xeng_descramble.md` for the behaviour, including the conjugated region coming from the next output window and the power-on read pass.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_BITS` | 8 | X-engine input bits (mask) |
| `ACC_LEN` | 256 | Integration length (mask) |
| `DEMUX_FACTOR` | 1 | Narrow words per element: 1, 2, 4 or 8 (mask) |
| `PLATFORM` | "GENERIC" | `dual_port_ram` vendor |
| `W` / `P` / `OW` | derived | As in `xeng_descramble` |

## Ports

As `xeng_descramble`.
