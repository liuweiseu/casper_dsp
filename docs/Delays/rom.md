# rom

## Description

A synchronous ROM of `2^ADDR_WIDTH` words × `DATA_WIDTH` bits, with a 1-cycle
registered read. Its contents come from `INIT_FILE`, which is loaded at
elaboration. Phase 3 will use it for twiddle coefficients produced by a
generator script. `dout` powers up to 0.

### `INIT_FILE` format

- One hexadecimal word per line (the `$readmemh` format).
- Give the file a `.mem` extension, so the same file is also a valid Xilinx
  XPM `MEMORY_INIT_FILE`.
- A relative path is resolved against the working directory of the simulator
  or synthesis tool. In this repo's cocotb flow that directory is
  `tests/sim_build/<Category>/<module>/`, so the test data uses
  `../../../test_data/...` paths.
- `""` (the default) makes every word 0.

## Platform Implementations

| `PLATFORM` | Implementation | Status |
|------------|----------------|--------|
| `"GENERIC"` (default) | Behavioral: `$readmemh` into an array | Simulated with cocotb in CI |
| `"XILINX"` | `platform/xilinx/rom_xilinx.sv`, which instantiates `xpm_memory_sprom` (`READ_LATENCY_A = 1`, `MEMORY_INIT_FILE = INIT_FILE`, or `"none"` when `INIT_FILE` is empty) | Checked for cycle equivalence with GENERIC in Vivado xsim; not in CI |
| `"ALTERA"` | `platform/altera/rom_altera.sv` | Stub: same interface, calls `$fatal`; TODO `altsyncram` `ROM` (Quartus needs `.mif`/Intel-HEX, so the init file must be converted) |

## Parameters

| Parameter    | Default     | Description |
|--------------|-------------|-------------|
| `DATA_WIDTH` | 8           | Word width |
| `ADDR_WIDTH` | 4           | Address width; depth = `2^ADDR_WIDTH` |
| `INIT_FILE`  | `""`        | Memory image path (see above) |
| `PLATFORM`   | `"GENERIC"` | `"GENERIC"`, `"XILINX"` or `"ALTERA"` |

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock |
| `addr` | input     | `ADDR_WIDTH` | Read address |
| `dout` | output    | `DATA_WIDTH` | `mem[addr]`, 1 cycle after `addr` |
