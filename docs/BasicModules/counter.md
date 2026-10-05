# counter

## Description

A configurable counter modelled on the Xilinx System Generator Counter block. It has free-running (wrap-around) and count-limit modes. The direction is fixed up or down, or taken each cycle from the `up` port, and the step size is a parameter. Optional ports provide a synchronous reset, an enable and a load.

On each clock edge, in priority order (from the Sysgen block model `data/sysgen/block_models/xlCounter.sgm`):

1. `rst` (when `ENABLE_SYNC_RST = 1`): load `RST_VAL`.
2. Otherwise, if `enable` is high, or `ENABLE_ENABLE = 0`:
   1. In count-limit mode, a counter at `COUNT_TO_VAL` loads `INIT_VAL`. This takes priority over `load`.
   2. `load` (when `ENABLE_LOAD = 1`): load `din`.
   3. Otherwise count by `STEP`. The direction is up for `COUNT_DIR = 0` and down for `COUNT_DIR = 1`. For `COUNT_DIR = 2` it follows the `up` port: 1 counts up, 0 counts down.

The counter powers on at `INIT_VAL`. Sysgen's `start_count` is the power-on value, the reset value and the count-limit wrap value. So a Sysgen Counter maps to `INIT_VAL = start_count`, and `RST_VAL` defaults to `INIT_VAL`. Set `RST_VAL` only to model a reset value that differs from `start_count`.

`INIT_VAL`, `STEP`, `COUNT_TO_VAL` and `din` are raw bit patterns. The Sysgen binary point and signedness only change how those bits are read, not how the counter counts.

`load`, `din` and `up` have default values (0, 0 and 1). An instance that does not use them may leave them unconnected.

Mask mapping:

| Sysgen | Here |
|---|---|
| `cnt_type` | `COUNTER_TYPE` |
| `n_bits` | `NBITS` |
| `bin_pt` | `BIN_P` |
| `cnt_to` | `COUNT_TO_VAL` |
| `operation` | `COUNT_DIR` |
| `start_count` | `INIT_VAL` |
| `cnt_by_val` | `STEP` |
| `load_pin` | `ENABLE_LOAD` |
| `rst` | `ENABLE_SYNC_RST` |
| `en` | `ENABLE_ENABLE` |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `COUNTER_TYPE` | 0 | Counting mode: 0 = free running (wraps around), 1 = count limit (after `COUNT_TO_VAL` the next count loads `INIT_VAL`) |
| `NBITS` | 8 | Counter bit width |
| `COUNT_TO_VAL` | 0 | Target value for count-limit mode; only used when `COUNTER_TYPE = 1` |
| `COUNT_DIR` | 0 | Count direction: 0 = up, 1 = down, 2 = up/down from the `up` port |
| `INIT_VAL` | 0 | Power-on value; also the value loaded after `COUNT_TO_VAL` in count-limit mode (Sysgen `start_count`) |
| `STEP` | 1 | Increment/decrement step per clock cycle |
| `BIN_P` | 0 | Binary point; interpretation only, it does not change the logic |
| `ENABLE_LOAD` | 0 | 1 = `load` loads `din` (gated by `enable`) |
| `ENABLE_SYNC_RST` | 0 | 1 = `rst` synchronously loads `RST_VAL` |
| `ENABLE_ENABLE` | 0 | 1 = count, wrap and load only when `enable` is high |
| `RST_VAL` | `INIT_VAL` | Value loaded by the synchronous reset |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `rst` | input | 1 | Synchronous reset to `RST_VAL` (used when `ENABLE_SYNC_RST = 1`) |
| `enable` | input | 1 | Count enable (used when `ENABLE_ENABLE = 1`) |
| `load` | input | 1 | Load `din` (used when `ENABLE_LOAD = 1`; default 0) |
| `din` | input | `NBITS` | Value loaded by `load` (default 0) |
| `up` | input | 1 | Direction for `COUNT_DIR = 2`: 1 = up, 0 = down (default 1) |
| `dout` | output | `NBITS` | Current counter value |
