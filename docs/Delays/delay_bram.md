# delay_bram

## Description

A long delay line stored in RAM instead of a register chain: `dout` is `din`
delayed by `DELAY_LEN` clock cycles. It corresponds to casper_library's
`delay_bram`. The module has no platform-specific logic. It passes `PLATFORM`
down to [`single_port_ram`](single_port_ram.md), which chooses the
implementation (on Xilinx, `xpm_memory_spram`).

```
counter (0 … DELAY_LEN-2, wraps) ──► addr ┐
din ─────────────────────────────► din   ├─ single_port_ram (READ_FIRST) ──► dout
                                  we = 1  ┘
```

## Parameters

| Parameter   | Default     | Description |
|-------------|-------------|-------------|
| `BITWIDTH`  | 8           | Data width |
| `DELAY_LEN` | 16          | Delay in clock cycles |
| `BRAM_LATENCY` | 2 | casper `bram_latency`; only moves registers inside Simulink's block (the HDL ignores it). Async with `BRAM_LATENCY = 1` cannot be built in Simulink |
| `ASYNC` | 0 | casper `async`: `1` = `en` stalls the counter, the RAM and its output, a delay of `DELAY_LEN` enabled samples that holds while `en` = 0 (checked against Simulink, MATLAB R2021a); no `dvalid` |
| `PLATFORM`  | `"GENERIC"` | Passed to `single_port_ram` (`"GENERIC"`, `"XILINX"`, `"ALTERA"`) |

## Ports

| Port   | Direction | Width      | Description |
|--------|-----------|------------|-------------|
| `clk`  | input     | 1          | Clock |
| `din`  | input     | `BITWIDTH` | Input |
| `en`   | input     | 1          | Async enable (used when `ASYNC = 1`; default 1) |
| `dout` | output    | `BITWIDTH` | `din` delayed by `DELAY_LEN` cycles |

## Functional Description

The RAM writes `din` on every cycle, at an address from a
[`counter`](../BasicModules/counter.md) in count-limit mode that wraps after
`M = DELAY_LEN − 1` addresses. The RAM reads READ_FIRST, so the same access
returns the word written to that address `M` cycles earlier. The RAM's 1-cycle
output register adds one more cycle, giving a total delay of `M + 1 = DELAY_LEN`.

- `M` need not be a power of two. The RAM depth is `2^clog2(M)`.
- `DELAY_LEN < 2` does not justify a RAM. The module then falls back to a
  [`pipeline`](pipeline.md) of `DELAY_LEN` registers (`0` = combinational).
- The RAM and the output power up to 0, so the first `DELAY_LEN` outputs are 0.
- casper_library's `delay_bram` also has a `bram_latency` parameter (extra
  output registers). It is not implemented here. Add a `pipeline` after the
  module if more output registers are needed.
