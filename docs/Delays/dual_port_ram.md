# dual_port_ram

## Description

A true dual-port synchronous RAM of `2^ADDR_WIDTH` words × `DATA_WIDTH` bits.
Ports A and B are fully independent read/write ports that share one clock.
On every clock edge, each port reads `mem[addr_x]` into its output register
(1-cycle read latency) and, if `we_x = 1`, writes `din_x` to `mem[addr_x]`.
This is the memory for corner-turn and reorder buffers, which need a read and
a write at different addresses in the same cycle.

- **Same-port read-during-write** is **READ_FIRST**: `dout_x` receives the
  *old* contents.
- **Cross-port collisions are undefined.** A collision is both ports using the
  same address in the same cycle with at least one of them writing. Vendor
  block RAMs leave this undefined, so callers must avoid it. The GENERIC model
  returns the old data and lets port B's write win, but other platforms need
  not match.
- The memory contents and both outputs power up to 0.

## Platform Implementations

| `PLATFORM` | Implementation | Status |
|------------|----------------|--------|
| `"GENERIC"` (default) | Behavioral (inferred RAM; one process drives both ports) | Simulated with cocotb in CI |
| `"XILINX"` | `platform/xilinx/dual_port_ram_xilinx.sv`, which instantiates `xpm_memory_tdpram` (`CLOCKING_MODE = "common_clock"`, `WRITE_MODE_A/B = "read_first"`, `READ_LATENCY_A/B = 1`) | Checked for cycle equivalence with GENERIC in Vivado xsim, using collision-free stimulus; not in CI |
| `"ALTERA"` | `platform/altera/dual_port_ram_altera.sv` | Stub: same interface, calls `$fatal`; TODO `altsyncram` `BIDIR_DUAL_PORT` |

## Parameters

| Parameter    | Default     | Description |
|--------------|-------------|-------------|
| `DATA_WIDTH` | 8           | Word width (both ports) |
| `ADDR_WIDTH` | 4           | Address width; depth = `2^ADDR_WIDTH` |
| `PLATFORM`   | `"GENERIC"` | `"GENERIC"`, `"XILINX"` or `"ALTERA"` |

## Ports

| Port     | Direction | Width        | Description |
|----------|-----------|--------------|-------------|
| `clk`    | input     | 1            | Clock shared by both ports |
| `we_a`   | input     | 1            | Port A write enable |
| `addr_a` | input     | `ADDR_WIDTH` | Port A address |
| `din_a`  | input     | `DATA_WIDTH` | Port A write data |
| `dout_a` | output    | `DATA_WIDTH` | Port A read data (1-cycle latency) |
| `we_b`   | input     | 1            | Port B write enable |
| `addr_b` | input     | `ADDR_WIDTH` | Port B address |
| `din_b`  | input     | `DATA_WIDTH` | Port B write data |
| `dout_b` | output    | `DATA_WIDTH` | Port B read data (1-cycle latency) |
