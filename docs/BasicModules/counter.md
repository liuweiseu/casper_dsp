# counter

## Description

A configurable counter supporting free-running (wrap-around) and count-limit modes. Counting direction (up, down, or up-down) and step size are parameterizable. The counter powers on at `INIT_VAL`; a count-limit counter that reaches `COUNT_TO_VAL` loads `INIT_VAL` on its next count. An optional synchronous reset (`ENABLE_SYNC_RST`) loads `RST_VAL` and an optional enable (`ENABLE_ENABLE`) gates counting; reset has priority over enable. The load port is reserved for future use.

The Xilinx System Generator Counter loads `start_count` on power-on, on reset and on a count-limit wrap, so a Sysgen Counter with `start_count = S` maps to `INIT_VAL = RST_VAL = S`. The default `RST_VAL = 0` keeps the original clear-to-zero reset.

The wrap-to-`start_count` behaviour is confirmed by the Simulink-exported test data (`simdata3`/`simdata4`). That reset loads `start_count` is an assumption taken from the Sysgen Counter semantics: none of the stored Simulink data drives `rst`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `COUNTER_TYPE` | 0 | Counting mode: 0 = free running (wraps around), 1 = count limit (after `COUNT_TO_VAL` the next count loads `INIT_VAL`) |
| `NBITS` | 8 | Counter bit width |
| `COUNT_TO_VAL` | 0 | Target value for count-limit mode; only used when `COUNTER_TYPE = 1` |
| `COUNT_DIR` | 0 | Count direction: 0 = up, 1 = down, 2 = up-down (not yet implemented) |
| `INIT_VAL` | 0 | Power-on value; also the value loaded after `COUNT_TO_VAL` in count-limit mode |
| `STEP` | 1 | Increment/decrement step per clock cycle |
| `BIN_P` | 0 | Binary point position (metadata for use by higher-level blocks) |
| `ENABLE_LOAD` | 0 | Reserved: enable a load port (not yet implemented) |
| `ENABLE_SYNC_RST` | 0 | 1 = `rst` synchronously loads `RST_VAL` |
| `ENABLE_ENABLE` | 0 | 1 = count only when `enable` is high |
| `RST_VAL` | 0 | Value loaded by the synchronous reset (Sysgen `start_count`) |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `rst` | input | 1 | Synchronous reset to `RST_VAL` (used when `ENABLE_SYNC_RST = 1`) |
| `enable` | input | 1 | Count enable (used when `ENABLE_ENABLE = 1`) |
| `dout` | output | `NBITS` | Current counter value |
