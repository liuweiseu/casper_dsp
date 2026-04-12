# edge_detect test data

Each subdirectory corresponds to one parameter set. `EDGE_TYPE`: 0 = rising edge, 1 = falling edge. `OUTPUT_POL`: 0 = active high, 1 = active low.

| Directory | EDGE_TYPE | OUTPUT_POL | Description |
|-----------|-----------|------------|-------------|
| `simdata0` | 0 (rising)  | 0 (active high) | Detect rising edge, output pulse active high |
| `simdata1` | 0 (rising)  | 1 (active low)  | Detect rising edge, output pulse active low |
| `simdata2` | 1 (falling) | 0 (active high) | Detect falling edge, output pulse active high |
| `simdata3` | 1 (falling) | 1 (active low)  | Detect falling edge, output pulse active low |
