# logical test data

Each subdirectory corresponds to one parameter set. `FUNC`: 0=AND, 1=NAND, 2=OR, 3=NOR, 4=XOR, 5=XNOR. The input file `sim_din.csv` has one column per element of the `din` array port (column j = `din[j]`); `sim_dout.csv` holds the expected output.

**CSV data exported from the corresponding MATLAB Simulink block.**

This applies to `simdata0`–`simdata7` (`USE_ENABLE` = 0). `simdata8` tests the enable (`en` from `sim_en.csv`). It is generated from a Python model of the Xilinx System Generator block (`data/sysgen/block_models/xl*.sgm`) by `test_data/scripts/gen_basic_test_data.py`, which also writes a `params.json` for each set (the testbench matches the DUT parameters against it).

| Test # | Directory | NBITS | NINPUTS | LATENCY | FUNC | USE_ENABLE | Cycles | Description |
|--------|-----------|-------|---------|---------|------|------------|--------|-------------|
| 0 | `simdata0` | 4 | 2 | 1 | 0 (AND)  | 0 | 16 | Bitwise AND of 2 inputs |
| 1 | `simdata1` | 4 | 2 | 1 | 1 (NAND) | 0 | 16 | Bitwise NAND of 2 inputs |
| 2 | `simdata2` | 4 | 2 | 1 | 2 (OR)   | 0 | 16 | Bitwise OR of 2 inputs |
| 3 | `simdata3` | 4 | 2 | 1 | 3 (NOR)  | 0 | 16 | Bitwise NOR of 2 inputs |
| 4 | `simdata4` | 4 | 2 | 1 | 4 (XOR)  | 0 | 16 | Bitwise XOR of 2 inputs |
| 5 | `simdata5` | 4 | 2 | 1 | 5 (XNOR) | 0 | 16 | Bitwise XNOR of 2 inputs |
| 6 | `simdata6` | 4 | 3 | 1 | 0 (AND)  | 0 | 16 | AND of 3 inputs — verifies NINPUTS reduction chain |
| 7 | `simdata7` | 4 | 2 | 2 | 4 (XOR)  | 0 | 16 | XOR with LATENCY=2 — verifies multi-stage pipeline |
| 8 | `simdata8` | 4 | 3 | 2 | 2 (OR)   | 1 | 200 | OR of 3 inputs, two pipeline stages held while `en` is low |
