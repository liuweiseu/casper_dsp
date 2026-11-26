# delay_srl

## Description

A fixed-length shift-register delay with an optional synchronous reset and
clock enable. It extends the [`delay`](../BasicModules/delay.md) pattern and
corresponds to casper_library's `delay_srl`. The chain is built from
`DELAY_LEN` [`register`](../BasicModules/register.md) stages, which all share
the same `rst` and `en`:

```
din ──► register ──► register ──► … ──► register ──► dout
```

## Parameters

| Parameter    | Default | Description |
|--------------|---------|-------------|
| `BITWIDTH`   | 8       | Data width |
| `DELAY_LEN`  | 4       | Number of stages; `0` = combinational pass-through |
| `USE_ENABLE` | 1       | `1`: stages shift only while `en = 1`; `0`: `en` is ignored |
| `USE_RST`    | 1       | `1`: `rst` synchronously clears every stage; `0`: `rst` is ignored |

## Ports

| Port   | Direction | Width      | Description |
|--------|-----------|------------|-------------|
| `clk`  | input     | 1          | Clock |
| `rst`  | input     | 1          | Synchronous clear, higher priority than `en` (used when `USE_RST = 1`) |
| `en`   | input     | 1          | Shift enable (used when `USE_ENABLE = 1`) |
| `din`  | input     | `BITWIDTH` | Input |
| `dout` | output    | `BITWIDTH` | `din` delayed by `DELAY_LEN` enabled cycles |

## Functional Description

On each clock edge the chain resets if `rst` is high (when `USE_RST = 1`).
Otherwise it shifts by one position, provided `en` is high or `USE_ENABLE = 0`.
When `en` is low, every stage holds its value. All stages power up to 0. With
`USE_RST = 0`, the chain has no reset, so synthesis can map it to SRL
shift-register primitives.
