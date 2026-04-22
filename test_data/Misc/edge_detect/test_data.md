# edge_detect test data

Input sequences (`sim_in.csv`) and expected outputs (`sim_out.csv`) are exported from a MATLAB Simulink model of the edge_detect block. Each subdirectory corresponds to one parameter set. `EDGE_TYPE`: 0 = rising edge, 1 = falling edge, 2 = both edges. `OUTPUT_POL`: 0 = active high, 1 = active low.

| Test # | Directory | EDGE_TYPE | OUTPUT_POL | Cycles | Description |
|--------|-----------|-----------|------------|--------|-------------|
| 0 | `simdata0` | 0 (rising)  | 0 (active high) | 100 | Detect rising edge, output pulse active high |
| 1 | `simdata1` | 0 (rising)  | 1 (active low)  | 100 | Detect rising edge, output pulse active low |
| 2 | `simdata2` | 1 (falling) | 0 (active high) | 100 | Detect falling edge, output pulse active high |
| 3 | `simdata3` | 1 (falling) | 1 (active low)  | 100 | Detect falling edge, output pulse active low |
| 4 | `simdata4` | 2 (both)    | 0 (active high) | 100 | Detect any edge, output pulse active high |
| 5 | `simdata5` | 2 (both)    | 1 (active low)  | 100 | Detect any edge, output pulse active low |
