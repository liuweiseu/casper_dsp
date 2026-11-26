# single_port_ram

## Description

A single-port synchronous RAM matching the Xilinx System Generator block
**Single Port RAM** (`xbsIndex_r4/Single Port RAM`). It has `DEPTH` words of
`DATA_WIDTH` bits (`DEPTH` defaults to `2^ADDR_WIDTH`) and implements every
behavioural mask option.

The behaviour was measured cycle by cycle in Simulink: MATLAB R2021a,
System Generator 2021.1, on SNAP, and on RFSoC4x2 for Ultra RAM. Where the
measurements differ from the literal `xlSPRAM.sgm` text, the RTL follows the
measurements.

The defaults keep the earlier fixed behaviour: Block RAM, Read Before Write
and latency 1. So existing instances (`delay_bram`, `reorder`, `fft_stage_n`)
are unchanged. Read Before Write is not the mask default (Read After Write).

### Read pipeline (`LATENCY ≥ 1`)

`dout` is the last of `LATENCY` registers.

**Stage 0** loads on an enabled edge (`en = 1`, or no `en` port):

| `we` | `WRITE_MODE` | Stage 0 loads |
|------|--------------|---------------|
| 0 | any | `mem[addr]` |
| 1 | 0 Read After Write | `din` |
| 1 | 1 Read Before Write | `mem[addr]` (old contents) |
| 1 | 2 No Read On Write | its own value (unchanged) |

An enabled edge with `we = 1` also writes `din` to `mem[addr]`.

**Stages 1 … `LATENCY − 1`** shift on enabled edges. There are two
exceptions, where they shift on every edge and only stage 0 sees `en`:

- **Ultra RAM**;
- **Block RAM with `OPTIMIZE_LATENCY`** (it has no effect on Distributed
  memory).

### Reset (`RST = 1`)

`rst` acts on the last stage only, whatever `en` is. An enabled write still
happens.

- **Block RAM:**
  - It loads `INIT_REG`.
  - `INIT_REG` is also the power-on value of the last stage. Without `rst`,
    the last stage powers up to 0.
  - The other stages power up to 0.
- **Ultra RAM:**
  - It clears the last stage. With `LATENCY = 1` this happens only on an
    enabled edge.
  - In every case `dout` reads 0 on the cycle after `rst`.
  - `INIT_REG` is ignored: `dout` powers up to 0.
- **Distributed memory:**
  - It has no `rst` port in Simulink, even with `rst` checked.
  - `RST` and `INIT_REG` are ignored.

With No Read On Write and `LATENCY = 1`, stage 0 is the output register. So
after a reset it repeats `INIT_REG` on writes.

### Combinational read (`LATENCY = 0`)

`dout = mem[addr]`, and `we = 1` writes `din` on the clock edge. Simulink
allows this only for Distributed memory with Read Before Write and no `en`
port.

### Contents

- **Initial contents:** the memory powers up to the raw hex words of
  `INIT_FILE` (`$readmemh`). Words beyond the end of the file are 0, which
  matches a short `initVector`.
- **No `INIT_FILE`:** with `INIT_FILE = ""` all words are 0.
- **Ultra RAM:** ignores `INIT_FILE`, as Simulink ignores `initVector`.
- **Out-of-range addresses:** Simulink stops with an error on
  `addr > depth − 1`. The HDL reads 0 and does not write.

### Parameter checks

The module stops with `$fatal` on the combinations Simulink rejects:

- `LATENCY = 0` with Block RAM or Ultra RAM ("must be greater than 0");
- `LATENCY = 0` with a write mode other than Read Before Write;
- `LATENCY = 0` with an `en` port;
- Distributed memory with No Read On Write;
- `DEPTH` outside `1 … 2^ADDR_WIDTH`;
- an invalid `MEM_TYPE` or `WRITE_MODE`.

### Differences from Simulink

The mapping in the RTL header lists them all. The main ones:

