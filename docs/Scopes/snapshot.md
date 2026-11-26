# snapshot

## Description

Captures `2^NSAMPLES` words of `din` into a shared BRAM under software
control, as the casper_library block `casper_library_scopes/snapshot`. Only
BRAM storage is implemented, with offset, circap, value, ext_arm, ext_circ
and provide_outputs all off. That is the configuration `bitfield_snapshot`
uses in tut_spec. Any other option stops elaboration with `$fatal`.

### Yellow blocks as ports

The HDL does not implement the block's three yellow blocks. Their
boundaries are ports instead:

| Yellow block | Type | HDL ports | Direction / width |
|--------------|------|-----------|-------------------|
| `<block>/ctrl` | swreg, From Processor | `ctrl` | input, 32 |
| `<block>/status` | swreg, To Processor | `status` | output, 32 (the value into the swreg) |
| `<block>/bram` | shared_bram (addr_width `NSAMPLES`, data_width `DATA_WIDTH`) | `bram_addr`, `bram_data_in`, `bram_we` | outputs, `NSAMPLES` / `DATA_WIDTH` / 1 |
| | | `bram_data_out` | input, `DATA_WIDTH` (unused: terminated in Simulink) |

The software names are `<design>_<block path>_ctrl`, `_status` and
`_bram`. The wrapper that connects the ports must keep them.

The swreg and shared_bram internals stay with the yellow blocks:

- the status swreg's own register (`cast_gw`, latency 1);
- the shared_bram's address manipulation (`calc_add`);
- the shared_bram's 32-bit word reordering (`munge_in` / `munge_out`, words
  reversed).

### ctrl bits

| Bit | Name | Meaning |
|-----|------|---------|
| 0 | enable | A rising edge arms a capture. Also drives `arm_out`. |
| 1 | trig_src | `1` = trigger at once, `0` = wait for `trig` |
| 2 | valid_src | `1` = write every cycle, `0` = write when `we` |
| 3 | circ | Circular capture (no effect without circap) |

### Behaviour

The behaviour was measured in Simulink; bits 0–2 of `ctrl` are delayed one
cycle.

1. **Arm:** a rising edge of enable (`init`) arms the capture and clears
   `go`. Two cycles later it sets `running` again; one cycle later it clears
   the address counter.
2. **Trigger:** while armed, the first `trig_sel` (`trig_src ? 1 : trig`)
   ends the armed state, and `go` goes high.
3. **Writes:** while `running`, each cycle with `we_sel & go` (registered)
   writes. The address counter steps `DATA_WIDTH/8` bytes per write.
4. **Done:** after `2^NSAMPLES` writes, the counter's top bit toggles. That
   blocks the write and clears `running`.
5. **BRAM port timing:**
   - `bram_we` and `bram_addr` (the word address) appear one cycle after the
     write decision;
   - `bram_data_in` is `din` delayed two cycles.
6. **status**, one cycle later:
   - bit 31: `running` (it powers up to 1);
   - bit `NSAMPLES + log2(DATA_WIDTH/8)`: `~running`;
   - the bits below: the byte count of the next write;
   - all other bits: 0.

The module is built from `delay`, `edge_detect`, `multiplexer`, `inverter`,
`logical`, `register`, `counter` and `slice`.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `STORAGE` | 0 | `0` bram (`1` dram: `$fatal`) (mask `storage`) |
| `NSAMPLES` | 10 | Capture depth `2^NSAMPLES` words (mask `nsamples`); `NSAMPLES + log2(DATA_WIDTH/8) ≤ 30` |
| `DATA_WIDTH` | 32 | `8`, `16`, `32`, `64` or `128` (mask `data_width`) |
| `OFFSET`, `CIRCAP`, `VALUE`, `EXT_ARM`, `EXT_CIRC`, `PROVIDE_OUTPUTS` | 0 | Must be 0 (mask defaults turn offset, circap, value, provide_outputs on) |
| `USE_DSP48` | 1 | Implementation only (mask `use_dsp48`) |
| `IN_WIDTH` | `DATA_WIDTH` | `din` width (HDL only): zero-extended or truncated to `DATA_WIDTH` |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | `IN_WIDTH` | Data |
| `we` | input | 1 | Write enable (used when `valid_src = 0`) |
| `trig` | input | 1 | Trigger (used when `trig_src = 0`) |
| `ctrl` | input | 32 | swreg `ctrl` value |
| `bram_data_out` | input | `DATA_WIDTH` | shared_bram data_out (unused) |
| `status` | output | 32 | Value into swreg `status` |
| `bram_addr` | output | `NSAMPLES` | shared_bram addr |
| `bram_data_in` | output | `DATA_WIDTH` | shared_bram data_in |
| `bram_we` | output | 1 | shared_bram we |
| `arm_out` | output | 1 | ctrl bit 0 (Simulink output 1) |
