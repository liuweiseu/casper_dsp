# single_port_ram

## Description

A single-port synchronous RAM of `2^ADDR_WIDTH` words × `DATA_WIDTH` bits,
with a 1-cycle registered read. On every clock edge it reads `mem[addr]` into
the output register and, if `we = 1`, writes `din` to `mem[addr]`.

- **Read-during-write** (`we = 1`) is **READ_FIRST**: `dout` receives the *old*
  contents of `mem[addr]`.
- The memory contents power up to 0, `dout` to `INIT_REG`.
- `RST` / `EN` / `INIT_REG` follow the built Xilinx block (latency 1, checked against Simulink: `rst` also acts while `en` = 0, unlike the literal `xlSPRAM.sgm`) and are GENERIC only
  (`$fatal` on other platforms).

## Platform Implementations

`PLATFORM` selects the implementation. All three platforms share the same
parameters, ports and behavior.

| `PLATFORM` | Implementation | Status |
|------------|----------------|--------|
| `"GENERIC"` (default) | Behavioral (inferred RAM), inside `rtl/Delays/single_port_ram.sv` | Simulated with cocotb in CI |
| `"XILINX"` | `platform/xilinx/single_port_ram_xilinx.sv`, which instantiates `xpm_memory_spram` (`WRITE_MODE_A = "read_first"`, `READ_LATENCY_A = 1`, `MEMORY_PRIMITIVE = "auto"`) | Checked for cycle equivalence with GENERIC in Vivado xsim (`platform/xilinx/sim/run_xsim_equiv.sh`); not in CI |
| `"ALTERA"` | `platform/altera/single_port_ram_altera.sv` | Stub: same interface, calls `$fatal`; TODO `altsyncram` `SINGLE_PORT` |

Only the GENERIC code is in `rtl/`. A XILINX or ALTERA build must also add the
matching `platform/<vendor>/` file and the vendor library (for Xilinx, the XPM
sources).

## Parameters

| Parameter    | Default     | Description |
|--------------|-------------|-------------|
| `DATA_WIDTH` | 8           | Word width |
| `ADDR_WIDTH` | 4           | Address width; depth = `2^ADDR_WIDTH` |
| `RST`        | 0           | `1` enables `rst` (Xilinx `rst` option): `dout` <= `INIT_REG` instead of the read, whatever `en` is; an enabled write still happens |
| `EN`         | 0           | `1` enables `en` (Xilinx `en` option): `en` = 0 freezes the edge (no read, no write, `dout` holds) |
| `INIT_REG`   | 0           | Output-register word at power-up and on `rst` (raw bits; Xilinx `init_reg`) |
| `PLATFORM`   | `"GENERIC"` | `"GENERIC"`, `"XILINX"` or `"ALTERA"` (any other value stops elaboration with `$fatal`) |

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock |
| `we`   | input     | 1            | Write enable |
| `addr` | input     | `ADDR_WIDTH` | Read/write address |
| `din`  | input     | `DATA_WIDTH` | Write data |
| `rst`  | input     | 1            | Output reset (used when `RST = 1`; defaults to 0) |
| `en`   | input     | 1            | Enable (used when `EN = 1`; defaults to 1) |
| `dout` | output    | `DATA_WIDTH` | Read data, 1 cycle after `addr` |