- **Raw values:** `INIT_FILE` and `INIT_REG` are raw words. Simulink
  quantizes the real `initVector` / `init_reg` to the data type with Round
  (half away from zero) and Saturate, and truncates `initVector` to `depth`.
  The generator or exporter must apply that conversion. For UFix_N_0 data,
  the raw words and the real values are the same.
- **Ultra RAM:** it exists only on UltraScale+ parts. The HDL has no part
  parameter.

## Platform Implementations

`PLATFORM` selects the implementation.

| `PLATFORM` | Implementation | Status |
|------------|----------------|--------|
| `"GENERIC"` (default) | Behavioral (inferred RAM), inside `rtl/Delays/single_port_ram.sv`; every option | Simulated with cocotb in CI |
| `"XILINX"` | `platform/xilinx/single_port_ram_xilinx.sv`, which instantiates `xpm_memory_spram` (`WRITE_MODE_A = "read_first"`, `READ_LATENCY_A = 1`, `MEMORY_PRIMITIVE = "auto"`) | Default configuration only; checked for cycle equivalence with GENERIC in Vivado xsim (`platform/xilinx/sim/run_xsim_equiv.sh`); not in CI |
| `"ALTERA"` | `platform/altera/single_port_ram_altera.sv` | Stub: same interface, calls `$fatal`; TODO `altsyncram` `SINGLE_PORT` |

On XILINX and ALTERA, any non-default option stops elaboration with
`$fatal`. The default configuration is Block RAM, Read Before Write,
`LATENCY = 1`, `DEPTH = 2^ADDR_WIDTH`, with no `rst` / `en` / `INIT_REG` /
`INIT_FILE` / `OPTIMIZE_LATENCY`.

Only the GENERIC code is in `rtl/`. A XILINX or ALTERA build must also add the
matching `platform/<vendor>/` file and the vendor library (for Xilinx, the XPM
sources).

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 8 | Word width (HDL only; inherited in Simulink) |
| `ADDR_WIDTH` | 4 | `addr` width (HDL only; inherited in Simulink); must hold `DEPTH − 1` |
| `DEPTH` | `2^ADDR_WIDTH` | Number of words (mask `depth`); need not be a power of two |
| `MEM_TYPE` | 1 | `0` Distributed memory, `1` Block RAM, `2` Ultra RAM (mask `distributed_mem`) |
| `WRITE_MODE` | 1 | `0` Read After Write, `1` Read Before Write, `2` No Read On Write (mask `write_mode`; mask default is 0) |
| `LATENCY` | 1 | Read latency in cycles (mask `latency`); `0` = combinational read |
| `RST` | 0 | `1` enables `rst` (mask `rst`) |
| `EN` | 0 | `1` enables `en` (mask `en`) |
| `OPTIMIZE_LATENCY` | 0 | `1` = mask `optimize_latency` (Block RAM: stages after the first ignore `en`) |
| `INIT_REG` | 0 | Output-register word at power-up and on `rst` (raw bits; mask `init_reg`) |
| `INIT_FILE` | `""` | `$readmemh` image of the initial contents (raw hex words; replaces `initVector`) |
| `PLATFORM` | `"GENERIC"` | `"GENERIC"`, `"XILINX"` or `"ALTERA"` (any other value stops elaboration with `$fatal`) |

The mask's `optimize` (Area / Speed / Power) only affects implementation, and
Simulink greys it out for every memory type.

## Ports

| Port   | Direction | Width        | Description |
|--------|-----------|--------------|-------------|
| `clk`  | input     | 1            | Clock |
| `we`   | input     | 1            | Write enable |
| `addr` | input     | `ADDR_WIDTH` | Read/write address |
| `din`  | input     | `DATA_WIDTH` | Write data (Simulink `data`) |
| `rst`  | input     | 1            | Output reset (used when `RST = 1`; defaults to 0) |
| `en`   | input     | 1            | Enable (used when `EN = 1`; defaults to 1) |
| `dout` | output    | `DATA_WIDTH` | Read data, `LATENCY` cycles after `addr` |
