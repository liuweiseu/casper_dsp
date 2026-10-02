# complex_multiplier

## Description

Fixed-point complex multiplication, composed entirely of
[`multiplier`](../Bus/multiplier.md) and [`adder_subtractor`](../Bus/adder_subtractor.md)
instances:

```
(dout_re + j·dout_im) = convert( (a_re + j·a_im) · (b_re + j·b_im) )
```

`MULT_SPEC` selects the structure through `generate`, following
casper_library's `twiddle_general_4mult` / `twiddle_general_3mult`.

All intermediate products and sums are kept at full precision, and the only
requantization is in the final adder stage. The two structures therefore give
**bit-identical outputs** and differ only in latency and resources.

### `MULT_SPEC = 0`: 4-multiply form

```
a_re,b_re ─► multiplier ─┐
a_im,b_im ─► multiplier ─┴► adder_subtractor (sub) ─► dout_re
a_re,b_im ─► multiplier ─┐
a_im,b_re ─► multiplier ─┴► adder_subtractor (add) ─► dout_im
```

Latency = `MULT_LATENCY + ADD_LATENCY`.

### `MULT_SPEC = 1`: 3-multiply (Karatsuba-style) form

```
k1 = b_re · (a_re + a_im)
k2 = a_re · (b_im − b_re)
k3 = a_im · (b_re + b_im)
dout_re = k1 − k3
dout_im = k1 + k2
```

Three pre-adders (`adder_subtractor`, `ADD_LATENCY` each) feed three
multipliers, followed by two post-adders. The operands that bypass the
pre-adders (`b_re`, `a_re`, `a_im`) are delay-matched with `BasicModules/delay`.
Latency = `ADD_LATENCY + MULT_LATENCY + ADD_LATENCY`.

## Parameters

| Parameter      | Default | Description |
|----------------|---------|-------------|
| `N_BITS_A`     | 18      | Word width of `a_re` and `a_im` |
| `BIN_PT_A`     | 17      | Binary point of `a_re` and `a_im` |
| `TYPE_A`       | 1       | Type of `a_re` and `a_im`: `0`=unsigned, `1`=signed |
| `N_BITS_B`     | 18      | Word width of `b_re` and `b_im` |
| `BIN_PT_B`     | 17      | Binary point of `b_re` and `b_im` |
| `TYPE_B`       | 1       | Type of `b_re` and `b_im`: `0`=unsigned, `1`=signed |
| `N_BITS_OUT`   | 18      | Word width of `dout_re` and `dout_im` |
| `BIN_PT_OUT`   | 17      | Binary point of `dout_re` and `dout_im` |
| `TYPE_OUT`     | 1       | Output type: `0`=unsigned, `1`=signed |
| `QUANTIZATION` | 2       | `0`=truncate, `1`=round half away from zero, `2`=round half to even |
| `OVERFLOW`     | 1       | `0`=wrap, `1`=saturate, `2`=flag as error (treated as wrap) |
| `MULT_SPEC`    | 0       | `0`=4-multiply form, `1`=3-multiply form |
| `MULT_LATENCY` | 3       | Pipeline stages of each `multiplier` (casper_library `mult_latency`) |
| `ADD_LATENCY`  | 2       | Pipeline stages of each `adder_subtractor` (casper_library `add_latency`) |

The real and imaginary parts of each operand share one format, as in
casper_library's `cmult` / `bus_mult`. The module computes the total latency as
the localparam `LATENCY`.

## Ports

| Port      | Direction | Width        | Description |
|-----------|-----------|--------------|-------------|
| `clk`     | input     | 1            | Clock |
| `a_re`    | input     | `N_BITS_A`   | Real part of `a` |
| `a_im`    | input     | `N_BITS_A`   | Imaginary part of `a` |
| `b_re`    | input     | `N_BITS_B`   | Real part of `b` |
| `b_im`    | input     | `N_BITS_B`   | Imaginary part of `b` |
| `dout_re` | output    | `N_BITS_OUT` | Real part of the product |
| `dout_im` | output    | `N_BITS_OUT` | Imaginary part of the product |

## Functional Description

Intermediate formats (all signed and exact):

| Signal | Width | Binary point |
|--------|-------|--------------|
| 4-mult products | `N_BITS_A + N_BITS_B + 2` | `BIN_PT_A + BIN_PT_B` |
| 3-mult pre-sum `a_re + a_im` | `N_BITS_A + 2` | `BIN_PT_A` |
| 3-mult pre-sums `b_im − b_re`, `b_re + b_im` | `N_BITS_B + 2` | `BIN_PT_B` |
| 3-mult products `k1`, `k2`, `k3` | `N_BITS_A + N_BITS_B + 4` | `BIN_PT_A + BIN_PT_B` |

Quantization and overflow are applied only by the two output `adder_subtractor`
instances, using the semantics of [`convert`](../Bus/convert.md).
