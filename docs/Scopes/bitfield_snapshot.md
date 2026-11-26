# bitfield_snapshot

## Description

The casper_library block `casper_library_scopes/bitfield_snapshot` (mask type
`bitsnap`). It wraps a [`snapshot`](snapshot.md) with a typed input field and
input delays. `bitsnap_init.m` builds the block from these parts:

- an Assert on the input field (type check only);
- a `bus_create` of the fields;
- `pipeline`s of `SNAP_DELAY` registers on the data, `we` and `trig`;
- the snapshot, which it always builds with provide_outputs off. So
  `snap_provide_outputs` has no effect, and the only output is `arm_out`.

The HDL implements one io field, `din` (Simulink port `in_<io_name>`, e.g.
`in_d`), of `IO_WIDTH` bits. tut_spec's `adc_snapshot` uses a single
128-bit field `d`.

### Yellow blocks as ports

The snapshot inside is named `ss`. Its yellow blocks are ports, as in
`snapshot.sv`:

| HDL port | Direction / width | Yellow block | Software name |
|----------|-------------------|--------------|---------------|
| `ctrl` | input, 32 | swreg `<block>/ss/ctrl` (From Processor) | `<design>_<block>_ss_ctrl` (tut_spec: `adc_snapshot_ss_ctrl`) |
| `status` | output, 32 | swreg `<block>/ss/status` (To Processor) | `..._ss_status` (`adc_snapshot_ss_status`) |
| `bram_addr` | output, `SNAP_NSAMPLES` | shared_bram `<block>/ss/bram` addr | `..._ss_bram` (`adc_snapshot_ss_bram`) |
| `bram_data_in` | output, `SNAP_DATA_WIDTH` | shared_bram data_in | |
| `bram_we` | output, 1 | shared_bram we | |
| `bram_data_out` | input, `SNAP_DATA_WIDTH` | shared_bram data_out (unused) | |

### Latency

Measured from `din` / `we` / `trig`:

- `SNAP_DELAY + 2` cycles to `bram_data_in`;
- `SNAP_DELAY + 3` cycles to the `bram_we` / `bram_addr` of a write that `we`
  causes.

The `snapshot` page describes the ctrl bits and the status word.

### Options that are not implemented

`snap_storage = dram`, `snap_offset`, `snap_circap`, `snap_value`,
`snap_ext_arm` and `snap_ext_circ` stop elaboration with `$fatal`. The
`extra_*` fields are used only with `snap_value`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `IO_WIDTH` | 32 | Width of the input field (mask `io_widths`, one element) |
| `SNAP_STORAGE` | 0 | `0` bram (mask `snap_storage`) |
| `SNAP_NSAMPLES` | 10 | Capture depth `2^SNAP_NSAMPLES` (mask `snap_nsamples`) |
| `SNAP_DATA_WIDTH` | 32 | `8`/`16`/`32`/`64`/`128` (mask `snap_data_width`); `din` is zero-extended or truncated to it |
| `SNAP_OFFSET`, `SNAP_CIRCAP`, `SNAP_VALUE`, `SNAP_EXT_ARM`, `SNAP_EXT_CIRC` | 0 | Must be 0 |
| `SNAP_PROVIDE_OUTPUTS` | 0 | No effect |
| `SNAP_USE_DSP48` | 1 | Implementation only |
| `SNAP_DELAY` | 2 | Input pipeline depth (mask `snap_delay`) |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | `IO_WIDTH` | Input field (Simulink `in_<io_name>`) |
| `we` | input | 1 | Write enable |
| `trig` | input | 1 | Trigger |
| `ctrl` | input | 32 | swreg `ss/ctrl` value |
| `bram_data_out` | input | `SNAP_DATA_WIDTH` | shared_bram data_out (unused) |
| `status` | output | 32 | Value into swreg `ss/status` |
| `bram_addr`, `bram_data_in`, `bram_we` | output | `SNAP_NSAMPLES`, `SNAP_DATA_WIDTH`, 1 | shared_bram inputs |
| `arm_out` | output | 1 | ctrl bit 0 (Simulink `arm_out`) |
