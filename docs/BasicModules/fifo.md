# fifo

## Description

A synchronous FIFO matching the Xilinx System Generator **FIFO** block
(`xbsIndex_r4/FIFO`). Its behaviour was measured cycle by cycle in Simulink
(MATLAB R2021a, System Generator 2021.1, on SNAP and RFSoC4x2), and the RTL
follows the Sysgen block model `data/sysgen/block_models/xlFIFOFWFT.sgm`.
Sysgen uses that model for both read modes on non-Versal parts.

The parameters are the block's mask options. `DATA_WIDTH` is the only
addition: Simulink takes the data width from `din`. All flags and counts are
registered, so they change on the clock edge after the write or read that
causes them:

```
wr_en = we & en & ~rst_q & ~full          (a write to a full FIFO is dropped)
rd_en = re' & en & ~empty_int             (a read of an empty FIFO is ignored)
```

`rst_q` is `rst` delayed by `RST_LATENCY − 1` cycles, or `rst` itself when
`RST_LATENCY = 1`. `re'` is `re` in Standard mode; in FWFT mode it is the
prefetch request of the output buffer.

### Standard mode (`PERFORMANCE_OPTIONS = 0`)

- **dout** shows the word read with `re` on the next cycle. With
  `EMBEDDED_REGISTERS` it shows it two cycles later, whatever the memory
  type; that second register is not gated by `en`. `dout` holds its value
  between reads.
- **empty / full** refer to the stored words.
- **dcount** is the number of stored words modulo `DEPTH` (`log2(DEPTH)`
  bits), so it reads 0 when the FIFO is full.
- **percent_full** (`%full` in Simulink) is
  `floor(words · 2^PERCENT_NBITS / DEPTH)`, all ones while full. It is an
  unsigned fraction, `UFix_<n>_<n>`; the port carries its raw bits.

### First Word Fall Through (`PERFORMANCE_OPTIONS = 1`)

The head word is prefetched into a two-stage output buffer:

- `dout` already holds the head word while `empty = 0`, and `re`
  acknowledges it.
- The FIFO holds `DEPTH + 2` words.
- `dcount` has `log2(DEPTH) + 1` bits.
- `percent_full = floor(words · 2^PERCENT_NBITS / (2·DEPTH))`.
- `EMBEDDED_REGISTERS` has no effect.
- The output register is gated by `en`.

### Almost empty / almost full

`ae` and `af` are the programmable flags of `xpm_fifo_sync`. They are not
plain comparisons:

- `ae` sets when a read-only cycle brings the count to
  `ALMOST_EMPTY_THRESH`, and clears when a write-only cycle leaves it there.
- `af` sets when a write-only cycle reaches `ALMOST_FULL_THRESH`, and clears
  when a read-only cycle leaves it.
- In FWFT mode the RAM count is compared with the thresholds minus 2.

After reset `ae = 1` and `af = 0`.

### Reset

When `rst_q` is high:

- The pointers and flags are cleared: `empty = ae = 1`, `full = af = 0`,
  and the counts are 0.
- The output registers are cleared.
- The memory contents are kept.

Like every output, the cleared values appear on the cycle after `rst_q`.

### Reset busy

`rd_rst_busy` and `wr_rst_busy` follow the reset-busy logic of the Versal
model `xlFIFOXPM.sgm`. Both are high:

- for 5 cycles, starting the cycle after power-on;
- from the cycle after `rst = 1` until 4 cycles after `rst` falls.

They do not stall the FIFO. Simulink cannot simulate these ports on the
non-Versal parts CASPER uses, so this behaviour is unverified.

### Memory types

- `Distributed RAM` and `Shift Register` behave exactly as `Block RAM`
  (measured), including `EMBEDDED_REGISTERS`. The mask dialog greys out that
  option for them, but the model still applies it.
- `Shift Register` does not support FWFT.
- `Built-in FIFO` is modelled as Block RAM. Its Simulink model outputs NaN
  on `empty` / `full`, so there is no reference for it.

### Parameter checks

The module stops with `$fatal` on the configurations the Simulink mask
rejects:

- a threshold out of `[3, DEPTH−3]` (Standard) or `[5, DEPTH−5]` (FWFT),
  when its port is on;
- `PERCENT_NBITS > log2(DEPTH)`;
- `DEPTH` not a power of two from 16 to 4M;
- Shift Register with FWFT.

### Simulink limits

These configurations have no Simulink reference (`[[unsupported]]` in the
mapping):

- `RST_LATENCY = 0` with the `rst` port on;
- `Built-in FIFO`;
- the reset-busy ports.

On UltraScale / UltraScale+ parts (for example RFSoC4x2), Simulink simulates
the block only with `rst` on and `rst_latency ≥ 2`. The HDL accepts all of
these configurations.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `DATA_WIDTH` | 8 | `din` / `dout` width (HDL only; inherited in Simulink) |
| `MEM_TYPE` | 0 | `0` Block RAM, `1` Distributed RAM, `2` Shift Register, `3` Built-in FIFO |
| `PERFORMANCE_OPTIONS` | 0 | `0` Standard FIFO, `1` First Word Fall Through |
| `EMBEDDED_REGISTERS` | 0 | Extra output register (Standard mode) |
| `DEPTH` | 16 | Words, a power of two from 16 to 4M (mask `16` … `1K` … `4M`) |
| `PERCENT_NBITS` | 1 | Width of `percent_full`, at most `log2(DEPTH)` |
| `RST` | 0 | `1` = `rst` port |
| `RST_LATENCY` | 1 | Cycles from `rst` to the reset taking effect |
| `EN` | 0 | `1` = `en` port |
| `USE_DCOUNT` | 0 | `1` = `dcount` port |
| `USE_PERCENT_FULL_PORT` | 1 | `1` = `percent_full` port |
| `USE_ALMOST_EMPTY`, `ALMOST_EMPTY_THRESH` | 0, 2 | `ae` port and its threshold |
| `USE_ALMOST_FULL`, `ALMOST_FULL_THRESH` | 0, 14 | `af` port and its threshold |
| `USE_RD_RST_BUSY`, `USE_WR_RST_BUSY` | 0, 0 | Reset-busy ports |

## Ports

Simulink shows only the enabled optional ports, in the order
`din, we, re, rst, en → dout, empty, %full, full, dcount, ae, af,
rd_rst_busy, wr_rst_busy`. The HDL always has every port:

- A disabled input is ignored (`rst` and `en` have defaults).
- A disabled output is driven 0.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | Clock |
| `din` | input | `DATA_WIDTH` | Write data |
| `we` | input | 1 | Write enable |
| `re` | input | 1 | Read enable (FWFT: acknowledge the head word) |
| `rst` | input | 1 | Reset, delayed by `RST_LATENCY − 1` (`RST = 1`) |
| `en` | input | 1 | Enable for writes, reads and the FWFT output register (`EN = 1`) |
| `dout` | output | `DATA_WIDTH` | Read data |
| `empty` | output | 1 | No word to read |
| `percent_full` | output | `PERCENT_NBITS` | Fill level, `%full` in Simulink |
| `full` | output | 1 | No room to write |
| `dcount` | output | `log2(DEPTH)` (+1 in FWFT) | Word count |
| `ae`, `af` | output | 1 | Almost empty / almost full |
| `rd_rst_busy`, `wr_rst_busy` | output | 1 | Reset busy |
