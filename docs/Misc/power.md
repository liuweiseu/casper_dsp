# power

## Description

Computes |c|² of a complex input, as the casper_library block
`casper_library_misc/power` (built by `power_behav.m`).

`c` packs `{re, im}`, with `re` in the MSBs. Each part is a signed fraction
`Fix_<BIT_WIDTH>_<BIT_WIDTH−1>`. The pipeline is:

```
re², im²  : full-precision Xilinx Mults (Fix_<2·BIT_WIDTH>_<2·BIT_WIDTH−2>), MULT_LATENCY registers
dout      : AddSub re² + im², UFix_<2·BIT_WIDTH+1>_<2·BIT_WIDTH>, Truncate / Wrap, ADD_LATENCY registers
```

- **Output type:** `dout` is `UFix_<2·BIT_WIDTH+1>_<2·BIT_WIDTH>`, which is
  `UFix_37_36` for `BIT_WIDTH = 18`.
- **Latency:** `MULT_LATENCY + ADD_LATENCY` cycles.
- **Overflow:** the only value that does not fit is `re = im = −1`
  (|c|² = 2). It wraps to 0, as in Simulink.
- **Power-on:** the registers power up to 0.
- **Simulink port name:** the output is called `power` in Simulink. Verilator
  rejects a port with the same name as its module, so here it is `dout`.

The module is built from `c_to_ri`, `multiplier` (a bus_mult lane) and
`adder_subtractor` (a bus_addsub lane).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `BIT_WIDTH` | 18 | Width of `re` and `im` (mask `BitWidth`) |
| `ADD_LATENCY` | 2 | AddSub latency (mask `add_latency`) |
| `MULT_LATENCY` | 3 | Mult latency (mask `mult_latency`) |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `c` | input | `2·BIT_WIDTH` | Complex input `{re, im}` |
| `dout` | output | `2·BIT_WIDTH+1` | \|c\|², UFix_<2·BIT_WIDTH+1>_<2·BIT_WIDTH> (Simulink `power`) |
