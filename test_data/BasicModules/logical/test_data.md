# logical test data

Each subdirectory corresponds to one parameter set. `FUNC`: 0=AND, 1=NAND, 2=OR, 3=NOR, 4=XOR, 5=XNOR. Input files are named `sim_in1.csv`, `sim_in2.csv`, … (one per input port).

| Directory | NBITS | NINPUTS | LATENCY | FUNC | Cycles | Description |
|-----------|-------|---------|---------|------|--------|-------------|
| `simdata0` | 4 | 2 | 1 | 0 (AND)  | 16 | Bitwise AND of 2 inputs |
| `simdata1` | 4 | 2 | 1 | 1 (NAND) | 16 | Bitwise NAND of 2 inputs |
| `simdata2` | 4 | 2 | 1 | 2 (OR)   | 16 | Bitwise OR of 2 inputs |
| `simdata3` | 4 | 2 | 1 | 3 (NOR)  | 16 | Bitwise NOR of 2 inputs |
| `simdata4` | 4 | 2 | 1 | 4 (XOR)  | 16 | Bitwise XOR of 2 inputs |
| `simdata5` | 4 | 2 | 1 | 5 (XNOR) | 16 | Bitwise XNOR of 2 inputs |
| `simdata6` | 4 | 3 | 1 | 0 (AND)  | 16 | AND of 3 inputs — verifies NINPUTS reduction chain |
| `simdata7` | 4 | 2 | 2 | 4 (XOR)  | 16 | XOR with LATENCY=2 — verifies multi-stage pipeline |
