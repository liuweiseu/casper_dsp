# logical test data

Each subdirectory corresponds to one parameter set. `FUNC`: 0=AND, 1=NAND, 2=OR, 3=NOR, 4=XOR, 5=XNOR. Input files are named `sim_in1.csv`, `sim_in2.csv`, … (one per input port).

**CSV data exported from the corresponding MATLAB Simulink block.**

| Test # | Directory | NBITS | NINPUTS | LATENCY | FUNC | Cycles | Description |
|--------|-----------|-------|---------|---------|------|--------|-------------|
| 0 | `simdata0` | 4 | 2 | 1 | 0 (AND)  | 16 | Bitwise AND of 2 inputs |
| 1 | `simdata1` | 4 | 2 | 1 | 1 (NAND) | 16 | Bitwise NAND of 2 inputs |
| 2 | `simdata2` | 4 | 2 | 1 | 2 (OR)   | 16 | Bitwise OR of 2 inputs |
| 3 | `simdata3` | 4 | 2 | 1 | 3 (NOR)  | 16 | Bitwise NOR of 2 inputs |
| 4 | `simdata4` | 4 | 2 | 1 | 4 (XOR)  | 16 | Bitwise XOR of 2 inputs |
| 5 | `simdata5` | 4 | 2 | 1 | 5 (XNOR) | 16 | Bitwise XNOR of 2 inputs |
| 6 | `simdata6` | 4 | 3 | 1 | 0 (AND)  | 16 | AND of 3 inputs — verifies NINPUTS reduction chain |
| 7 | `simdata7` | 4 | 2 | 2 | 4 (XOR)  | 16 | XOR with LATENCY=2 — verifies multi-stage pipeline |
