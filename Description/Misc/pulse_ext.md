# pulse_ext

## Description

Detects a rising edge on `in` and asserts `out` for exactly `PULSE_LEN` clock cycles.
A new rising edge during an active pulse resets the counter to 0, restarting the
full `PULSE_LEN`-cycle pulse from that point.

> **Power-on note:** With `INIT_VAL=0` the counter starts at 0, so `out` is
> asserted for `PULSE_LEN` cycles immediately after power-on before settling into
> the idle state.  Apply a system reset upstream if a clean initial state is needed.

The module is composed of four primitives connected as follows:

```
in ──► edge_detect ──► trig ──► counter.rst   (clears cnt to 0)

constant(PULSE_LEN) ───────────► relational.b

counter.dout ──────────────────► relational.a
       ▲                               │
       └────── enable ◄── relational.out ──► out
                          (cnt != PULSE_LEN)
```

1. **`edge_detect`** (`EDGE_TYPE=0`, `OUTPUT_POL=0`) — produces a 1-cycle active-high
   strobe `trig` on each rising edge of `in`. Connected to `counter.rst`.
2. **`constant`** (`VAL=PULSE_LEN`) — supplies `PULSE_LEN` as the comparison reference
   for `relational.b`.
3. **`counter`** (`COUNTER_TYPE=free_running`, `COUNT_DIR=up`, `INIT_VAL=0`,
   `ENABLE_SYNC_RST=1`, `ENABLE_ENABLE=1`) — counts from 0 upward. `rst` (from
   `edge_detect`) synchronously clears `cnt` to 0. `enable` (from `relational`) gates
   counting, stopping the counter when `cnt` reaches `PULSE_LEN`.
4. **`relational`** (`COMP=ne`, `LATENCY=0`) — compares `counter.dout` against
   `constant.out`. Output is `1` while `cnt != PULSE_LEN`. This signal drives both
   `counter.enable` and the module output `out`.

Total latency from rising edge to first asserted output: **2 clock cycles**
(1 from `edge_detect` + 1 from counter clear).

## Parameters

| Parameter   | Default | Description |
|-------------|---------|-------------|
| `PULSE_LEN` | 4       | Number of clock cycles `out` is asserted after a trigger |

## Ports

| Port  | Direction | Width | Description |
|-------|-----------|-------|-------------|
| `clk` | input     | 1     | Clock signal |
| `in`  | input     | 1     | Trigger input — rising edge starts the pulse |
| `out` | output    | 1     | Pulse output, asserted for `PULSE_LEN` cycles |

## Behaviour

```
clk    _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
in     _____|‾‾‾‾‾‾‾‾‾‾‾|___________________
out    ___________|‾‾‾‾‾‾‾‾‾‾‾|_____________
                  |← PULSE_LEN →|
       (2-cycle latency from rising edge)
```

A second rising edge while `out` is high resets the counter to 0 and extends the
pulse by `PULSE_LEN` cycles from that point.
