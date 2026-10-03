# x_cast

## Description

Combinational field reorder and sign extension inside `xeng_descramble` (`system_588`; identical copy `system_1107` in `xeng_descramble_4ant`). It is not a library block.

`din` holds 8 signed `N_BITS_IN`-bit fields, with field 0 at the LSB. Concat input `j` (1 = MSB) takes field `bit_offsets(j)`, sign-extended to `N_BITS_OUT` bits. The offsets are:

| `DEMUX_FACTOR` | `bit_offsets` |
|----------------|---------------|
| 8 | `[0 1 2 3 4 5 6 7]` |
| 4 | `[1 0 3 2 5 4 7 6]` |
| 2 | `[3 2 1 0 7 6 5 4]` |
| 1 | `[7 6 5 4 3 2 1 0]` |

So `bit_offsets(j) = (j−1) XOR (8/DEMUX_FACTOR − 1)`: the `DEMUX_FACTOR` blocks are reversed and the field order inside each block is kept. The dual-port RAM's narrow port reads LSB first, so this makes the descramble read each element MSB block first.

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `N_BITS_IN` | 16 | Field width W (mask `n_bits_in`) |
| `N_BITS_OUT` | 16 | Output field width P (mask `n_bits_out`). Must be ≥ `N_BITS_IN` |
| `FIX_PNT_POS` | 6 | Binary point (mask `fix_pnt_pos`). Only a type annotation; declared only |
| `DEMUX_FACTOR` | 8 | 1, 2, 4 or 8 (mask `demux_factor`) |

## Ports

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `din` | input | `8*N_BITS_IN` | 8 fields |
| `dout` | output | `8*N_BITS_OUT` | Reordered, sign-extended fields |
