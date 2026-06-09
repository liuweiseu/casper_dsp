# counter

## Description

A configurable counter supporting free-running (wrap-around) and count-limit (stop at target) modes. Counting direction (up, down, or up-down) and step size are parameterizable. The counter initializes to `INIT_VAL` at simulation start. Parameters for load, synchronous reset, and enable ports are reserved for future use.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `COUNTER_TYPE` | 0 | Counting mode: 0 = free running (wraps around), 1 = count limit (holds at `COUNT_TO_VAL`) |
| `NBITS` | 8 | Counter bit width |
| `COUNT_TO_VAL` | 0 | Target value for count-limit mode; only used when `COUNTER_TYPE = 1` |
| `COUNT_DIR` | 0 | Count direction: 0 = up, 1 = down, 2 = up-down (not yet implemented) |
| `INIT_VAL` | 0 | Initial counter value |
| `STEP` | 1 | Increment/decrement step per clock cycle |
| `BIN_P` | 0 | Binary point position (metadata for use by higher-level blocks) |
| `ENABLE_LOAD` | 0 | Reserved: enable a load port (not yet implemented) |
| `ENABLE_SYNC_RST` | 0 | Reserved: enable a synchronous reset port (not yet implemented) |
| `ENABLE_ENABLE` | 0 | Reserved: enable an enable port (not yet implemented) |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `rst` | input | 1 | Reset signal (reserved; not used in current implementation) |
| `enable` | input | 1 | Enable signal (reserved; not used in current implementation) |
| `dout` | output | `NBITS` | Current counter value |
