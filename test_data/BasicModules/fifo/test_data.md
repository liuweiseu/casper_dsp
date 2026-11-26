# fifo test data

Test data of the Xilinx FIFO block (`xbsIndex_r4/FIFO`). Each `simdataN/` holds one parameter set: `params.json` (the DUT parameters the testbench matches), the inputs `sim_din.csv`, `sim_we.csv`, `sim_re.csv` (and `sim_rst.csv` / `sim_en.csv` when `RST` / `EN` is 1) and the enabled outputs `sim_dout.csv`, `sim_empty.csv`, `sim_full.csv`, `sim_percent_full.csv` (raw bits of `%full`), `sim_dcount.csv`, `sim_ae.csv`, `sim_af.csv`. Line `i` is clock cycle `i`; all inputs are 0 in cycle 0.

**CSV data exported from the corresponding MATLAB Simulink block.**

Simulink data: every file of every set (inputs and outputs) was exported on 2026-10-27 from Simulink models of the block (MATLAB R2021a, System Generator 2021.1) built and simulated with the matlab-tools `create_simulink` / `run_simulation` scripts. Each model holds the FIFO block with the mask options of the set (the HDL-Simulink mapping in `rtl/BasicModules/fifo.sv`), a Gateway In per input fed by a Repeating Sequence Stair with deterministic stimulus (fill past full, drain past empty, random reads and writes, `en` gaps, `rst` pulses of 1-3 cycles) and a Gateway Out per output (`%full` through a Slice for its raw bits). There is no generator script: regenerating means re-exporting from Simulink. The platform block is SNAP (Kintex-7) or RFSoC4x2 (Zynq UltraScale+ RFSoC); both give the same behaviour, but RFSoC4x2 can only simulate the block with `rst` on and `rst_latency` >= 2, so the sets without reset or with `RST_LATENCY = 1` use SNAP.

Not covered, because Simulink gives no reference (mapping `unsupported`): `RST_LATENCY = 0`, `MEM_TYPE = 3` (Built-in FIFO) and the `rd_rst_busy` / `wr_rst_busy` ports.

`MEM_TYPE`: 0 Block RAM, 1 Distributed RAM, 2 Shift Register. `PERFORMANCE_OPTIONS`: 0 Standard, 1 First Word Fall Through.

| Test # | Directory | `DATA_WIDTH` | `MEM_TYPE` | `PERFORMANCE_OPTIONS` | `EMBEDDED_REGISTERS` | `DEPTH` | `PERCENT_NBITS` | `RST` | `RST_LATENCY` | `EN` | `USE_DCOUNT` | `USE_PERCENT_FULL_PORT` | `USE_ALMOST_EMPTY` | `ALMOST_EMPTY_THRESH` | `USE_ALMOST_FULL` | `ALMOST_FULL_THRESH` | Cycles | Description |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 0 | `simdata0` | 8 | 0 | 0 | 0 | 16 | 4 | 1 | 1 | 1 | 1 | 1 | 1 | 4 | 1 | 12 | 300 | Block RAM, Standard, every optional port but the reset-busy ones; rst_latency 1 (Simulink platform SNAP) |
| 1 | `simdata1` | 8 | 0 | 0 | 0 | 16 | 1 | 0 | 1 | 0 | 0 | 1 | 0 | 2 | 0 | 14 | 200 | mask defaults: Block RAM, Standard, depth 16, %full (1 bit) only (Simulink platform SNAP) |
| 2 | `simdata2` | 8 | 0 | 0 | 1 | 16 | 2 | 1 | 3 | 1 | 1 | 1 | 1 | 3 | 1 | 13 | 300 | Block RAM, Standard, embedded registers (2-cycle read), rst_latency 3 (Simulink platform RFSoC4x2) |
| 3 | `simdata3` | 8 | 0 | 1 | 0 | 16 | 3 | 1 | 2 | 1 | 1 | 1 | 1 | 5 | 1 | 11 | 300 | Block RAM, First Word Fall Through, %full and dcount, rst_latency 2 (Simulink platform RFSoC4x2) |
| 4 | `simdata4` | 3 | 1 | 0 | 0 | 32 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 29 | 1 | 3 | 400 | Distributed RAM, Standard, depth 32, 3-bit data, thresholds at their limits (Simulink platform SNAP) |
| 5 | `simdata5` | 5 | 1 | 1 | 0 | 32 | 5 | 1 | 4 | 1 | 1 | 1 | 1 | 27 | 1 | 5 | 400 | Distributed RAM, First Word Fall Through, depth 32, rst_latency 4 (Simulink platform RFSoC4x2) |
| 6 | `simdata6` | 6 | 2 | 0 | 0 | 16 | 3 | 1 | 5 | 1 | 0 | 1 | 1 | 6 | 1 | 10 | 300 | Shift Register, Standard, rst_latency 5, no dcount (Simulink platform RFSoC4x2) |
| 7 | `simdata7` | 12 | 0 | 0 | 0 | 64 | 6 | 1 | 2 | 1 | 1 | 1 | 1 | 3 | 1 | 61 | 500 | Block RAM, Standard, depth 64, 12-bit data (Simulink platform RFSoC4x2) |
| 8 | `simdata8` | 8 | 0 | 1 | 1 | 16 | 1 | 1 | 1 | 0 | 1 | 0 | 1 | 7 | 1 | 9 | 300 | Block RAM, First Word Fall Through, embedded registers (no effect), no en port (Simulink platform SNAP) |
| 9 | `simdata9` | 8 | 1 | 0 | 1 | 16 | 4 | 1 | 2 | 1 | 1 | 1 | 0 | 2 | 0 | 14 | 300 | Distributed RAM, Standard, embedded registers on (applied: 2-cycle read) (Simulink platform RFSoC4x2) |
| 10 | `simdata10` | 16 | 0 | 0 | 0 | 128 | 7 | 0 | 1 | 1 | 1 | 1 | 1 | 20 | 1 | 100 | 700 | Block RAM, Standard, depth 128, 16-bit data, no rst port (Simulink platform SNAP) |
| 11 | `simdata11` | 7 | 2 | 0 | 1 | 16 | 2 | 1 | 1 | 1 | 1 | 1 | 0 | 2 | 1 | 8 | 300 | Shift Register, Standard, embedded registers on (applied: 2-cycle read) (Simulink platform SNAP) |
