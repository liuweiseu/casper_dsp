# slice test data

This directory contains one parameter set tested against `simulation.toml`.

**CSV data exported from the corresponding MATLAB Simulink block.**

Simulink data: the `sim_*.csv` files of set 0 were exported from Simulink models of the block (MATLAB R2021a, System Generator; plugins-demo2 export flow with its own random stimulus) and copied here on 2026-10-14; `params.json` (and any `.mem` files) are the generator's. Regenerating the module with its script replaces the exported CSVs with the reference model's output.

| Parameter | Value |
|-----------|-------|
| `START_BIT` | 2 |
| `WIDTH` | 2 |

Extracts a 2-bit field starting at bit 2 from the input bus. Each file contains **513 cycles**.
