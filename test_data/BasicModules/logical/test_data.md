# logical test data

Each subdirectory corresponds to one parameter set. `FUNC`: 0=AND, 1=NAND, 2=OR, 3=NOR, 4=XOR, 5=XNOR. Input files are named `sim_in1.csv`, `sim_in2.csv`, … (one per input port).

| Directory | NBITS | NINPUTS | LATENCY | FUNC | Description |
|-----------|-------|---------|---------|------|-------------|
| `simdata0` | 4 | 2 | 1 | 0 (AND)  | Bitwise AND of 2 inputs |
| `simdata1` | 4 | 2 | 1 | 1 (NAND) | Bitwise NAND of 2 inputs |
| `simdata2` | 4 | 2 | 1 | 2 (OR)   | Bitwise OR of 2 inputs |
| `simdata3` | 4 | 2 | 1 | 3 (NOR)  | Bitwise NOR of 2 inputs |
| `simdata4` | 4 | 2 | 1 | 4 (XOR)  | Bitwise XOR of 2 inputs |
| `simdata5` | 4 | 2 | 1 | 5 (XNOR) | Bitwise XNOR of 2 inputs |
| `simdata6` | 4 | 3 | 1 | 0 (AND)  | AND of 3 inputs — verifies NINPUTS reduction chain |
| `simdata7` | 4 | 2 | 2 | 4 (XOR)  | XOR with LATENCY=2 — verifies multi-stage pipeline |
