# armed_trigger

## Description

A one-shot trigger with an explicit arm step. The module must be armed before it can fire: once armed, the first active `trig_in` cycle produces a single-cycle pulse on `trig_out` and the module automatically disarms. Sending another `arm` rising edge re-arms the module for the next trigger.

The module is armed by default at power-on (internal register initialised to 1).

## Parameters

None.

## Ports

| Port      | Direction | Width | Description |
|-----------|-----------|-------|-------------|
| `clk`     | input     | 1     | Clock signal |
| `arm`     | input     | 1     | A rising edge arms the module (re-arms if already armed) |
| `trig_in` | input     | 1     | Trigger input; only effective while the module is armed |
| `trig_out`| output    | 1     | One-cycle pulse when `trig_in` is asserted while armed |

## Internal structure

| Submodule | Role |
|-----------|------|
| `edge_detect` (EDGE_TYPE=0, OUTPUT_POL=0) | Detects rising edge of `arm`; 1-cycle active-high pulse drives the register reset |
| `register` (BITWIDTH=1, USE_RST=1, USE_ENABLE=1, INIT_VAL=1) | Holds the armed state; reset to 1 by `arm` edge, cleared to 0 by `trig_out` feedback |
| `logical` (FUNC=AND, NINPUTS=2, LATENCY=0) | Computes `trig_out = trig_in AND armed`; output is fed back to register enable |

## Timing

| Cycle | Event |
|-------|-------|
| N     | `arm` 0→1 rising edge |
| N+1   | `arm_edge` pulse arrives; register resets to 1 (armed) |
| N+1+k | `trig_in` goes high; `trig_out` pulses for one cycle |
| N+2+k | Register clears to 0 (disarmed); `trig_out` returns low |

`arm` reset takes priority over the `trig_out` feedback: if an `arm` edge and a `trig_in` pulse arrive simultaneously, the module re-arms cleanly.
