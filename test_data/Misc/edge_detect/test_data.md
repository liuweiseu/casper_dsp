# edge_detect test data

Each subdirectory corresponds to one parameter set. `EDGE_TYPE`: 0 = rising edge, 1 = falling edge, 2 = both edges. `OUTPUT_POL`: 0 = active high, 1 = active low.

| Directory | EDGE_TYPE | OUTPUT_POL | Cycles | Description |
|-----------|-----------|------------|--------|-------------|
| `simdata0` | 0 (rising)  | 0 (active high) | 100 | Detect rising edge, output pulse active high |
| `simdata1` | 0 (rising)  | 1 (active low)  | 100 | Detect rising edge, output pulse active low |
| `simdata2` | 1 (falling) | 0 (active high) | 100 | Detect falling edge, output pulse active high |
| `simdata3` | 1 (falling) | 1 (active low)  | 100 | Detect falling edge, output pulse active low |
| `simdata4` | 2 (both)    | 0 (active high) | 100 | Detect any edge, output pulse active high |
| `simdata5` | 2 (both)    | 1 (active low)  | 100 | Detect any edge, output pulse active low |
