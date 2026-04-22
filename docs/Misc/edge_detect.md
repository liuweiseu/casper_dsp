# edge_detect

## Description

Detects rising edges, falling edges, or any transition on a single-bit input signal. The previous input value is captured in a register on each rising clock edge; the comparison against the current input is combinational, so `dout` is valid in the same clock cycle that the transition is applied. Output polarity is configurable.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `EDGE_TYPE` | 0 | Edge to detect: 0 = rising edge, 1 = falling edge, 2 = both edges |
| `OUTPUT_POL` | 0 | Output polarity: 0 = active high, 1 = active low |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock signal |
| `din` | input | 1 | Input signal to monitor |
| `dout` | output | 1 | Edge detection output; pulses for one cycle when the configured edge is detected |

## Behavior

`dout` is combinational with respect to `din` and the registered `din_prev`, so the pulse is visible in the **same clock cycle** that the transition is sampled (no extra register stage on the output).

| `EDGE_TYPE` | `OUTPUT_POL` | Behaviour |
|-------------|--------------|-----------|
| 0 (rising)  | 0 (active high) | `dout` pulses high for one cycle when a 0→1 transition is sampled |
| 0 (rising)  | 1 (active low)  | `dout` pulses low for one cycle when a 0→1 transition is sampled |
| 1 (falling) | 0 (active high) | `dout` pulses high for one cycle when a 1→0 transition is sampled |
| 1 (falling) | 1 (active low)  | `dout` pulses low for one cycle when a 1→0 transition is sampled |
| 2 (both)    | 0 (active high) | `dout` pulses high for one cycle when any transition is sampled |
| 2 (both)    | 1 (active low)  | `dout` pulses low for one cycle when any transition is sampled |
